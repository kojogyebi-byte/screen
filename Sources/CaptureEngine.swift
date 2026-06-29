//
//  CaptureEngine.swift
//  ScreenExtend
//
//  Captures a specific display with ScreenCaptureKit and encodes the frames to
//  H.264 (hardware) with VideoToolbox. Emits two callbacks:
//    onConfig(Data)  -> Annex-B SPS/PPS (sent before each keyframe)
//    onFrame(Data, isKeyframe) -> Annex-B access unit
//

import Foundation
import ScreenCaptureKit
import VideoToolbox
import CoreMedia
import CoreVideo

final class CaptureEngine: NSObject, SCStreamDelegate, SCStreamOutput {

    private var stream: SCStream?
    private var session: VTCompressionSession?
    private let outputQueue = DispatchQueue(label: "com.shamaapps.screenextend.capture")

    private var width: Int = 0
    private var height: Int = 0
    private var fps: Int = 30

    private var forceKeyframe = false
    private var frameIndex: Int64 = 0

    var onConfig: ((Data) -> Void)?
    var onFrame: ((Data, Bool) -> Void)?
    var onError: ((String) -> Void)?

    private static let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

    // MARK: Lifecycle

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int) async {
        self.width = width
        self.height = height
        self.fps = fps

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                               onScreenWindowsOnly: false)
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                onError?("Could not find the virtual display in ScreenCaptureKit. Is Screen Recording permission granted?")
                return
            }

            try setupEncoder()

            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.queueDepth = 5
            config.showsCursor = true
            config.scalesToFit = true

            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            try await s.startCapture()
            stream = s
            requestKeyframe()
            NSLog("[ScreenExtend] Capture started \(width)x\(height)@\(fps)")
        } catch {
            onError?("Capture failed: \(error.localizedDescription)")
        }
    }

    func stop() async {
        if let s = stream {
            try? await s.stopCapture()
        }
        stream = nil
        if let session = session {
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    func requestKeyframe() {
        outputQueue.async { self.forceKeyframe = true }
    }

    // MARK: Encoder setup

    private func setupEncoder() throws {
        var newSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,           // we use the block-based encode API
            refcon: nil,
            compressionSessionOut: &newSession)

        guard status == noErr, let session = newSession else {
            throw NSError(domain: "ScreenExtend", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "VTCompressionSessionCreate failed (\(status))"])
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: NSNumber(value: fps * 4))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             value: NSNumber(value: 4))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: NSNumber(value: fps))
        // Bitrate budget scaled to resolution (~0.1 bits/px/frame baseline).
        let bitrate = max(4_000_000, Int(Double(width * height) * Double(fps) * 0.10))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: NSNumber(value: bitrate))

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let session = session,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Drop frames flagged as not-complete / blank by SCK.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let info = attachments.first,
           let statusRaw = info[.status] as? Int,
           let frameStatus = SCFrameStatus(rawValue: statusRaw),
           frameStatus != .complete {
            return
        }

        let pts = CMTime(value: frameIndex, timescale: CMTimeScale(fps))
        frameIndex += 1

        var props: CFDictionary?
        if forceKeyframe {
            forceKeyframe = false
            props = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
        }

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: props,
            infoFlagsOut: nil) { [weak self] status, _, sample in
                guard let self = self, status == noErr, let sample = sample else { return }
                self.handleEncoded(sample)
            }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?("Capture stopped: \(error.localizedDescription)")
    }

    // MARK: Encoded output -> Annex-B

    private func handleEncoded(_ sample: CMSampleBuffer) {
        let isKeyframe = Self.isKeyframe(sample)

        if isKeyframe, let fmt = CMSampleBufferGetFormatDescription(sample),
           let config = Self.annexBParameterSets(fmt) {
            onConfig?(config)
        }

        guard let annexB = Self.annexBAccessUnit(sample) else { return }
        onFrame?(annexB, isKeyframe)
    }

    private static func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[CFString: Any]],
              let first = attachments.first else { return true }
        // NotSync present and true -> delta frame; absent/false -> keyframe.
        if let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }
        return true
    }

    /// Builds Annex-B (start-code prefixed) SPS + PPS from the format desc.
    private static func annexBParameterSets(_ fmt: CMFormatDescription) -> Data? {
        var count = 0
        var nalHeaderLength: Int32 = 4
        // First call: how many parameter sets?
        let s0 = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            fmt, parameterSetIndex: 0, parameterSetPointerOut: nil,
            parameterSetSizeOut: nil, parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: &nalHeaderLength)
        guard s0 == noErr, count > 0 else { return nil }

        var out = Data()
        for i in 0..<count {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            let st = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                fmt, parameterSetIndex: i, parameterSetPointerOut: &ptr,
                parameterSetSizeOut: &size, parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil)
            guard st == noErr, let ptr = ptr, size > 0 else { continue }
            out.append(contentsOf: startCode)
            out.append(ptr, count: size)
        }
        return out.isEmpty ? nil : out
    }

    /// Converts the AVCC (length-prefixed) sample data to Annex-B.
    private static func annexBAccessUnit(_ sample: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let st = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                             totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard st == noErr, let dataPointer = dataPointer, totalLength > 0 else { return nil }

        let bytes = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: UInt8.self)
        var out = Data(capacity: totalLength + 16)
        var offset = 0
        let headerLen = 4   // VideoToolbox emits 4-byte AVCC length prefixes

        while offset + headerLen <= totalLength {
            var nalLength = 0
            for j in 0..<headerLen {
                nalLength = (nalLength << 8) | Int(bytes[offset + j])
            }
            offset += headerLen
            if nalLength <= 0 || offset + nalLength > totalLength { break }
            out.append(contentsOf: startCode)
            out.append(bytes + offset, count: nalLength)
            offset += nalLength
        }
        return out.isEmpty ? nil : out
    }
}

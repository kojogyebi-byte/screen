//
//  AppModel.swift
//  ScreenExtend
//

import Foundation
import SwiftUI
import CoreGraphics

struct DisplayPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let width: Int
    let height: Int
    static let all: [DisplayPreset] = [
        .init(name: "1920 × 1200  (16:10)", width: 1920, height: 1200),
        .init(name: "2360 × 1640  (iPad Air)", width: 2360, height: 1640),
        .init(name: "2560 × 1600  (16:10 QHD)", width: 2560, height: 1600),
        .init(name: "1280 × 800   (low latency)", width: 1280, height: 800),
        .init(name: "1920 × 1080  (16:9)", width: 1920, height: 1080),
    ]
}

@MainActor
final class AppModel: ObservableObject {

    @Published var isRunning = false
    @Published var statusText = "Idle"
    @Published var clientConnected = false
    @Published var ipAddresses: [String] = []
    @Published var hasScreenRecording = false
    @Published var hasAccessibility = false
    @Published var lastError: String?

    @Published var selectedPreset: DisplayPreset = DisplayPreset.all[0]
    @Published var fps: Int = 30
    @Published var hiDPI: Bool = false

    let port: UInt16 = 53121

    private let vdisplay = VirtualDisplayShim()
    private let capture = CaptureEngine()
    private let injector = InputInjector()
    private lazy var server = StreamServer(port: port)

    private var latestConfig: Data?

    init() {
        refreshPermissions()
        ipAddresses = NetworkInfo.localIPv4Addresses()
        wireCallbacks()
    }

    func refreshPermissions() {
        hasScreenRecording = Permissions.hasScreenRecording()
        hasAccessibility = Permissions.hasAccessibility()
    }

    var virtualDisplaySupported: Bool { VirtualDisplayShim.isSupported() }

    private func wireCallbacks() {
        capture.onConfig = { [weak self] config in
            guard let self = self else { return }
            self.latestConfig = config
            self.server.send(.config, config)
        }
        capture.onFrame = { [weak self] frame, isKey in
            guard let self = self else { return }
            var payload = Data([isKey ? 1 : 0])
            payload.append(frame)
            self.server.send(.frame, payload)
        }
        capture.onError = { [weak self] msg in
            Task { @MainActor in self?.lastError = msg; self?.statusText = msg }
        }

        server.onStateChange = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .stopped:    self?.statusText = "Stopped"
                case .listening:  self?.statusText = "Waiting for tablet…"
                case .connected:  self?.statusText = "Tablet connected"
                }
            }
        }
        server.onClientConnected = { [weak self] in
            Task { @MainActor in
                self?.clientConnected = true
                self?.sendHandshake()
                self?.capture.requestKeyframe()
            }
        }
        server.onClientDisconnected = { [weak self] in
            Task { @MainActor in self?.clientConnected = false }
        }
        server.onPointer = { [weak self] action, nx, ny, dx, dy in
            self?.injector.handle(action: action, nx: nx, ny: ny, dx: dx, dy: dy)
        }
    }

    private func sendHandshake() {
        let info: [String: Int] = ["w": selectedPreset.width,
                                   "h": selectedPreset.height,
                                   "fps": fps]
        if let data = try? JSONSerialization.data(withJSONObject: info) {
            server.send(.info, data)
        }
    }

    // MARK: Start / Stop

    func start() {
        lastError = nil
        refreshPermissions()

        guard virtualDisplaySupported else {
            lastError = "This macOS build does not expose the virtual-display API. Screen extension is unavailable."
            return
        }

        if !hasScreenRecording {
            Permissions.requestScreenRecording()
            statusText = "Grant Screen Recording, then press Start again."
            // Re-check shortly after the prompt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.refreshPermissions()
            }
            return
        }
        if !hasAccessibility {
            Permissions.requestAccessibility()
            // Not fatal for video; only needed for input. Continue but warn.
        }

        let w = selectedPreset.width
        let h = selectedPreset.height
        let id = vdisplay.createDisplay(withName: "ScreenExtend Display",
                                        width: UInt32(w), height: UInt32(h), hiDPI: hiDPI)
        guard id != 0 else {
            lastError = "Failed to create the virtual display."
            return
        }
        injector.setDisplay(id)
        server.start()

        Task {
            await capture.start(displayID: id, width: w, height: h, fps: fps)
        }
        isRunning = true
        statusText = "Waiting for tablet…"
    }

    func stop() {
        Task {
            await capture.stop()
            server.stop()
            vdisplay.destroyDisplay()
            await MainActor.run {
                isRunning = false
                clientConnected = false
                statusText = "Idle"
            }
        }
    }
}

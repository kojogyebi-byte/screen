//
//  AppModel.swift
//  Expanse (ScreenExtend target)
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
        .init(name: "1920 × 1200  ·  16:10", width: 1920, height: 1200),
        .init(name: "2360 × 1640  ·  iPad Air", width: 2360, height: 1640),
        .init(name: "2560 × 1600  ·  16:10 QHD", width: 2560, height: 1600),
        .init(name: "1280 × 800  ·  low latency", width: 1280, height: 800),
        .init(name: "1920 × 1080  ·  16:9", width: 1920, height: 1080),
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

    // Resolution mode
    @Published var autoResolution = true
    @Published var selectedPreset: DisplayPreset = DisplayPreset.all[0]
    @Published var fps: Int = 30
    @Published var hiDPI: Bool = false

    // Detected tablet (populated from its HELLO message)
    @Published var tabletName: String = ""
    @Published var tabletNativeText: String = ""
    @Published var activeResolutionText: String = ""

    // Tablets discovered on the local network (Bonjour)
    @Published var discoveredTablets: [DiscoveredTablet] = []
    @Published var selectedTabletID: String?

    let port: UInt16 = 53121

    private let vdisplay = VirtualDisplayShim()
    private let capture = CaptureEngine()
    private let injector = InputInjector()
    private lazy var server = StreamServer(port: port)
    private let discovery = TabletDiscovery()

    private var latestConfig: Data?
    private var activeWidth = 0
    private var activeHeight = 0

    init() {
        refreshPermissions()
        ipAddresses = NetworkInfo.localIPv4Addresses()
        wireCallbacks()
        discovery.onChange = { [weak self] tablets in
            Task { @MainActor in
                self?.discoveredTablets = tablets
                // Drop a stale selection if that tablet went away.
                if let sel = self?.selectedTabletID, !tablets.contains(where: { $0.id == sel }) {
                    self?.selectedTabletID = nil
                }
            }
        }
        discovery.start()
    }

    func refreshPermissions() {
        hasScreenRecording = Permissions.hasScreenRecording()
        hasAccessibility = Permissions.hasAccessibility()
    }

    var virtualDisplaySupported: Bool { VirtualDisplayShim.isSupported() }

    // MARK: Resolution helpers

    /// Chooses a stream resolution that matches the tablet's aspect ratio,
    /// capping the long edge for bandwidth and keeping dimensions even (H.264).
    static func bestResolution(_ w: Int, _ h: Int) -> (Int, Int) {
        guard w > 0, h > 0 else { return (1920, 1200) }
        let maxLong = 2560
        var tw = w, th = h
        let longEdge = max(tw, th)
        if longEdge > maxLong {
            let scale = Double(maxLong) / Double(longEdge)
            tw = Int((Double(tw) * scale).rounded())
            th = Int((Double(th) * scale).rounded())
        }
        tw = max(640, tw - (tw % 2))
        th = max(480, th - (th % 2))
        return (tw, th)
    }

    // MARK: Callback wiring

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
                case .stopped:   self?.statusText = "Stopped"
                case .listening: if self?.isRunning == true { self?.statusText = "Waiting for tablet…" }
                case .connected: break
                }
            }
        }
        server.onClientConnected = { [weak self] in
            Task { @MainActor in self?.clientConnected = true }
        }
        server.onClientDisconnected = { [weak self] in
            Task { @MainActor in
                self?.clientConnected = false
                if self?.isRunning == true { self?.statusText = "Waiting for tablet…" }
            }
        }
        server.onPointer = { [weak self] action, nx, ny, dx, dy in
            self?.injector.handle(action: action, nx: nx, ny: ny, dx: dx, dy: dy)
        }
        server.onHello = { [weak self] w, h, dpi, name in
            Task { @MainActor in self?.handleTabletHello(w: w, h: h, dpi: dpi, name: name) }
        }
    }

    private func sendHandshake() {
        let w = activeWidth > 0 ? activeWidth : selectedPreset.width
        let h = activeHeight > 0 ? activeHeight : selectedPreset.height
        let info: [String: Int] = ["w": w, "h": h, "fps": fps]
        if let data = try? JSONSerialization.data(withJSONObject: info) {
            server.send(.info, data)
        }
    }

    private func handleTabletHello(w: Int, h: Int, dpi: Int, name: String) {
        tabletName = name
        if w > 0, h > 0 { tabletNativeText = "\(w) × \(h)" }
        guard isRunning else { return }

        if autoResolution && activeWidth == 0 {
            let (cw, ch) = Self.bestResolution(w, h)
            guard createDisplayAndCapture(cw, ch) else { return }
        }
        sendHandshake()
        capture.requestKeyframe()
        statusText = name.isEmpty ? "Tablet connected" : "Streaming to \(name)"
    }

    // MARK: Start / Stop

    @discardableResult
    private func createDisplayAndCapture(_ w: Int, _ h: Int) -> Bool {
        let id = vdisplay.createDisplay(withName: "Expanse Display",
                                        width: UInt32(w), height: UInt32(h), hiDPI: hiDPI)
        guard id != 0 else {
            lastError = "Failed to create the virtual display."
            return false
        }
        activeWidth = w
        activeHeight = h
        activeResolutionText = "\(w) × \(h)"
        injector.setDisplay(id)
        Task { await capture.start(displayID: id, width: w, height: h, fps: fps) }
        return true
    }

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.refreshPermissions()
            }
            return
        }
        if !hasAccessibility {
            Permissions.requestAccessibility()
        }

        activeWidth = 0
        activeHeight = 0
        activeResolutionText = ""
        server.start()
        isRunning = true

        if autoResolution {
            statusText = "Waiting for tablet…"
            // The virtual display is created once the tablet reports its size.
        } else {
            guard createDisplayAndCapture(selectedPreset.width, selectedPreset.height) else {
                isRunning = false
                server.stop()
                return
            }
            statusText = "Waiting for tablet…"
        }

        triggerSelectedTablet()
    }

    /// If the user picked a discovered tablet, tell it to connect to this Mac.
    private func triggerSelectedTablet() {
        guard let id = selectedTabletID,
              let tablet = discoveredTablets.first(where: { $0.id == id }),
              let ip = ipAddresses.first else { return }
        statusText = "Inviting \(tablet.name)…"
        discovery.sendConnectCommand(to: tablet.endpoint, host: ip, port: Int(port))
    }

    func stop() {
        Task {
            await capture.stop()
            server.stop()
            vdisplay.destroyDisplay()
            await MainActor.run {
                isRunning = false
                clientConnected = false
                activeWidth = 0
                activeHeight = 0
                activeResolutionText = ""
                statusText = "Idle"
            }
        }
    }
}

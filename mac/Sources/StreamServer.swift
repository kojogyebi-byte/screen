//
//  StreamServer.swift
//  ScreenExtend
//
//  Single-client TCP server. The Mac listens; the tablet connects. Outbound
//  video frames are sent framed; inbound pointer events are parsed and handed
//  to a callback.
//

import Foundation
import Network

final class StreamServer {

    enum State { case stopped, listening, connected }

    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.shamaapps.screenextend.server")

    // Inbound parse buffer.
    private var rxBuffer = Data()

    // Callbacks (invoked on `queue`).
    var onStateChange: ((State) -> Void)?
    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?
    var onPointer: ((PointerAction, Double, Double, Double, Double) -> Void)?
    // Tablet capabilities: (nativeWidth, nativeHeight, densityDpi, deviceName)
    var onHello: ((Int, Int, Int, String) -> Void)?

    private(set) var state: State = .stopped {
        didSet { onStateChange?(state) }
    }

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Lower latency for interactive use.
            if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcp.noDelay = true
            }
            let l = try NWListener(using: params, on: port)
            l.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            l.stateUpdateHandler = { [weak self] st in
                switch st {
                case .ready:   self?.state = .listening
                case .failed(let e): NSLog("[ScreenExtend] Listener failed: \(e)")
                default: break
                }
            }
            listener = l
            l.start(queue: queue)
        } catch {
            NSLog("[ScreenExtend] Failed to start listener: \(error)")
        }
    }

    func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        rxBuffer.removeAll()
        state = .stopped
    }

    private func accept(_ conn: NWConnection) {
        // Replace any existing client with the newest connection.
        connection?.cancel()
        rxBuffer.removeAll()
        connection = conn
        conn.stateUpdateHandler = { [weak self] st in
            guard let self = self else { return }
            switch st {
            case .ready:
                self.state = .connected
                self.onClientConnected?()
                self.receive()
            case .failed, .cancelled:
                if self.connection === conn {
                    self.connection = nil
                    self.state = .listening
                    self.onClientDisconnected?()
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    // MARK: Sending

    func send(_ type: MsgType, _ payload: Data) {
        guard let conn = connection else { return }
        let data = WireFraming.frame(type, payload)
        conn.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                NSLog("[ScreenExtend] send error: \(error)")
            }
        })
    }

    var hasClient: Bool { connection != nil }

    // MARK: Receiving (pointer events)

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.rxBuffer.append(data)
                self.drainInbound()
            }
            if isComplete || error != nil { return }
            self.receive()
        }
    }

    private func drainInbound() {
        // Each inbound frame: [type:1][len:4][payload]
        while rxBuffer.count >= 5 {
            let type = rxBuffer[rxBuffer.startIndex]
            let lenStart = rxBuffer.index(rxBuffer.startIndex, offsetBy: 1)
            let len = rxBuffer.subdata(in: lenStart..<rxBuffer.index(lenStart, offsetBy: 4))
                .withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let total = 5 + Int(len)
            guard rxBuffer.count >= total else { return }

            let payloadStart = rxBuffer.index(rxBuffer.startIndex, offsetBy: 5)
            let payload = rxBuffer.subdata(in: payloadStart..<rxBuffer.index(payloadStart, offsetBy: Int(len)))
            rxBuffer.removeSubrange(rxBuffer.startIndex..<rxBuffer.index(rxBuffer.startIndex, offsetBy: total))

            if type == MsgType.pointer.rawValue {
                parsePointer(payload)
            } else if type == MsgType.hello.rawValue {
                parseHello(payload)
            }
        }
    }

    private func parsePointer(_ p: Data) {
        guard p.count >= 17 else { return }
        let bytes = [UInt8](p)
        guard let action = PointerAction(rawValue: bytes[0]) else { return }
        func f(_ offset: Int) -> Double {
            let bits = (UInt32(bytes[offset]) << 24) |
                       (UInt32(bytes[offset + 1]) << 16) |
                       (UInt32(bytes[offset + 2]) << 8) |
                        UInt32(bytes[offset + 3])
            return Double(Float(bitPattern: bits))
        }
        let nx = f(1), ny = f(5), dx = f(9), dy = f(13)
        onPointer?(action, nx, ny, dx, dy)
    }

    private func parseHello(_ p: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: p) as? [String: Any] else { return }
        let w = (obj["w"] as? Int) ?? 0
        let h = (obj["h"] as? Int) ?? 0
        let dpi = (obj["dpi"] as? Int) ?? 0
        let name = (obj["name"] as? String) ?? "Tablet"
        onHello?(w, h, dpi, name)
    }
}

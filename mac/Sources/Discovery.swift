//
//  Discovery.swift
//  Expanse (ScreenExtend target)
//
//  Finds Expanse tablets on the local network via Bonjour and can tell a
//  chosen tablet to connect back to this Mac's video server. The tablet
//  advertises "_expanse._tcp" and listens on a small control port; here we
//  browse for it and, on request, open a short-lived connection to hand it
//  this Mac's address + video port.
//

import Foundation
import Network

struct DiscoveredTablet: Identifiable, Hashable {
    let id: String              // Bonjour service name (unique on the network)
    let name: String
    let endpoint: NWEndpoint

    static func == (lhs: DiscoveredTablet, rhs: DiscoveredTablet) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

final class TabletDiscovery {

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.shamaapps.screenextend.discovery")

    /// Called (on an arbitrary queue) whenever the set of tablets changes.
    var onChange: (([DiscoveredTablet]) -> Void)?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_expanse._tcp", domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            var list: [DiscoveredTablet] = []
            for result in results {
                if case let .service(name, _, _, _) = result.endpoint {
                    list.append(DiscoveredTablet(id: name, name: name, endpoint: result.endpoint))
                }
            }
            self.onChange?(list.sorted { $0.name.lowercased() < $1.name.lowercased() })
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        onChange?([])
    }

    /// Opens a short-lived connection to the tablet and hands it the Mac's
    /// address + video port so the tablet connects back to the video server.
    func sendConnectCommand(to endpoint: NWEndpoint, host: String, port: Int) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let payload = "{\"host\":\"\(host)\",\"port\":\(port)}\n"
                connection.send(content: payload.data(using: .utf8),
                                completion: .contentProcessed { _ in connection.cancel() })
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
}

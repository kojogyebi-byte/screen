//
//  NetworkInfo.swift
//  ScreenExtend
//

import Foundation

enum NetworkInfo {
    /// Returns non-loopback IPv4 addresses, preferring Wi-Fi / Ethernet
    /// interfaces (en*). Used so the user can type the Mac's address into the
    /// tablet.
    static func localIPv4Addresses() -> [String] {
        var results: [(iface: String, ip: String)] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let addr = cur.pointee.ifa_addr
            if let addr = addr,
               (flags & IFF_UP) == IFF_UP,
               (flags & IFF_LOOPBACK) == 0,
               addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: cur.pointee.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let saLen = socklen_t(addr.pointee.sa_len)
                if getnameinfo(addr, saLen, &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if !ip.isEmpty { results.append((name, ip)) }
                }
            }
            ptr = cur.pointee.ifa_next
        }

        // Prefer en0/en1... (Wi-Fi & Ethernet) ahead of bridge/utun/etc.
        let ordered = results.sorted { a, b in
            let aw = a.iface.hasPrefix("en") ? 0 : 1
            let bw = b.iface.hasPrefix("en") ? 0 : 1
            if aw != bw { return aw < bw }
            return a.iface < b.iface
        }
        return ordered.map { $0.ip }
    }
}

//
//  Protocol.swift
//  ScreenExtend
//
//  Tiny length-prefixed binary protocol over a single TCP connection.
//
//  Frame layout (all multi-byte integers big-endian):
//      [1 byte messageType][4 byte payloadLength][payload...]
//
//  Mac -> Tablet:
//      0x01 INFO    payload = UTF-8 JSON: {"w":Int,"h":Int,"fps":Int}
//      0x02 CONFIG  payload = H.264 SPS/PPS as Annex-B (start-code prefixed)
//      0x03 FRAME   payload = [1 byte keyframeFlag][H.264 access unit, Annex-B]
//
//  Tablet -> Mac:
//      0x10 POINTER payload = [1 byte action]
//                            [4 byte float nx][4 byte float ny]
//                            [4 byte float dx][4 byte float dy]
//           floats are IEEE-754 big-endian. action == PointerAction raw value.
//

import Foundation

enum MsgType: UInt8 {
    case info    = 0x01
    case config  = 0x02
    case frame   = 0x03
    case pointer = 0x10
    case hello   = 0x11
}

enum WireFraming {
    static func frame(_ type: MsgType, _ payload: Data) -> Data {
        var out = Data(capacity: payload.count + 5)
        out.append(type.rawValue)
        var len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }
}

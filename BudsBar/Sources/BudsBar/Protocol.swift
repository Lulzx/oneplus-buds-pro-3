import Foundation

/// OPPO / HeyMelody control protocol used by OnePlus Buds Pro 3 (RFCOMM, UUID 0000079a-…).
/// `AA | len(LEB128) | 00 00 | cmd u16 LE | seq | paylen u16 LE | payload`, len = 7 + paylen.
nonisolated enum BudsProtocol {
    static let serviceUUID: [UInt8] = [0x00, 0x00, 0x07, 0x9a, 0xd1, 0x02, 0x11, 0xe1,
                                       0x9b, 0x23, 0x00, 0x02, 0x5b, 0x00, 0xa5, 0xa5]
    static let fallbackChannel: UInt8 = 15

    struct Frame: Sendable, Equatable {
        var cmd: UInt16
        var seq: UInt8
        var payload: [UInt8]
        var isReply: Bool { cmd & 0x8000 != 0 }
        /// First payload byte of a reply is a status code; 0 means OK.
        var status: UInt8? { isReply ? payload.first : nil }
    }

    static func encode(cmd: UInt16, seq: UInt8, payload: [UInt8] = []) -> [UInt8] {
        var body: [UInt8] = [0, 0, UInt8(cmd & 0xff), UInt8(cmd >> 8), seq,
                             UInt8(payload.count & 0xff), UInt8(payload.count >> 8)]
        body += payload
        var out: [UInt8] = [0xaa]
        var n = body.count
        repeat {
            var b = UInt8(n & 0x7f)
            n >>= 7
            if n > 0 { b |= 0x80 }
            out.append(b)
        } while n > 0
        return out + body
    }

    /// Pulls every complete frame out of `buffer`, leaving any partial tail in place.
    static func drain(_ buffer: inout [UInt8]) -> [Frame] {
        var frames: [Frame] = []
        var i = 0
        scan: while i < buffer.count {
            guard buffer[i] == 0xaa else { i += 1; continue }
            var j = i + 1, length = 0, shift = 0
            while true {
                guard j < buffer.count else { break scan }
                let b = buffer[j]; j += 1
                length |= Int(b & 0x7f) << shift; shift += 7
                if b & 0x80 == 0 { break }
                if shift > 21 { i += 1; continue scan }
            }
            guard length >= 7 else { i += 1; continue }
            guard j + length <= buffer.count else { break }
            let body = Array(buffer[j ..< j + length])
            let cmd = UInt16(body[2]) | UInt16(body[3]) << 8
            let plen = min(Int(body[5]) | Int(body[6]) << 8, length - 7)
            frames.append(Frame(cmd: cmd, seq: body[4], payload: Array(body[7 ..< 7 + plen])))
            i = j + length
        }
        buffer.removeFirst(min(i, buffer.count))
        return frames
    }
}

// MARK: - Domain values

nonisolated struct Battery: Equatable, Sendable {
    var level: Int
    var charging: Bool
    init(raw: UInt8) { level = Int(raw & 0x7f); charging = raw & 0x80 != 0 }
}

nonisolated enum WearState: Equatable, Sendable {
    case inCase, out, inEar
    init(raw: UInt8) {
        self = raw & 0x02 != 0 ? .inEar : (raw & 0x01 != 0 ? .out : .inCase)
    }
    var label: String {
        switch self { case .inCase: "In case"; case .out: "Out"; case .inEar: "In ear" }
    }
}

/// Raw values are what the buds report; `setMask` is what they accept.
nonisolated enum NoiseMode: UInt16, CaseIterable, Identifiable, Sendable {
    case off = 0x0008, transparency = 0x0100, smart = 0x0080
    case deep = 0x0010, moderate = 0x0020, light = 0x0040
    var id: UInt16 { rawValue }
    var setMask: UInt16 {
        switch self {
        case .off: 0x0001
        case .transparency: 0x0004
        default: rawValue
        }
    }
    var isANC: Bool { [.deep, .moderate, .light].contains(self) }
    var title: String {
        switch self {
        case .off: "Off"; case .transparency: "Transparency"; case .smart: "Adaptive"
        case .deep: "Deep"; case .moderate: "Moderate"; case .light: "Light"
        }
    }
}

nonisolated enum EQPreset: UInt8, CaseIterable, Identifiable, Sendable {
    case balanced = 0, bold = 1, serenade = 2, bass = 3, dynaudio = 7
    var id: UInt8 { rawValue }
    var title: String {
        switch self {
        case .balanced: "Balanced"; case .bold: "Bold"; case .serenade: "Serenade"
        case .bass: "Bass"; case .dynaudio: "Dynaudio"
        }
    }
}

nonisolated enum SpatialMode: UInt8, CaseIterable, Identifiable, Sendable {
    case off = 0, fixed = 1, headTracked = 2
    var id: UInt8 { rawValue }
    var title: String {
        switch self { case .off: "Off"; case .fixed: "Fixed"; case .headTracked: "Head Tracked" }
    }
}

nonisolated enum Feature: UInt8, Sendable {
    case wearDetection = 0x04, goldenSound = 0x0b, dualConnection = 0x11
    case hiRes = 0x18, bassWave = 0x1d, gameMode = 0x28
}

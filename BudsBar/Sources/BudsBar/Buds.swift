import Foundation
import IOBluetooth
import Observation
import os

private let log = Logger(subsystem: "local.BudsBar", category: "link")

/// Owns the RFCOMM control channel to the buds and mirrors their state.
@Observable
final class Buds: NSObject, IOBluetoothRFCOMMChannelDelegate {
    enum Link: Equatable { case searching, disconnected, connecting, connected }

    private(set) var link: Link = .searching
    /// True while the buds are connected to the Mac at the Bluetooth level; drives the menu bar icon.
    var budsPresent = false
    private(set) var deviceName = "OnePlus Buds Pro 3"
    private(set) var left: Battery?
    private(set) var right: Battery?
    private(set) var caseBattery: Battery?
    private(set) var leftWear: WearState?
    private(set) var rightWear: WearState?
    private(set) var noise: NoiseMode?
    private(set) var eq: EQPreset?
    private(set) var spatial: SpatialMode?
    private(set) var bassLevel: Int?
    private(set) var features: [UInt8: Bool] = [:]
    private(set) var firmware: String?
    private(set) var findingBuds = false
    private(set) var notice: String?

    var anyBudInEar: Bool { leftWear == .inEar || rightWear == .inEar }
    var budLevel: Int? { [left?.level, right?.level].compactMap(\.self).min() }

    private struct Pending { var cmd: UInt16; var payload: [UInt8] }

    @ObservationIgnored private var device: IOBluetoothDevice?
    @ObservationIgnored private var channel: IOBluetoothRFCOMMChannel?
    @ObservationIgnored private var connectStarted: Date?
    @ObservationIgnored private var rx: [UInt8] = []
    @ObservationIgnored private var seq: UInt8 = 0
    @ObservationIgnored private var queue: [Pending] = []
    @ObservationIgnored private var inFlight: (reply: UInt16, seq: UInt8, sent: Date)?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var connectNote: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNote: IOBluetoothUserNotification?

    override init() {
        super.init()
        loop = Task { [weak self] in
            // IOBluetooth refuses channel opens until its CoreBluetooth backend powers on.
            try? await Task.sleep(for: .seconds(2))
            self?.watchConnections()
            var tick = 0
            while !Task.isCancelled {
                self?.tick(tick)
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Public controls

    func refresh() {
        guard link == .connected else { connect(); return }
        for cmd: UInt16 in [0x0106, 0x0109] { send(cmd) }
        send(0x010c, [0x01, 0x01])
        send(0x010f); send(0x012a); send(0x0124)
        queryFeatures()
    }

    func setNoise(_ mode: NoiseMode) {
        guard anyBudInEar else { flash("Put at least one bud in your ear"); return }
        noise = mode
        send(0x0404, [0x01, 0x01, UInt8(mode.setMask & 0xff), UInt8(mode.setMask >> 8)])
        send(0x010c, [0x01, 0x01])
    }

    func setEQ(_ preset: EQPreset) { eq = preset; send(0x0406, [preset.rawValue]) }

    func setSpatial(_ mode: SpatialMode) { spatial = mode; send(0x0422, [mode.rawValue]) }

    func setBassLevel(_ level: Int) {
        let clamped = max(-5, min(5, level))
        bassLevel = clamped
        send(0x041b, [0xfb, 0x05, UInt8(bitPattern: Int8(clamped))])
    }

    func isOn(_ f: Feature) -> Bool { features[f.rawValue] ?? false }
    func has(_ f: Feature) -> Bool { features[f.rawValue] != nil }

    func set(_ f: Feature, _ on: Bool) {
        features[f.rawValue] = on
        send(0x0403, [f.rawValue, on ? 1 : 0])
        queryFeatures()
    }

    func toggleFindBuds() {
        findingBuds.toggle()
        send(0x0400, [findingBuds ? 1 : 0])
    }

    // MARK: - Connection

    private func tick(_ n: Int) {
        if let f = inFlight, Date().timeIntervalSince(f.sent) > 1.5 {
            log.debug("timeout waiting for \(String(f.reply, radix: 16), privacy: .public)")
            inFlight = nil
            pump()
        }
        switch link {
        case .connected:
            if n % 30 == 0 { send(0x0106); send(0x0109); send(0x010c, [0x01, 0x01]) }
        case .connecting:
            if let s = connectStarted, Date().timeIntervalSince(s) > 6 { teardown(); link = .disconnected }
        case .searching, .disconnected:
            if n % 4 == 0 { connect() }
        }
    }

    private func connect() {
        guard link != .connecting, link != .connected else { return }
        let paired = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).filter(Self.isOurBuds)
        guard let dev = paired.first(where: { $0.isConnected() }) ?? paired.first
        else { link = .searching; budsPresent = false; return }
        device = dev
        deviceName = dev.name ?? deviceName
        budsPresent = dev.isConnected()
        guard budsPresent else { link = .disconnected; return }
        watchDisconnect(of: dev)

        link = .connecting
        connectStarted = .now
        var ch: IOBluetoothRFCOMMChannel?
        let result = dev.openRFCOMMChannelAsync(&ch, withChannelID: controlChannel(of: dev), delegate: self)
        if result == kIOReturnSuccess, let ch {
            channel = ch
            if ch.isOpen() { didOpen() }
        } else {
            log.error("open failed \(result)")
            link = .disconnected
        }
    }

    private func controlChannel(of dev: IOBluetoothDevice) -> BluetoothRFCOMMChannelID {
        let uuid = BudsProtocol.serviceUUID.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        var id: BluetoothRFCOMMChannelID = 0
        if let rec = dev.getServiceRecord(for: uuid), rec.getRFCOMMChannelID(&id) == kIOReturnSuccess { return id }
        return BudsProtocol.fallbackChannel
    }

    private func didOpen() {
        guard link != .connected else { return }
        link = .connected
        log.notice("control channel open")
        send(0x0100)
        send(0x0105)
        refresh()
    }

    private func teardown() {
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        queue.removeAll(); inFlight = nil; rx.removeAll()
        findingBuds = false
    }

    // MARK: - Bluetooth connect / disconnect notifications

    nonisolated private static func isOurBuds(_ d: IOBluetoothDevice) -> Bool {
        d.name?.hasPrefix("OnePlus Buds Pro 3") == true
    }

    private func watchConnections() {
        guard connectNote == nil else { return }
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(deviceConnected(_:device:)))
        connect()
    }

    private func watchDisconnect(of dev: IOBluetoothDevice) {
        disconnectNote?.unregister()
        disconnectNote = dev.register(forDisconnectNotification: self,
                                      selector: #selector(deviceDisconnected(_:device:)))
    }

    // IOBluetooth may deliver these on a background queue, so hop to the main actor with plain values.
    @objc nonisolated private func deviceConnected(_ note: IOBluetoothUserNotification, device dev: IOBluetoothDevice) {
        guard Self.isOurBuds(dev) else { return }
        let name = dev.name
        Task { @MainActor [weak self] in
            guard let self else { return }
            log.notice("buds connected")
            budsPresent = true
            deviceName = name ?? deviceName
            // Give the audio profiles a moment to settle before opening the control channel.
            try? await Task.sleep(for: .seconds(1.5))
            connect()
        }
    }

    @objc nonisolated private func deviceDisconnected(_ note: IOBluetoothUserNotification, device dev: IOBluetoothDevice) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            log.notice("buds disconnected")
            disconnectNote?.unregister()
            disconnectNote = nil
            teardown()
            budsPresent = false
            link = .disconnected
        }
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate (delivered on the main run loop)

    nonisolated func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        MainActor.assumeIsolated {
            if status == kIOReturnSuccess { didOpen() } else { teardown(); link = .disconnected }
        }
    }

    nonisolated func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data: UnsafeMutableRawPointer!, length: Int) {
        let bytes = [UInt8](UnsafeRawBufferPointer(start: data, count: length))
        MainActor.assumeIsolated { receive(bytes) }
    }

    nonisolated func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
        MainActor.assumeIsolated {
            log.notice("control channel closed")
            teardown()
            link = .disconnected
        }
    }

    // MARK: - Send queue (one request in flight, matched by reply cmd + seq)

    private func send(_ cmd: UInt16, _ payload: [UInt8] = []) {
        queue.append(Pending(cmd: cmd, payload: payload))
        pump()
    }

    private func pump() {
        guard inFlight == nil, let channel, channel.isOpen(), !queue.isEmpty else { return }
        let next = queue.removeFirst()
        seq &+= 1
        write(BudsProtocol.encode(cmd: next.cmd, seq: seq, payload: next.payload))
        inFlight = (next.cmd | 0x8000, seq, .now)
    }

    private func write(_ bytes: [UInt8]) {
        guard let channel else { return }
        var b = bytes
        let r = channel.writeSync(&b, length: UInt16(b.count))
        if r != kIOReturnSuccess { log.error("write failed \(r)") }
    }

    private func queryFeatures() {
        let ids: [Feature] = [.wearDetection, .goldenSound, .dualConnection, .hiRes, .bassWave, .gameMode]
        send(0x010d, [UInt8(ids.count)] + ids.map(\.rawValue))
    }

    // MARK: - Receive

    private func receive(_ bytes: [UInt8]) {
        rx += bytes
        for frame in BudsProtocol.drain(&rx) {
            handle(frame)
            if let f = inFlight, frame.cmd == f.reply, frame.seq == f.seq {
                inFlight = nil
            }
        }
        pump()
    }

    private func handle(_ f: BudsProtocol.Frame) {
        let p = f.payload
        if f.isReply, let s = f.status, s != 0 {
            if s == 0x0e { flash("Put at least one bud in your ear"); send(0x010c, [0x01, 0x01]) }
            log.debug("cmd \(String(f.cmd, radix: 16), privacy: .public) status \(s)")
            return
        }
        switch f.cmd {
        case 0x8106 where p.count >= 2:
            for (part, raw) in pairs(p.dropFirst(2)) {
                switch part {
                case 1: left = Battery(raw: raw)
                case 2: right = Battery(raw: raw)
                case 3: caseBattery = Battery(raw: raw)
                default: break
                }
            }
        case 0x8109 where p.count >= 2:
            for (part, raw) in pairs(p.dropFirst(2)) {
                if part == 1 { leftWear = WearState(raw: raw) }
                if part == 2 { rightWear = WearState(raw: raw) }
            }
        case 0x810c where p.count >= 5 && p[1] == 0x01:
            noise = NoiseMode(rawValue: UInt16(p[3]) | UInt16(p[4]) << 8)
        case 0x810f where p.count >= 2: eq = EQPreset(rawValue: p[1])
        case 0x812a where p.count >= 2: spatial = SpatialMode(rawValue: p[1])
        case 0x8124 where p.count >= 4: bassLevel = Int(Int8(bitPattern: p[3]))
        case 0x810d where p.count >= 2:
            for (id, v) in pairs(p.dropFirst(2)) { features[id] = v != 0 }
        case 0x8105 where p.count > 2:
            firmware = Self.firmwareString(p.dropFirst(2))
        case 0x0504 where !p.isEmpty: eq = EQPreset(rawValue: p[0])
        case 0x0510 where !p.isEmpty: spatial = SpatialMode(rawValue: p[0])
        case 0x0500:
            // Buds ask for host time; answer with unix seconds so the link stays up.
            let t = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970))
            write(BudsProtocol.encode(cmd: 0x8500, seq: f.seq,
                                      payload: [0, UInt8(t & 0xff), UInt8(t >> 8 & 0xff), UInt8(t >> 16 & 0xff), UInt8(t >> 24)]))
        case 0x0204 where !p.isEmpty:
            switch p[0] {
            case 0x01: send(0x0106)
            case 0x02: send(0x0109)
            case 0x03: send(0x010c, [0x01, 0x01])
            case 0x05: queryFeatures()
            default: break
            }
        default: break
        }
    }

    private func pairs(_ s: ArraySlice<UInt8>) -> [(UInt8, UInt8)] {
        let a = Array(s)
        return stride(from: 0, to: a.count - 1, by: 2).map { (a[$0], a[$0 + 1]) }
    }

    /// "1,2,143,2,2,143,3,2,039" → "L 143 · R 143 · Case 039"
    private static func firmwareString(_ bytes: ArraySlice<UInt8>) -> String? {
        guard let s = String(bytes: bytes, encoding: .ascii) else { return nil }
        let f = s.split(separator: ",").map(String.init)
        let names = ["1": "L", "2": "R", "3": "Case"]
        let parts = stride(from: 0, to: f.count - 2, by: 3).compactMap { i in
            names[f[i]].map { "\($0) \(f[i + 2])" }
        }
        return parts.isEmpty ? s : parts.joined(separator: " · ")
    }

    private func flash(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self?.notice = nil }
        }
    }
}

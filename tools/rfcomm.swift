// usage: rfcomm <channel> <listenSeconds> [hex payload ...]
import Foundation
import IOBluetooth

let args = CommandLine.arguments
let chID = BluetoothRFCOMMChannelID(UInt8(args[1])!)
let listen = Double(args.count > 2 ? args[2] : "3")!
let payloads = args.dropFirst(3).map { h -> [UInt8] in
    let s = h.replacingOccurrences(of: " ", with: "")
    return stride(from: 0, to: s.count, by: 2).map { i in
        UInt8(s[s.index(s.startIndex, offsetBy: i)..<s.index(s.startIndex, offsetBy: i+2)], radix: 16)! }
}
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var open = false
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        let b = [UInt8](UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))
        let ts = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
        print("[\(ts)] RX \(n): \(hex(b))"); fflush(stdout)
    }
    func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        print("open status:", status, "mtu:", ch.getMTU()); open = (status == kIOReturnSuccess); fflush(stdout)
    }
    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) { print("closed"); fflush(stdout) }
}
let dev = IOBluetoothDevice(addressString: budsAddress())!
let d = D()
var ch: IOBluetoothRFCOMMChannel? = nil
RunLoop.current.run(until: Date().addingTimeInterval(2.0))
if !dev.isConnected() { print("openConnection:", dev.openConnection()) }
let r = dev.openRFCOMMChannelAsync(&ch, withChannelID: chID, delegate: d)
print("openRFCOMMChannelSync:", String(format:"0x%x", r))
let t0 = Date()
while !d.open && !(ch?.isOpen() ?? false) && Date().timeIntervalSince(t0) < 15 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
print("isOpen:", ch?.isOpen() ?? false, "after", Date().timeIntervalSince(t0)); if !(ch?.isOpen() ?? false) { exit(2) }
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
for p in payloads {
    var m = p
    print("TX \(m.count): \(hex(m))"); fflush(stdout)
    _ = ch!.writeSync(&m, length: UInt16(m.count))
    RunLoop.current.run(until: Date().addingTimeInterval(listen))
}
if payloads.isEmpty { RunLoop.current.run(until: Date().addingTimeInterval(listen)) }
ch!.close()
RunLoop.current.run(until: Date().addingTimeInterval(0.3))

/// Buds MAC from $BUDS_ADDR, e.g. BUDS_ADDR=aa-bb-cc-dd-ee-ff
func budsAddress() -> String {
    guard let a = ProcessInfo.processInfo.environment["BUDS_ADDR"] else { FileHandle.standardError.write("set BUDS_ADDR to your buds MAC (see system_profiler SPBluetoothDataType)\n".data(using: .utf8)!); exit(64) }
    return a
}

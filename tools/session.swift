// usage: session <channel>  ; stdin lines: "<hex>" sends, "sleep <s>" waits, "# ..." comment
import Foundation
import IOBluetooth
let chID = BluetoothRFCOMMChannelID(UInt8(CommandLine.arguments[1])!)
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var open = false
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        let b = [UInt8](UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))
        print("RX \(hex(b))"); fflush(stdout)
    }
    func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status: IOReturn) { open = (status == kIOReturnSuccess) }
    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) { print("CLOSED"); fflush(stdout) }
}
let lines = (readLine(strippingNewline: true).map { [$0] } ?? []) + Array(sequence(state: 0) { _ in readLine() })
RunLoop.current.run(until: Date().addingTimeInterval(2.0))
let dev = IOBluetoothDevice(addressString: budsAddress())!
let d = D(); var ch: IOBluetoothRFCOMMChannel? = nil
var t0 = Date()
for attempt in 1...4 {
  let r = dev.openRFCOMMChannelAsync(&ch, withChannelID: chID, delegate: d)
  t0 = Date()
  while !(ch?.isOpen() ?? false) && Date().timeIntervalSince(t0) < 4 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
  if ch?.isOpen() ?? false { break }
  FileHandle.standardError.write("attempt \(attempt) r=\(r) failed\n".data(using:.utf8)!)
  RunLoop.current.run(until: Date().addingTimeInterval(1.5))
}
while !(ch?.isOpen() ?? false) && Date().timeIntervalSince(t0) < 10 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
guard ch?.isOpen() ?? false else { print("OPEN FAILED"); exit(2) }
print("OPEN mtu \(ch!.getMTU())"); fflush(stdout)
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
for l in lines {
    let t = l.trimmingCharacters(in: .whitespaces)
    if t.isEmpty || t.hasPrefix("#") { continue }
    if t.hasPrefix("sleep") { RunLoop.current.run(until: Date().addingTimeInterval(Double(t.split(separator: " ")[1])!)); continue }
    let s = t.replacingOccurrences(of: " ", with: "")
    var b = stride(from: 0, to: s.count, by: 2).map { i in UInt8(s[s.index(s.startIndex, offsetBy: i)..<s.index(s.startIndex, offsetBy: i+2)], radix: 16)! }
    print("TX \(hex(b))"); fflush(stdout)
    _ = ch!.writeSync(&b, length: UInt16(b.count))
    RunLoop.current.run(until: Date().addingTimeInterval(0.35))
}
RunLoop.current.run(until: Date().addingTimeInterval(1.0))
ch!.close(); RunLoop.current.run(until: Date().addingTimeInterval(0.3))

/// Buds MAC from $BUDS_ADDR, e.g. BUDS_ADDR=aa-bb-cc-dd-ee-ff
func budsAddress() -> String {
    guard let a = ProcessInfo.processInfo.environment["BUDS_ADDR"] else { FileHandle.standardError.write("set BUDS_ADDR to your buds MAC (see system_profiler SPBluetoothDataType)\n".data(using: .utf8)!); exit(64) }
    return a
}

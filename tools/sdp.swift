import Foundation
import IOBluetooth

let addr = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : (ProcessInfo.processInfo.environment["BUDS_ADDR"] ?? "")
guard let dev = IOBluetoothDevice(addressString: addr) else { print("no device"); exit(1) }
print("Name:", dev.name ?? "?", "connected:", dev.isConnected())
print("ClassOfDevice: 0x" + String(dev.classOfDevice, radix: 16))
let r = dev.performSDPQuery(nil)
print("SDP query result:", r)
// wait for SDP
let deadline = Date().addingTimeInterval(8)
while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }

func dump(_ e: IOBluetoothSDPDataElement, _ ind: String) -> String {
    let t = e.getTypeDescriptor()
    switch t {
    case 1: return "uint " + (e.getNumberValue()?.stringValue ?? "?") + " (0x" + String(e.getNumberValue()?.uint64Value ?? 0, radix:16) + ")"
    case 2: return "int " + (e.getNumberValue()?.stringValue ?? "?")
    case 3: return "UUID " + (e.getUUIDValue()?.description ?? "?")
    case 4: return "str \"" + (e.getStringValue() ?? "") + "\""
    case 5: return "bool " + (e.getNumberValue()?.stringValue ?? "?")
    case 6, 7:
        var s = (t == 6 ? "seq[" : "alt[")
        for x in (e.getArrayValue() ?? []) { if let xe = x as? IOBluetoothSDPDataElement { s += "\n" + ind + "  " + dump(xe, ind + "  ") } }
        return s + "]"
    case 8: return "url " + (e.getStringValue() ?? "")
    default: return "type\(t)"
    }
}
for case let rec as IOBluetoothSDPServiceRecord in (dev.services ?? []) {
    print("\n=== Service:", rec.getServiceName() ?? "(unnamed)")
    var ch: BluetoothRFCOMMChannelID = 0
    if rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess { print("  RFCOMM channel:", ch) }
    var psm: BluetoothL2CAPPSM = 0
    if rec.getL2CAPPSM(&psm) == kIOReturnSuccess { print("  L2CAP PSM: 0x" + String(psm, radix:16)) }
    if let attrs = rec.attributes as? [NSNumber: IOBluetoothSDPDataElement] {
        for k in attrs.keys.sorted(by: { $0.intValue < $1.intValue }) {
            print(String(format: "  attr 0x%04x: ", k.intValue) + dump(attrs[k]!, "    "))
        }
    }
}

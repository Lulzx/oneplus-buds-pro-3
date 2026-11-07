import Foundation
import CoreBluetooth
func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
let svc079a = CBUUID(string: "0000079A-D102-11E1-9B23-00025B00A5A5")
class S: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var cm: CBCentralManager!; var seen = Set<UUID>(); var target: CBPeripheral?
    override init() { super.init(); cm = CBCentralManager(delegate: self, queue: nil) }
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { return }
        let conn = c.retrieveConnectedPeripherals(withServices: [svc079a, CBUUID(string: "FE2C"), CBUUID(string:"180F"), CBUUID(string:"180A")])
        for p in conn { print("CONNECTED-PERIPHERAL:", p.name ?? "?", p.identifier) }
        if let p = conn.first(where: { ($0.name ?? "").contains("OnePlus Buds Pro 3") }) ?? conn.first { target = p; p.delegate = self; c.connect(p) }
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData a: [String : Any], rssi: NSNumber) {
        let name = (a[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        let mfg = a[CBAdvertisementDataManufacturerDataKey] as? Data
        let sd = a[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
        let interesting = name.lowercased().contains("oneplus") || name.lowercased().contains("buds") || sd.keys.contains(CBUUID(string:"FE2C")) || (mfg.map { $0.count >= 2 && $0[0] == 0x9a && $0[1] == 0x07 } ?? false)
        guard interesting, !seen.contains(p.identifier) else { return }
        seen.insert(p.identifier)
        print("ADV \(p.identifier) rssi \(rssi) name='\(name)' mfg=\(mfg.map(hex) ?? "-") svcdata=\(sd.map { "\($0.key)=\(hex($0.value))" }) svcs=\(a[CBAdvertisementDataServiceUUIDsKey] ?? "-")")
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { print("GATT connected"); p.discoverServices(nil) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { print("connect fail", error as Any) }
    func peripheral(_ p: CBPeripheral, didDiscoverServices e: Error?) {
        for s in p.services ?? [] { print("SERVICE", s.uuid); p.discoverCharacteristics(nil, for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            print("  CHAR \(s.uuid) / \(ch.uuid) props=0x\(String(ch.properties.rawValue, radix:16))")
            if ch.properties.contains(.read) { p.readValue(for: ch) }
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        let v = ch.value ?? Data()
        print("  VALUE \(ch.uuid) = \(hex(v)) '\(String(data: v, encoding: .utf8)?.filter { $0.isASCII && !$0.isNewline } ?? "")' \(error.map { "err \($0)" } ?? "")")
    }
}
let s = S()
RunLoop.main.run(until: Date().addingTimeInterval(Double(CommandLine.arguments.dropFirst().first ?? "12")!))

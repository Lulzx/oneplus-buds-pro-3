import Foundation
import IOBluetooth
RunLoop.current.run(until: Date().addingTimeInterval(2))
let d = IOBluetoothDevice(addressString: budsAddress())!
print("close:", d.closeConnection())
RunLoop.current.run(until: Date().addingTimeInterval(5))
print("connected after close:", d.isConnected())
print("open:", d.openConnection())
RunLoop.current.run(until: Date().addingTimeInterval(6))
print("connected:", d.isConnected())

/// Buds MAC from $BUDS_ADDR, e.g. BUDS_ADDR=aa-bb-cc-dd-ee-ff
func budsAddress() -> String {
    guard let a = ProcessInfo.processInfo.environment["BUDS_ADDR"] else { FileHandle.standardError.write("set BUDS_ADDR to your buds MAC (see system_profiler SPBluetoothDataType)\n".data(using: .utf8)!); exit(64) }
    return a
}

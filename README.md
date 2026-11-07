# OnePlus Buds Pro 3 on macOS

These are reverse-engineering notes for the OnePlus Buds Pro 3's Bluetooth control protocol, plus a native macOS menu bar app that controls the buds without a phone.

- **[REPORT.md](REPORT.md)**: hardware and identity, the Bluetooth surface (SDP, RFCOMM, GATT), and the OPPO/HeyMelody `AA`-framed control protocol. Includes command tables verified on real hardware with firmware 143.
- **[BudsBar/](BudsBar/)**: a SwiftUI menu bar app (macOS 26+, Liquid Glass). It shows battery and in-ear state, and controls noise mode (Off / Transparency / Adaptive / ANC Light, Moderate, Deep), EQ presets, spatial audio, BassWave, game mode, in-ear detection, dual connection, and find my buds. It starts at login and its icon appears when the buds connect.
- **[tools/](tools/)**: small command-line probes: an SDP dump, a raw RFCOMM session, a frame builder and decoder (`op.py`), and a BLE/GATT scanner.

## Quick start

```sh
cd BudsBar && ./build.sh          # builds and installs /Applications/BudsBar.app
open /Applications/BudsBar.app
```

To run the CLI tools:

```sh
cd tools
for t in sdp rfcomm session reconnect ble; do
  swiftc -O $t.swift -o $t -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist
done
export BUDS_ADDR=aa-bb-cc-dd-ee-ff   # your buds' MAC, from: system_profiler SPBluetoothDataType
python3 op.py 0106 0105 010c:0101    # battery, firmware, noise mode
```

macOS lets only one client hold the control channel at a time, so quit BudsBar before using the tools.

## Credits

Earlier community work on the protocol helped: Gadgetbridge's OPPO headphones support, QuickBuds, OnePlusBuds4Mac, oneplus_buds3_pro_python, and oneplus-buds-macos.

Not affiliated with OnePlus or OPPO.

# BudsBar

A native SwiftUI menu bar app (macOS 26+, Liquid Glass) for OnePlus Buds Pro 3.

Build and run:

    ./build.sh && open build/BudsBar.app

Features: live battery (L/R/case, charging, in-ear state), noise control (Off / Transparency /
Adaptive / ANC Light-Moderate-Deep), EQ presets, spatial audio (off / fixed / head-tracked),
BassWave, game mode, in-ear detection, dual connection, find my buds.

It talks to the buds over RFCOMM (the OPPO `079a` service; see ../REPORT.md). macOS lets only one
client hold that channel, so quit BudsBar before using the CLI tools in ../tools.
Logs: `log stream --predicate 'subsystem == "local.BudsBar"' --info`

## Auto-start
`build.sh` installs to /Applications. On first launch BudsBar registers itself as a login item and
then runs in the background. Its menu bar icon appears only while the buds are connected, using
IOBluetooth connect/disconnect notifications. Turn this off with "Open when buds connect" in the panel,
or in System Settings > General > Login Items.

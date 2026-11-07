# OnePlus Buds Pro 3: reverse-engineering notes

Device under test: classic MAC `40:72:18:xx:xx:xx`, connected to a Mac (macOS 27.2). All protocol data below was captured live from this unit on 2026-11-07, unless marked *(spec page)* or *(community)*.

## 1. Hardware and identity

| Item | Value | Source |
|---|---|---|
| SoC vendor | **Bestechnic (BES)**. PnP record: vendor-ID source 1 (Bluetooth SIG), vendor `0x02B0` = Bestechnic (Shanghai). A BES "TOTA" service is also present. Exact chip (e.g. BES2700-series) not confirmed. | SDP |
| PnP product / version | `0x001F` / `0x0000` | SDP |
| OPPO product ID | `0x064014` (cmd `0x0103`) | live |
| Google Fast Pair model ID | `0x927BA1` (GATT `FE2C1233` and RFCOMM message stream) | live |
| Firmware | left **143**, right **143**, case **039** (cmd `0x0105` → `"1,2,143,2,2,143,3,2,039"`) | live |
| BLE address | `42:xx:xx:xx:xx:xx` (resolvable private) | Fast Pair stream |
| Class of device | `0x240404` (Audio/Video, wearable headset) | live |
| Drivers | 11 mm dual-magnet dynamic woofer (ceramic-metal diaphragm) + 6 mm planar tweeter, 2 DACs, Dynaudio tuning | spec page |
| Mics/sensors | 3 mics per bud (feed-forward, feed-back, talk) + VPU bone sensor; IMU (head tracking, Neck Health); in-ear detection (confirmed live, state 7) | spec + live |
| Radio | BT 5.4; codecs LHDC 5.0 (24-bit/192 kHz, 1 Mbps), AAC, SBC; no LDAC, no LC3 listed | spec page |
| ANC | up to 50 dB, adaptive | spec page |
| Battery | 58 mAh per bud, 566 mAh case; 10 h / 43 h ANC off, 6 h / 25 h ANC on; wired 70 min, Qi wireless 2.5 h | spec page |
| Build | IP55 buds, 5.28 g per bud, 50.57 g case | spec page |

### AI and software features (spec page)
- **AI Clear Call**: AI noise reduction for calls (3 mics + VPU), runs on the buds.
- **AI Translation**: in-person translation. It runs on the phone (OxygenOS 15.0.1+, select OnePlus phones only) and uses the buds as mic and speaker. No translation commands appear in the buds protocol.
- **Spatial audio**: rendered on the buds, so it works from any source, including this Mac (verified). Head tracking uses the buds' IMU.
- **Golden Sound**: personalized hearing/ear-canal EQ. Its filter bank is readable via `0x011F` (below).
- **Zen Mode Air** (white-noise scenes), **Neck Health** (IMU posture alerts), Find My Earbuds, dual connection, game mode (94 ms with OnePlus phones), Fast Pair, OTA.
- Neither spec page mentions Gemini or any on-device assistant.

## 2. Bluetooth surface (SDP + GATT)

Classic profiles: A2DP sink 1.3 · AVRCP CT/TG 1.6/1.4 · HFP 1.8 (features `0x3F`) · PnP/DID · GATT over BR/EDR. The SDP provider name is "MtView" (meaning unknown).

| RFCOMM ch | UUID | Name | Purpose |
|---|---|---|---|
| **15** | `0000079a-d102-11e1-9b23-00025b00a5a5` | ELNK | **OPPO/HeyMelody control protocol** (see section 3). `0x079A` is OPPO's SIG company ID. |
| 17 | `df21fe2c-2515-4fdb-8886-f12c4d67927c` | — | Google Fast Pair Message Stream. On connect it pushes model ID, BLE address and battery. |
| 12 | `00001101` (SPP) | TOTA | BES "Test Over The Air" debug/OTA tunnel. Silent; needs a vendor handshake. |
| 24 | `0000079b-d102-11e1-9b23-00025b00a5a5` | — | Silent; ignores `AA` frames. Purpose unknown. |

GATT services: Battery (`180F`, reads 0) · Fast Pair `FE2C` (`1233` model ID, `1234`–`1237` key-based pairing, passkey, account key, additional data) · OPPO `079A` (`0100079A` write, `0200079A` read/notify; read value = `01 9a07 144006 3f00 0198 00 <buds MAC reversed> 01 c9c7a702`) · OPPO `079C` (`0100079C`/`0200079C`, not readable; unknown).

## 3. Control protocol (RFCOMM ch 15, also reachable over GATT 079A)

```
AA | len (LEB128) | 00 00 | cmd u16 LE | seq u8 | paylen u16 LE | payload
len = 7 + paylen. No checksum. Reply cmd = request | 0x8000; payload[0] = status (00 OK, 0E = not worn, 02 = bad args).
High byte of cmd: 01 get · 02 notify/subscribe · 04 set · 05 push from buds · 81/84/85 replies.
```
On connect the buds send `0x0500` (time-sync request) and a `0x0204` push of the paired host list.

### Verified on this unit
| Cmd | Function | Example / decoded reply |
|---|---|---|
| `0100` | handshake / capability bitmap | `00 ff777aee668f0e04` |
| `0103` | product ID | `00 144006` → 0x064014 |
| `0105` | firmware | `1,2,143 / 2,2,143 / 3,2,039` (part, type, version) |
| `0106` | battery | `00 03 01 e4 02 e4 03 5a`; part 1=L, 2=R, 3=case; `&0x7F` = %, `0x80` = charging |
| `0109` | wear state | per part bitfield: bit0 out of case, bit1 in ear, bit2 lid open (7 = worn) |
| `0108 020301` | gesture table | 12 × (side, btn, action, fn); see table below |
| `010C 0101` / `0404 0101 <mask16>` | noise mode get/set | see ANC table |
| `010C 0201` | long-press cycle mask | `0x0006` = ANC ↔ Transparency |
| `010D <n> <ids>` / `0403 <id> <0/1>` | feature switches get/set | see feature table |
| `010F` / `0406 <id>` | EQ preset get/set, push `0504` | 00 Balanced, 01 Bold, 02 Serenade, 03 Bass, 07 Dynaudio *(01/07 verified)* |
| `0112` | connected hosts | MAC (LE) + state + name ("<host name>") |
| `0114` | active codec | `00 02` (on the Mac; very likely AAC) |
| `0124` | BassWave level | `00 fb05 00` (−5…+5, set via `041B fb05 <lvl>`) |
| `012A` / `0422 <0/1/2>` | spatial audio off / fixed / head-tracked, push `0510` | verified all three |
| `011F` | DSP filter bank (Golden Sound / custom EQ) | 44100 Hz header + 24 stages × 3 float32; currently all pass-through (1,0,0) |
| `0121` | sound profile record | named `"default"` |
| `0122` | custom EQ list | empty |

Also answered but not decoded: `0101` (`11f8`), `0102` (`079a`), `0104`, `0107`, `010A` (16 zero bytes), `010B`, `010E`, `0115`, `0116`, `0118`, `0119`, `011A`–`011E`, `0123` (`46 01`), `0125`–`0127`, `0129`, `012B`, `012D`, `012E`, `0131`.

### Noise modes (set `0404 01 01 <mask LE16>`)
| Set | Readback | Mode |
|---|---|---|
| `0001` | `0008` | Off |
| `0004` | `0100` | Transparency |
| `0010` | `0010` | ANC Deep |
| `0020` | `0020` | ANC Moderate |
| `0040` | `0040` | ANC Light |
| `0080` | `0080` | Smart (adaptive) ANC |
| `0800` | ignored | not supported on Pro 3 |

### Gesture table (both buds, current defaults)
| Action code | Gesture | Function code |
|---|---|---|
| 01 | single pinch | 01 play/pause |
| 02 | double | 06 next |
| 03 | triple | 05 previous |
| 04 | hold 1 s | 08 noise control |
| 06 | hold 3 s | 12 Zen Mode Air |
| 05 | slide | 07 volume |

Rewrite with `0401 <count> (side btn act fn)*` *(community; not tested here)*.

### Feature switch IDs present on this firmware (current value)
`02`=0 · `04`=1 wear detection · `05`=1 · `06`=1 · `0B`=0 Golden Sound/hearing profile · `0C`=1 · `0D`=1 · `11`=0 dual connection · `12`=0 · `13`=1 · `14`=0 · `15`=0 · `16`=0 · `18`=0 Hi-Res (LHDC) · `19`=0 · `1D`=1 BassWave · `22`=0 · `23`=0 · `24`=0 · `27`=0 · `28`=0 **game mode (verified)**. IDs without a name are unidentified.

### Other commands *(community, not exercised here)*
`0400 01/00` find earbuds (loud beep) · `0429`/`040B` multipoint connect/disconnect · `0418` custom EQ · `0502` find-phone request from the buds.

## 4. Tools (in `tools/`)
Set `BUDS_ADDR` to your buds' MAC first (`system_profiler SPBluetoothDataType`), e.g. `export BUDS_ADDR=aa-bb-cc-dd-ee-ff`.
- `sdp`: dumps SDP records.
- `session <ch>`: opens an RFCOMM channel and sends hex lines from stdin (`sleep N` to wait). Waits for IOBluetooth to power on first, which is required on macOS.
- `op.py CMD[:PAYLOADHEX] … [sleep:N]`: builds `AA` frames, runs them through `session 15`, and decodes replies. Example: `python3 op.py 0106 0105 010c:0101`.
- `ble`: BLE advertisement scan plus GATT enumeration and reads.

Rebuild Swift tools with: `swiftc -O X.swift -o X -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist && codesign -s - -f X`.

## 5. Open questions
- Undecoded replies (section 3) and unnamed feature IDs. Capturing HeyMelody traffic on Android (HCI snoop log) while toggling each setting would label them.
- Neck Health / IMU data and the head-tracking stream: no command found yet.
- TOTA (ch 12), the `079b` channel (24) and GATT `079C`: need a BES/OPPO handshake. This is the likely OTA/debug path; writing to it risks bricking.
- The meaning of "MtView" in the SDP provider name.

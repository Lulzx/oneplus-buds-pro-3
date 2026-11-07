#!/usr/bin/env python3
"""Build/parse OPPO/OnePlus 'AA' frames. op.py build CMD [payloadhex]  |  op.py run CMD:PAYLOAD ... (via ./session 15)"""
import sys, subprocess, itertools
seq = itertools.count(0x20)
def frame(cmd, payload=b"", s=None):
    s = next(seq) & 0xff if s is None else s
    body = b"\x00\x00" + cmd.to_bytes(2, "little") + bytes([s]) + len(payload).to_bytes(2, "little") + payload
    n = len(body); L = bytearray()
    while True:
        b = n & 0x7f; n >>= 7
        L.append(b | (0x80 if n else 0))
        if not n: break
    return b"\xaa" + bytes(L) + body
def parse(buf):
    out = []
    i = 0
    while i < len(buf):
        if buf[i] != 0xaa: i += 1; continue
        j = i + 1; n = 0; sh = 0
        while True:
            n |= (buf[j] & 0x7f) << sh; sh += 7; j += 1
            if not buf[j-1] & 0x80: break
        body = buf[j:j+n]
        if len(body) < 7: break
        cmd = int.from_bytes(body[2:4], "little"); s = body[4]; pl = int.from_bytes(body[5:7], "little")
        out.append((cmd, s, body[7:7+pl], body[:2]))
        i = j + n
    return out
def run(cmds, ch="15", pre=None):
    lines = []
    for c in cmds:
        if c.startswith("sleep"): lines.append("sleep " + c.split(":")[1]); continue
        k, _, p = c.partition(":")
        lines.append(frame(int(k, 16), bytes.fromhex(p)).hex())
    r = subprocess.run(["./session", ch], input="\n".join(lines) + "\n", capture_output=True, text=True, timeout=120)
    rx = bytearray()
    for l in r.stdout.splitlines():
        print(l)
        if l.startswith("RX "): rx += bytes.fromhex(l[3:])
    print("---- decoded ----")
    for cmd, s, p, hdr in parse(bytes(rx)):
        try: asc = p.decode() if all(32 <= c < 127 or c in (44,) for c in p[2:]) and len(p) > 4 else ""
        except: asc = ""
        print(f"cmd {cmd:04x} seq {s:02x} hdr {hdr.hex()} len {len(p):3d}: {p.hex()} {asc!r}" if asc else f"cmd {cmd:04x} seq {s:02x} hdr {hdr.hex()} len {len(p):3d}: {p.hex()}")
if __name__ == "__main__":
    run(sys.argv[1:])

"""Round-trip check for the UART build: send packets to each loopback node on each VC,
require every flit to echo byte-identical with tlast in the right place."""
import serial, time, sys
PORT, BAUD = 'COM3', 3_000_000
ser = serial.Serial(PORT, BAUD, timeout=0.5)
ser.reset_input_buffer()

def send(dest, vc, data):
    for i, b in enumerate(data):
        hdr = ((i == len(data)-1) << 7) | ((1 << vc) << 5) | (dest & 0xF)
        ser.write(bytes([hdr, b]))
    ser.flush()

def recv(n, deadline=3.0):
    got, t0 = [], time.time()
    while len(got) < n and time.time() - t0 < deadline:
        raw = ser.read(2)
        if len(raw) == 2:
            got.append((raw[0], raw[1]))
    return got

mode = sys.argv[1] if len(sys.argv) > 1 else 'all'
fails = 0
msg = ("For millions of years, mankind lived just like the animals. Then something "
       "happened which unleashed the power of our imagination. We learned to talk.").encode()
cases = [(0b0101, 1, msg), (0b0100, 0, bytes([0xAA,0xBB,0x00,0xFF,0x55])),
         (0b0101, 0, bytes(range(32))), (0b0100, 1, bytes(range(32))),
         (0b0001, 0, b"node idx2 VC0"), (0b0001, 1, b"node idx2 VC1")]
for dest, vc, data in (cases if mode in ('all','pos') else []):
    ser.reset_input_buffer()
    send(dest, vc, data)
    got = recv(len(data))
    payload = bytes(p for _, p in got)
    tid_ok  = all(((h >> 5) & 3) == (1 << vc) for h, _ in got)
    last_ok = [(h >> 7) & 1 for h, _ in got] == [0]*(len(data)-1) + [1] if got else False
    ok = payload == data and tid_ok and last_ok
    fails += (not ok)
    print(f"dest={dest:04b} vc={vc} len={len(data):3d} -> got {len(got):3d} "
          f"bytes_ok={payload==data} tid_ok={tid_ok} tlast_ok={last_ok} {'PASS' if ok else 'FAIL'}")
# negative: tid=00 must NOT come back (dropped + flagged in RTL)
if mode in ('all','neg'):
  ser.reset_input_buffer()
  for i, b in enumerate(b"bad"):
      ser.write(bytes([((i==2)<<7) | (0 << 5) | 0b0100, b]))
  ser.flush()
  got = recv(3, 1.5)
  print(f"tid=00 negative: got {len(got)} flits back (expect 0) {'PASS' if not got else 'FAIL'}")
  fails += bool(got)
ser.close()
print("UART ROUNDTRIP", "PASS" if fails == 0 else f"FAIL ({fails})")
sys.exit(fails)

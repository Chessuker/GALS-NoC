"""
Dual-VC functional test
-----------------------
ยิงทราฟฟิกสลับ VC0/VC1 ไปยัง 3 ปลายทางพร้อมกัน แล้วตรวจ:
  1. จำนวนแพ็กเก็ตครบทุกคู่ (node, vc)
  2. ลำดับ SEQ ถูกต้อง (in-order delivery ต่อ VC)
  3. ฟิลด์ VC ใน header ตรงกับ VC ที่ระบุใน payload (tid ไม่ถูกสลับระหว่างทาง)
  4. ไม่มีการปนกันข้าม VC (VC0 กับ VC1 reassemble แยก buffer)

หมายเหตุ: เทสต์นี้พิสูจน์ "ความถูกต้อง" ของเส้นทาง VC1 เท่านั้น
ยังพิสูจน์พฤติกรรม arbitration ไม่ได้ เพราะ PC ป้อนได้แค่ ~16% ของ
ความจุลิงก์ NoC จึงไม่เคยแออัดพอให้ arbiter ต้องตัดสินอะไรจริงจัง
"""
import re
import serial
import time
import threading

COM_PORT   = 'COM3'
BAUD_RATE  = 3_000_000
WINDOW     = 16384

# dest ตาม convention {x,y} ที่ router ใช้ (tdest[3:2]=x, tdest[1:0]=y)
NODES = {
    "NODE_01": 0b0100,   # -> echo_01
    "NODE_10": 0b0001,   # -> echo_10
    "NODE_11": 0b0101,   # -> echo_11
}

# tid เป็น one-hot 2 บิต: VC0 = 2'b01, VC1 = 2'b10
VCS = {"VC0": 0b01, "VC1": 0b10}

PACKETS = 2000          # ต่อคู่ (node, vc) -> 12,000 แพ็กเก็ต

# header ที่ยอมรับได้ = {tlast, tid[1:0], 0, tdest=0000}
#   VC0: 0x20 (tlast=0) / 0xA0 (tlast=1)
#   VC1: 0x40 (tlast=0) / 0xC0 (tlast=1)
HDR_MAP = {0x20: (0, 0), 0xA0: (0, 1), 0x40: (1, 0), 0xC0: (1, 1)}

PAT = re.compile(rb'^(NODE_\d\d)_VC(\d)_(\d{4})$')

keys      = [(n, v) for n in NODES for v in VCS]
counters  = {k: 0 for k in keys}
expected  = {k: 0 for k in keys}
order_err = []
stats     = {'corrupt': 0, 'vc_mismatch': 0, 'hdr_desync': 0, 'rx_bytes': 0}
bad_samples = []

lock = threading.Lock()
finished = False


def receiver(ser):
    state = 0
    vc = 0
    tlast = 0
    buf = {0: bytearray(), 1: bytearray()}   # reassemble แยกต่อ VC

    while not finished:
        try:
            n = ser.in_waiting
            if n:
                data = ser.read(n)
                with lock:
                    stats['rx_bytes'] += len(data)

                for b in data:
                    if state == 0:
                        if b in HDR_MAP:
                            vc, tlast = HDR_MAP[b]
                            state = 1
                        else:
                            with lock:
                                stats['hdr_desync'] += 1
                    else:
                        buf[vc].append(b)
                        if tlast:
                            check(bytes(buf[vc]), vc)
                            buf[vc].clear()
                        state = 0
            else:
                time.sleep(0.0005)
        except Exception as e:
            print(f"\n[CRITICAL] receiver พัง: {e}")
            break


def check(payload, hdr_vc):
    m = PAT.match(payload)
    with lock:
        if not m:
            stats['corrupt'] += 1
            if len(bad_samples) < 10:
                bad_samples.append((hdr_vc, payload))
            return

        node = m.group(1).decode()
        pay_vc = int(m.group(2))
        seq = int(m.group(3))
        key = (node, f"VC{pay_vc}")

        # VC ใน header ต้องตรงกับ VC ที่เขียนไว้ใน payload
        if pay_vc != hdr_vc:
            stats['vc_mismatch'] += 1

        if key not in expected:
            stats['corrupt'] += 1
            return

        if seq != expected[key]:
            order_err.append((key, expected[key], seq))
        expected[key] = seq + 1
        counters[key] += 1


def build_traffic():
    tx = bytearray()
    for seq in range(PACKETS):
        for node, dest in NODES.items():
            for vcname, tid in VCS.items():
                msg = f"{node}_{vcname}_{seq:04d}".encode('ascii')  # 16 bytes
                last_i = len(msg) - 1
                for i, ch in enumerate(msg):
                    hdr = ((1 if i == last_i else 0) << 7) | (tid << 5) | dest
                    tx.append(hdr)
                    tx.append(ch)
    return tx


if __name__ == '__main__':
    ser = None
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        print(f"[OK] เชื่อมต่อ {COM_PORT}")

        threading.Thread(target=receiver, args=(ser,), daemon=True).start()

        tx_buf = build_traffic()
        TOTAL = len(tx_buf)
        print(f"[..] เตรียมทราฟฟิก {TOTAL:,} ไบต์ "
              f"({PACKETS:,} แพ็กเก็ต x {len(NODES)} node x {len(VCS)} VC)\n")

        t0 = time.time()
        idx = 0
        next_mark = TOTAL // 10

        while idx < TOTAL:
            with lock:
                rx = stats['rx_bytes']
            in_flight = idx - rx

            if in_flight < WINDOW:
                chunk = min(WINDOW - in_flight, TOTAL - idx)
                chunk -= chunk % 2                  # ห้ามหั่นกลาง flit
                if chunk > 0:
                    ser.write(tx_buf[idx: idx + chunk])
                    idx += chunk
                    if idx >= next_mark:
                        next_mark += TOTAL // 10
                        with lock:
                            v0 = sum(counters[(n, "VC0")] for n in NODES)
                            v1 = sum(counters[(n, "VC1")] for n in NODES)
                        print(f"  ส่งแล้ว {idx:,}/{TOTAL:,} | rx VC0={v0:,} VC1={v1:,}")
                else:
                    time.sleep(0.001)
            else:
                time.sleep(0.001)

        drain = time.time()
        while time.time() - drain < 5.0:
            with lock:
                if stats['rx_bytes'] >= TOTAL:
                    break
            time.sleep(0.01)

        finished = True
        elapsed = time.time() - t0

        print("\n" + "=" * 56)
        print("สรุปผล Dual-VC Test")
        print("=" * 56)
        print(f"เวลา : {elapsed:.2f} s   throughput : "
              f"{TOTAL / elapsed / 1000:.1f} kB/s ต่อทิศทาง")
        print("-" * 56)

        ok = True
        for node in NODES:
            row = []
            for vcname in VCS:
                c = counters[(node, vcname)]
                row.append(f"{vcname}={c:,}")
                if c != PACKETS:
                    ok = False
            print(f"  {node} : " + "  ".join(row) +
                  ("   [OK]" if all(counters[(node, v)] == PACKETS for v in VCS)
                   else "   [MISSING]"))

        print("-" * 56)
        print(f"  order errors : {len(order_err)}")
        for e in order_err[:10]:
            print(f"      {e[0]} คาด SEQ {e[1]} ได้ {e[2]}")
        if len(order_err) > 10:
            print(f"      ... อีก {len(order_err) - 10} รายการ")

        print(f"  corrupt packets  : {stats['corrupt']}")
        for vc, p in bad_samples:
            print(f"      VC{vc}: {p!r}")
        print(f"  VC field mismatch: {stats['vc_mismatch']}")
        print(f"  header desync    : {stats['hdr_desync']}")
        print("-" * 56)

        if ok and not order_err and stats['corrupt'] == 0 \
           and stats['vc_mismatch'] == 0 and stats['hdr_desync'] == 0:
            print("[PASS] ทั้งสอง VC ส่งครบ เรียงถูก และ tid คงค่าตลอดเส้นทาง")
        else:
            print("[FAIL] ดูรายละเอียดด้านบน")
        print("=" * 56)

    except KeyboardInterrupt:
        finished = True
        print("\nยกเลิก")
    finally:
        finished = True
        time.sleep(0.1)
        if ser and ser.is_open:
            ser.close()

import re
import serial
import time
import threading

COM_PORT = 'COM3'
BAUD_RATE = 3000000
VC0_ID = 1

WINDOW_SIZE = 1024

NODES = {
    "NODE_01": 0b0100,
    "NODE_10": 0b0001,
    "NODE_11": 0b0101   # เดิมถูกอยู่แล้ว
}

PACKETS_PER_NODE = 5000 

rx_counters = {"NODE_01": 0, "NODE_10": 0, "NODE_11": 0}
rx_total_bytes = 0 
rx_lock = threading.Lock()
test_finished = False

PAT = re.compile(rb'^(NODE_\d\d)_SEQ_(\d{4})$')
expected = {n: 0 for n in NODES}
order_errors = []
corrupt = 0

# ==========================================
# 1. Receiver Thread (รับข้อมูลและคัดแยก)
# ==========================================
def noc_receiver(ser):
    global rx_counters, test_finished, rx_total_bytes
    sync_state = 0
    tlast = 0
    payload_buffer = bytearray()
    
    while not test_finished:
        try:
            if ser.in_waiting > 0:
                raw_data = ser.read(ser.in_waiting)
                
                with rx_lock:
                    rx_total_bytes += len(raw_data)
                    
                for byte in raw_data:
                    if sync_state == 0:
                        # 🔴 ล็อกเป้าแบบเจาะจง: Header ต้องเป็น 0x20 หรือ 0xA0 เท่านั้น!
                        # ป้องกันตัวอักษร '0' (0x30) ปลอมตัวมาเป็น Header
                        if byte == 0x20 or byte == 0xA0:
                            header = byte
                            tlast = (header >> 7) & 0x01
                            sync_state = 1
                        else:
                            pass
                    else:
                        payload_buffer.append(byte)
                        if tlast == 1:
                            try:
                                text = payload_buffer.decode('utf-8')
                                with rx_lock:
                                    m = PAT.match(text.encode('utf-8'))
                                    if m:
                                        node = m.group(1).decode()
                                        seq = int(m.group(2))
                                        if seq != expected[node]:
                                            order_errors.append((node, expected[node], seq))
                                        expected[node] = seq + 1
                                        rx_counters[node] += 1
                                    else:
                                        corrupt += 1
                            except UnicodeDecodeError:
                                pass 
                            payload_buffer.clear()
                        sync_state = 0
            else:
                time.sleep(0.001)
        except Exception as e:
            print(f"\n❌ [CRITICAL ERROR] Receiver Thread พัง!: {e}")
            break

# ==========================================
# 2. Main Test Flow
# ==========================================
if __name__ == '__main__':
    try:
        WINDOW_SIZE = int(input(f" Enter WINDOW_SIZE (default {WINDOW_SIZE}): ") or WINDOW_SIZE)
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        print(f"✅ เชื่อมต่อ {COM_PORT} สำเร็จ")
        
        rx_thread = threading.Thread(target=noc_receiver, args=(ser,), daemon=True)
        rx_thread.start()
        
        full_tx_buffer = bytearray()
        for seq in range(PACKETS_PER_NODE):
            for node_name, dest_id in NODES.items():
                message = f"{node_name}_SEQ_{seq:04d}".encode('utf-8')
                for i, byte in enumerate(message):
                    is_last = 1 if i == len(message) - 1 else 0
                    header = (is_last << 7) | (VC0_ID << 5) | dest_id
                    full_tx_buffer.extend([header, byte])
                    
        TOTAL_BYTES = len(full_tx_buffer)
        
        print("\n" + "🚦"*15)
        print("🚀 เริ่มทดสอบ Multi-Node Real-World Stress Test!")
        print("เครือข่ายกำลังส่งแพ็กเก็ตสลับไปหา Node 01, 10 และ 11 พร้อมๆ กัน...")
        print(f"📦 เตรียมข้อมูลเสร็จสิ้น ขนาดรวม {TOTAL_BYTES:,} ไบต์")
        print("🚦"*15 + "\n")
        
        start_time = time.time()
        tx_idx = 0
        
        # ลอจิก Sliding Window แบบคู่ (ห้ามหั่นครึ่ง)
        while tx_idx < TOTAL_BYTES:
            with rx_lock:
                current_rx = rx_total_bytes
                
            in_flight = tx_idx - current_rx
            
            if in_flight < WINDOW_SIZE:
                chunk_size = min(WINDOW_SIZE - in_flight, TOTAL_BYTES - tx_idx)
                chunk_size = chunk_size - (chunk_size % 2) 
                
                if chunk_size > 0:
                    ser.write(full_tx_buffer[tx_idx : tx_idx + chunk_size])
                    tx_idx += chunk_size
                    
                    if tx_idx % (TOTAL_BYTES // 10) < chunk_size:
                        with rx_lock:
                            print(f"📦 ทยอยส่งแล้ว {tx_idx:,} / {TOTAL_BYTES:,} ไบต์ | รับคืน: N01={rx_counters['NODE_01']}, N10={rx_counters['NODE_10']}, N11={rx_counters['NODE_11']}")
                else:
                    # with rx_lock:
                    #     print(f"⚠️ [WARNING] chunk_size={chunk_size} | tx_idx={tx_idx} | rx_total_bytes={rx_total_bytes} | in_flight={in_flight}")
                    time.sleep(0.0005)
            else:
                time.sleep(0.001)

        timeout_start = time.time()
        while time.time() - timeout_start < 5.0:
            with rx_lock:
                if rx_total_bytes >= TOTAL_BYTES:
                    break
            time.sleep(0.01)
            
        test_finished = True
        end_time = time.time()
        
        # ==========================================
        # 3. สรุปผลลัพธ์
        # ==========================================
        print("\n" + "="*45)
        print("📊 สรุปผลลัพธ์ Routing & Arbitration:")
        print("="*45)
        print(f"⏱️ เวลาที่ใช้ : {end_time - start_time:.2f} วินาที")
        
        total_rx = 0
        all_passed = True
        for node_name in NODES.keys():
            rx_count = rx_counters[node_name]
            total_rx += rx_count
            status = "✅ PASS" if rx_count == PACKETS_PER_NODE else "❌ DROP"
            if rx_count != PACKETS_PER_NODE: all_passed = False
            print(f"   {node_name} : ส่ง {PACKETS_PER_NODE:,} -> รับ {rx_count:,} {status}")
            
        print("-" * 45)
        print(f"🔢 Order errors : {len(order_errors)}")
        if order_errors:
            for e in order_errors[:10]:
                print(f"    {e[0]}: คาด SEQ {e[1]} แต่ได้ {e[2]}")
            if len(order_errors) > 10:
                print(f"    ... และอีก {len(order_errors)-10} รายการ")
        print(f"🧪 Corrupt/unparsable packets : {corrupt}")

        if all_passed and not order_errors and corrupt == 0:
            print("✨ [SUCCESS] ครบ 100% และเรียงลำดับถูกต้องทุกแพ็กเก็ต")
        else:
            print("⚠️ [FAIL] ดูรายละเอียดด้านบน")
        print("="*45)

    except KeyboardInterrupt:
        print("\n🛑 ยกเลิกการทดสอบ")
        test_finished = True
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
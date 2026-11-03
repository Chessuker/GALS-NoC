import serial
import time
import threading

COM_PORT = 'COM3'   
BAUD_RATE = 3000000 
WINDOW_SIZE = 32

# 🔴 แก้ไขหมายเลข VC ให้ตรงกับ One-Hot ในฮาร์ดแวร์
VC0_ID = 1  # ตรงกับ 2'b01
VC1_ID = 2  # ตรงกับ 2'b10

rx_vc0_buffer = bytearray()
rx_vc1_buffer = bytearray()
rx_lock = threading.Lock()

# ==========================================
# 1. State Machine ฝั่งรับ
# ==========================================
def preempt_receiver(ser):
    global rx_vc0_buffer, rx_vc1_buffer
    sync_state = 0
    header_byte = 0
    
    while True:
        try:
            if ser.in_waiting > 0:
                raw_data = ser.read(ser.in_waiting)
                with rx_lock:
                    for byte in raw_data:
                        if sync_state == 0:
                            header_byte = byte
                            sync_state = 1
                        else:
                            payload_byte = byte
                            tid = (header_byte >> 5) & 0x03
                            
                            # 🔴 อ่านข้อมูลกลับตาม ID ที่ถูกต้อง
                            if tid == VC0_ID:
                                rx_vc0_buffer.append(payload_byte)
                            elif tid == VC1_ID:
                                rx_vc1_buffer.append(payload_byte)
                                print(f"🚑 [VIP-VC1] แทรกคิวทะลุมาถึงแล้ว!: '{chr(payload_byte)}'")
                                
                            sync_state = 0 
        except Exception:
            break

# ==========================================
# 2. Main Test Flow
# ==========================================
if __name__ == '__main__':
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)
        print(f"✅ เชื่อมต่อ {COM_PORT} สำเร็จ")
        
        rx_thread = threading.Thread(target=preempt_receiver, args=(ser,), daemon=True)
        rx_thread.start()
        
        target_dest = 0b0101 # Node 11
        
        vc0_expected = bytearray([i % 256 for i in range(1000)])
        vc1_vip_msg = b"EMERGENCY_VIP_PACKET"

        with rx_lock:
            rx_vc0_buffer.clear()
            rx_vc1_buffer.clear()
            
        print("\n🚚 1. กำลังทยอยส่งรถบรรทุก (VC0) 1,000 ไบต์...")
        
        tx_vc0_idx = 0
        vc1_sent = False
        
        while tx_vc0_idx < len(vc0_expected):
            with rx_lock:
                current_vc0_rx = len(rx_vc0_buffer)
                
            # พอส่งไปได้ 500 ไบต์ หยุดยิง VC0 ชั่วคราว แล้วยิง VC1 แทรกเข้าไป!
            if tx_vc0_idx == 500 and not vc1_sent:
                print("\n🛑 หยุดรถบรรทุกชั่วคราว! กำลังแทรกข้อความฉุกเฉินลงในเลนด่วน (VC1)...")
                
                for i, data in enumerate(vc1_vip_msg):
                    is_last = 1 if i == len(vc1_vip_msg) - 1 else 0
                    header = (is_last << 7) | (VC1_ID << 5) | target_dest
                    ser.write(bytes([header, data]))
                    time.sleep(0.005) 
                    
                vc1_sent = True
                print("✅ ส่งข้อความฉุกเฉินเสร็จสิ้น! กลับมาส่งรถบรรทุกต่อ...\n")
                
            # Sliding Window สำหรับ VC0
            if (tx_vc0_idx - current_vc0_rx) < WINDOW_SIZE:
                data = vc0_expected[tx_vc0_idx]
                is_last = 1 if tx_vc0_idx == (len(vc0_expected) - 1) else 0
                header = (is_last << 7) | (VC0_ID << 5) | target_dest
                
                ser.write(bytes([header, data]))
                tx_vc0_idx += 1
            else:
                # ลดการปริ้นในลูปเพื่อไม่ให้คอมพิวเตอร์หน่วง
                time.sleep(0.001)

        # รอให้ข้อมูลเดินทางกลับมาครบ (เพิ่มเวลาเผื่อนิดนึง)
        time.sleep(1)

        # ==========================================
        # 3. สรุปผล
        # ==========================================
        with rx_lock:
            recv_vc0 = bytes(rx_vc0_buffer)
            recv_vc1 = bytes(rx_vc1_buffer)
            
        print("\n" + "="*45)
        print("📊 ผลการทดสอบ Virtual Channel Preemption:")
        print("="*45)
        
        if recv_vc1 == vc1_vip_msg:
            print(f"✨ [VC1 SUCCESS] แพ็กเก็ต VIP ทะลวงคิวสมบูรณ์: {recv_vc1.decode('utf-8')}")
        else:
            print(f"❌ [VC1 FAIL] ข้อมูล VIP ผิดพลาด! ได้รับ: {recv_vc1}")

        print(f"📦 [VC0] คาดหวัง: 1,000 ไบต์ | ได้รับจริง: {len(recv_vc0)} ไบต์")
        if recv_vc0 == vc0_expected:
            print("✨ [VC0 SUCCESS] ข้อมูล Background ถูกระงับและประกอบกลับได้สมบูรณ์ 100%!")
        else:
            print("❌ [VC0 FAIL] ข้อมูล Background เสียหายจากการถูกแทรกคิว")
        print("="*45)

    except KeyboardInterrupt:
        pass
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
import serial
import time
import threading

COM_PORT = 'COM3'   
BAUD_RATE = 3000000 
TOTAL_BYTES = 10000 
WINDOW_SIZE = 32     # จำนวนความจุสูงสุดของ FIFO ใน NoC

rx_buffer = bytearray()
rx_lock = threading.Lock()

# ==========================================
# 1. State Machine ฝั่งรับ (กันข้อมูลเหลื่อม)
# ==========================================
def bulk_receiver(ser):
    global rx_buffer
    sync_state = 0  # 0 = รอรับ Header, 1 = รอรับ Payload
    
    while True:
        try:
            if ser.in_waiting > 0:
                raw_data = ser.read(ser.in_waiting)
                with rx_lock:
                    for byte in raw_data:
                        if sync_state == 0:
                            # ไบต์นี้คือ Header (ไม่สนใจเนื้อหา ข้ามไป)
                            sync_state = 1
                        else:
                            # ไบต์นี้คือ Payload (เก็บเข้า Buffer)
                            rx_buffer.append(byte)
                            sync_state = 0  # กลับไปรอ Header ใหม่
        except Exception:
            break

# ==========================================
# 2. Main
# ==========================================
if __name__ == '__main__':
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)
        print(f"✅ เชื่อมต่อ {COM_PORT} สำเร็จที่ความเร็ว {BAUD_RATE:,} bps\n")
        
        rx_thread = threading.Thread(target=bulk_receiver, args=(ser,), daemon=True)
        rx_thread.start()
        
        test_data = bytearray([i % 256 for i in range(TOTAL_BYTES)])
        
        print(f"📦 กำลังส่งข้อมูล {TOTAL_BYTES:,} ไบต์ ด้วย True Sliding Window...")
        
        with rx_lock:
            rx_buffer.clear()
            
        start_time = time.time()
        
        target_dest = 0b0101
        vc_id = 1
        tx_idx = 0
        
        # ==========================================
        # 3. ระบบสายพานต่อเนื่อง (True Continuous Window)
        # ==========================================
        while tx_idx < TOTAL_BYTES:
            with rx_lock:
                current_rx = len(rx_buffer)
                
            # ถ้าระยะห่างระหว่างข้อมูลที่ส่งไป กับข้อมูลที่สะท้อนกลับมา ยังไม่เกิน 32
            # แปลว่าคิวใน FPGA ยังว่าง ให้ยิงข้อมูลอัดเข้าไปได้เลย
            if (tx_idx - current_rx) < WINDOW_SIZE:
                data = test_data[tx_idx]
                is_last = 1 if tx_idx == (TOTAL_BYTES - 1) else 0
                header = (is_last << 7) | (vc_id << 5) | (target_dest & 0x0F)
                
                ser.write(bytes([header, data]))
                tx_idx += 1
            else:
                # ถ้าคิวเต็ม รอให้ FPGA คายของเก่าออกมาแปปนึง
                time.sleep(0.001)

        # รอให้ข้อมูลชุดสุดท้ายสะท้อนกลับมาให้ครบ
        while True:
            with rx_lock:
                if len(rx_buffer) >= TOTAL_BYTES:
                    break
            time.sleep(0.001)

        end_time = time.time()
        elapsed = end_time - start_time
        
        with rx_lock:
            received_data = bytes(rx_buffer)
            
        # ==========================================
        # 4. ตรวจสอบผลลัพธ์
        # ==========================================
        print("\n" + "="*40)
        print("📊 ผลการทดสอบ Bulk Data Transfer:")
        print("="*40)
        print(f"⏱️ เวลาที่ใช้ทั้งหมด : {elapsed:.3f} วินาที")
        
        if elapsed > 0:
            throughput = (TOTAL_BYTES * 8) / elapsed / 1000 
            print(f"📈 Throughput      : {throughput:.2f} kbps")
            
        print(f"📤 ส่งออก  : {len(test_data):,} ไบต์")
        print(f"📥 ได้รับ   : {len(received_data):,} ไบต์")
        
        if received_data == test_data:
            print("\n✨ [SUCCESS] ข้อมูลถูกต้องตรงกัน 100% (NoC ของคุณโคตรแกร่ง!)")
        else:
            print("\n❌ [FAIL] ข้อมูลไม่ตรงกัน")
            for idx in range(min(len(test_data), len(received_data))):
                if test_data[idx] != received_data[idx]:
                    print(f"   พังที่ Index {idx}: ส่ง 0x{test_data[idx]:02X} รับ 0x{received_data[idx]:02X}")
                    break
        print("="*40)

    except KeyboardInterrupt:
        print("\n🛑 หยุดการทดสอบ")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
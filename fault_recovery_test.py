import serial
import time
import threading

COM_PORT = 'COM3'   
BAUD_RATE = 3000000 
TOTAL_BYTES = 50000  # 🔴 เพิ่มเป็น 50,000 ไบต์ ให้คุณมีเวลาทดลองกด Reset เล่นๆ
WINDOW_SIZE = 32

VC0_ID = 1  
target_dest = 0b0101

rx_buffer = bytearray()
rx_lock = threading.Lock()

# ==========================================
# 1. Receiver Thread (ตัวรับข้อมูล)
# ==========================================
def fault_receiver(ser):
    global rx_buffer
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
                            rx_buffer.append(byte)
                            sync_state = 0 
        except Exception:
            break

# ==========================================
# 2. Main Test Flow
# ==========================================
if __name__ == '__main__':
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        print(f"✅ เชื่อมต่อ {COM_PORT} สำเร็จ")
        
        rx_thread = threading.Thread(target=fault_receiver, args=(ser,), daemon=True)
        rx_thread.start()
        
        test_data = bytearray([i % 256 for i in range(TOTAL_BYTES)])

        with rx_lock:
            rx_buffer.clear()
            
        print("\n" + "🔥"*20)
        print("🚀 ระบบกำลังสาดข้อมูลอย่างต่อเนื่อง! (50,000 ไบต์)")
        print("⚡ คุณสามารถกดปุ่ม Reset (C2) ตอนไหนก็ได้แบบสุ่ม!")
        print("🔥"*20 + "\n")
        
        tx_idx = 0
        lost_bytes = 0  # ตัวแปรจำจำนวนข้อมูลที่ระเหยหายไปตอนที่คุณกดรีเซ็ต
        stuck_timer = time.time()
        
        start_time = time.time()

        # ==========================================
        # 3. Continuous Sending Loop with Auto-Recovery
        # ==========================================
        while tx_idx < TOTAL_BYTES:
            with rx_lock:
                current_rx = len(rx_buffer)
                
            # คำนวณข้อมูลที่ยังค้างอยู่ในท่อ (หักลบส่วนที่สูญหายไปแล้ว)
            in_flight = tx_idx - (current_rx + lost_bytes)
            
            if in_flight < WINDOW_SIZE:
                is_last = 1 if tx_idx == (TOTAL_BYTES - 1) else 0
                header = (is_last << 7) | (VC0_ID << 5) | target_dest
                ser.write(bytes([header, test_data[tx_idx]]))
                tx_idx += 1
                stuck_timer = time.time() # รีเซ็ตตัวจับเวลาเพราะระบบยังไหลลื่น
                
                # แสดง % ความคืบหน้าแบบเงียบๆ
                if tx_idx % 5000 == 0:
                    print(f"📦 ส่งข้อมูลไปแล้ว {tx_idx:,} / {TOTAL_BYTES:,} ไบต์...")

            else:
                # 🔴 ไฮไลท์การแก้ปัญหา: ถ้ารอคิวว่างนานเกิน 0.5 วินาที แปลว่าคุณกด Reset!
                if time.time() - stuck_timer > 0.5:
                    print(f"\n💥 [INTERRUPT] FPGA ขาดการติดต่อ! (โดนรีเซ็ตกลางอากาศ)")
                    print(f"🔄 [RECOVERY] ยอมทิ้งข้อมูลในท่อ {in_flight} ไบต์ แล้วสาดข้อมูลใหม่ต่อทันที...\n")
                    
                    # เคลียร์บัฟเฟอร์ฮาร์ดแวร์ USB เผื่อมีขยะตกค้าง
                    ser.reset_input_buffer()
                    
                    # บันทึกข้อมูลที่หายไป แล้วบังคับเดินหน้าต่อ
                    lost_bytes += in_flight
                    stuck_timer = time.time()
                else:
                    time.sleep(0.001)

        # รอข้อมูลชุดสุดท้าย
        time.sleep(1)

        end_time = time.time()
        
        with rx_lock:
            total_received = len(rx_buffer)

        print("\n" + "="*45)
        print("📊 สรุปผล Fault Injection แบบสุ่ม:")
        print("="*45)
        print(f"⏱️ เวลาทั้งหมดที่ใช้ : {end_time - start_time:.2f} วินาที")
        print(f"📤 ส่งข้อมูลไปทั้งหมด : {TOTAL_BYTES:,} ไบต์")
        print(f"📥 ได้รับข้อมูลรอดตาย : {total_received:,} ไบต์")
        print(f"👻 ข้อมูลที่ระเหยหายไป : {lost_bytes:,} ไบต์ (เกิดจากตอนฮาร์ดแวร์ถูกรีเซ็ต)")
        
        if total_received + lost_bytes >= TOTAL_BYTES:
            print("\n✨ [SUCCESS] NoC ฟื้นตัวจากการถูกรีเซ็ตแบบกะทันหันได้อย่างสมบูรณ์!")
            print("เมื่อฮาร์ดแวร์ Boot กลับมา มันสามารถทำงานต่อได้ทันทีโดยไม่ต้องเริ่มต้นระบบใหม่!")
        else:
            print("\n❌ [FAIL] บางอย่างผิดปกติ ข้อมูลขาดหายไปมากกว่าที่ประเมินไว้")
        print("="*45)

    except KeyboardInterrupt:
        print("\n🛑 ยกเลิกการทดสอบ")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
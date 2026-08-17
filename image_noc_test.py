import serial
import time
import threading
import os

COM_PORT = 'COM3'
BAUD_RATE = 3000000
WINDOW_SIZE = 32
VC0_ID = 1
target_dest = 0b0101

# ชื่อไฟล์ต้นฉบับ และชื่อไฟล์ที่จะเซฟหลังผ่าน FPGA
INPUT_IMAGE = 'hee.png'
OUTPUT_IMAGE = 'recovered_from_fpga.png'

rx_buffer = bytearray()
rx_lock = threading.Lock()

# ==========================================
# 1. Receiver Thread
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
    # เช็คว่ามีไฟล์รูปไหม
    if not os.path.exists(INPUT_IMAGE):
        print(f"❌ หาไฟล์รูป '{INPUT_IMAGE}' ไม่เจอ รบกวนเอามาวางไว้ที่เดียวกันก่อนนะครับ")
        exit()

    # โหลดรูปภาพแปลงเป็น Byte Array
    with open(INPUT_IMAGE, "rb") as f:
        image_data = bytearray(f.read())
    
    TOTAL_BYTES = len(image_data)

    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        print(f"✅ เชื่อมต่อ {COM_PORT} สำเร็จ")
        
        rx_thread = threading.Thread(target=fault_receiver, args=(ser,), daemon=True)
        rx_thread.start()

        with rx_lock:
            rx_buffer.clear()
            
        print("\n" + "🖼️"*20)
        print(f"🚀 เริ่มส่งรูปภาพขนาด {TOTAL_BYTES:,} ไบต์ ผ่าน GALS NoC")
        print("⚡ ลองแกล้งกด Reset (C2) ระหว่างโหลดรูปดูสิ! ระบบจะซ่อมแซมตัวเอง!")
        print("🖼️"*20 + "\n")
        
        tx_idx = 0
        stuck_timer = time.time()
        start_time = time.time()
        retransmit_count = 0

        # ==========================================
        # 3. Continuous Sending + ARQ (Auto-Retransmit)
        # ==========================================
        while tx_idx < TOTAL_BYTES:
            with rx_lock:
                current_rx = len(rx_buffer)
                
            in_flight = tx_idx - current_rx
            
            # ถ้ายังมีที่ว่างในท่อ ให้ส่งต่อ
            if in_flight < WINDOW_SIZE:
                is_last = 1 if tx_idx == (TOTAL_BYTES - 1) else 0
                header = (is_last << 7) | (VC0_ID << 5) | target_dest
                ser.write(bytes([header, image_data[tx_idx]]))
                tx_idx += 1
                stuck_timer = time.time()
                
                # อัปเดต % ความคืบหน้า
                if tx_idx % 10000 == 0:
                    print(f"📦 โหลดรูปไปแล้ว {tx_idx:,} / {TOTAL_BYTES:,} ไบต์...")

            else:
                # 🔴 ไฮไลท์การแก้ปัญหา: ถ้ารอเกิน 0.5 วิ แปลว่าของหาย
                if time.time() - stuck_timer > 0.5:
                    retransmit_count += 1
                    print(f"\n💥 [INTERRUPT] โดนรีเซ็ตกลางอากาศ! ข้อมูลหายไป {in_flight} ไบต์")
                    
                    # 🔴 ลอจิกการซ่อมแซมตัวเอง (Rewind)
                    print(f"🔄 [RECOVERY] กรอเทปกลับไปส่งใหม่ตั้งแต่ไบต์ที่ {current_rx:,}...")
                    
                    ser.reset_input_buffer()
                    tx_idx = current_rx  # ถอยตัวส่ง กลับไปเท่ากับตัวที่รับได้สำเร็จล่าสุด!
                    stuck_timer = time.time()
                else:
                    time.sleep(0.001)

        # รอรับข้อมูลไบต์สุดท้ายให้ครบ
        while True:
            with rx_lock:
                if len(rx_buffer) >= TOTAL_BYTES:
                    break
            time.sleep(0.01)

        end_time = time.time()
        
        with rx_lock:
            received_data = bytes(rx_buffer)

        # ==========================================
        # 4. บันทึกเป็นรูปใหม่ และตรวจสอบผลลัพธ์
        # ==========================================
        with open(OUTPUT_IMAGE, "wb") as f:
            f.write(received_data)

        print("\n" + "="*45)
        print("📊 สรุปผลการส่งรูปภาพ:")
        print("="*45)
        print(f"⏱️ เวลาที่ใช้ : {end_time - start_time:.2f} วินาที")
        print(f"🔄 จำนวนครั้งที่ซ่อมแซมข้อมูล (Retransmit) : {retransmit_count} ครั้ง")
        
        if received_data == image_data:
            print(f"\n✨ [SUCCESS] ยินดีด้วย! รูปภาพถูกส่งผ่าน FPGA สำเร็จ 100%")
            print(f"📁 บันทึกไฟล์ที่ได้รับไว้ที่: '{OUTPUT_IMAGE}' (ลองเปิดดูได้เลย!)")
        else:
            print("\n❌ [FAIL] รูปภาพเสียหายบางส่วน (อาจจะมี Noise เปิดดูไฟล์อาจจะภาพแตก)")
        print("="*45)

    except KeyboardInterrupt:
        print("\n🛑 ยกเลิก")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
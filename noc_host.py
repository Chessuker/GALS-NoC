import serial
import time
import threading

# ==========================================
# 1. การตั้งค่าพอร์ต UART
# ==========================================
COM_PORT = 'COM3'  # 🔴 เปลี่ยนให้ตรงกับ Device Manager ของคุณ
BAUD_RATE = 3000000

# ==========================================
# 2. ฟังก์ชันถอดรหัสข้อมูลจาก NoC (RX Thread)
# ==========================================
def noc_receiver(ser):
    print("🎯 [RX] เริ่มดักฟังข้อมูลจาก NoC...")
    while True:
        try:
            # รอจนกว่าจะมีข้อมูลเข้ามาครบ 2 ไบต์ (1 Flit)
            if ser.in_waiting >= 2:
                header = ser.read(1)[0]
                payload = ser.read(1)[0]
                
                # แกะบิตจาก Header (ตามโปรโตคอลที่เราออกแบบไว้)
                tlast = (header >> 7) & 0x01
                tid   = (header >> 5) & 0x03
                tdest = header & 0x0F
                
                # แปลง Payload เป็นตัวอักษรถ้าเป็นไปได้ (ASCII 32-126)
                char_disp = chr(payload) if 32 <= payload <= 126 else '.'
                
                print(f"[RX] Dest: {tdest:04b} | VC: {tid} | Last: {tlast} | Data: 0x{payload:02X} ('{char_disp}')")
        except Exception as e:
            print(f"RX Error: {e}")
            break

# ==========================================
# 3. ฟังก์ชันประกอบร่างแพ็กเก็ตส่งเข้า NoC (TX)
# ==========================================
def send_complex_payload(ser, target_dest, vc_id, data_bytes):
    print(f"\n🚀 [TX] กำลังส่งข้อมูล {len(data_bytes)} ไบต์ ไปยัง Dest: {target_dest:04b}, VC: {vc_id}")
    
    for i, data in enumerate(data_bytes):
        # บิต tlast จะเป็น 1 ก็ต่อเมื่อเป็นไบต์สุดท้ายของแพ็กเก็ต
        is_last = 1 if i == (len(data_bytes) - 1) else 0
        
        # ประกอบ Header: [7]tlast | [6:5]tid | [4]0 | [3:0]tdest
        header = (is_last << 7) | (vc_id << 5) | (target_dest & 0x0F)
        
        # ส่งข้อมูล 2 ไบต์ออกไปที่บอร์ด
        ser.write(bytes([header, data]))
        
        # หน่วงเวลาเล็กน้อยให้วงจรประมวลผลทัน
        time.sleep(0.005) 
        
    print("✅ [TX] ส่งแพ็กเก็ตเสร็จสมบูรณ์\n")

# ==========================================
# 4. โปรแกรมหลัก (Main)
# ==========================================
if __name__ == '__main__':
    try:
        # เปิดการเชื่อมต่อ
        ser = serial.Serial(COM_PORT, BAUD_RATE)
        print(f"✅ เชื่อมต่อ {COM_PORT} สำเร็จ ที่ความเร็ว {BAUD_RATE} bps\n")
        
        # รัน Thread สำหรับอ่านข้อมูลเบื้องหลังตลอดเวลา
        rx_thread = threading.Thread(target=noc_receiver, args=(ser,), daemon=True)
        rx_thread.start()
        
        # ปล่อยให้มันโชว์ข้อมูล RX ที่ไหลเข้ามาสัก 2 วินาที
        time.sleep(2)
        
        # --------------------------------------------------
        # ทดสอบส่ง Payload ซับซ้อน (Multi-flit Packet)
        # --------------------------------------------------
        # ตัวอย่างที่ 1: ส่งข้อความทักทาย
        message = "For millions of years, mankind lived just like the animals. Then something happened which unleashed the power of our imagination. We learned to talk."
        payload_1 = [ord(c) for c in message]
        send_complex_payload(ser, target_dest=0b0101, vc_id=1, data_bytes=payload_1)
        
        time.sleep(2)
        
        # ตัวอย่างที่ 2: ส่งชุดคำสั่งแบบ Hex Code (เช่น ตั้งค่า Register ปลายทาง)
        payload_2 = [0xAA, 0xBB, 0x00, 0xFF, 0x55]
        send_complex_payload(ser, target_dest=0b0100, vc_id=0, data_bytes=payload_2)
        
        # รันสคริปต์ค้างไว้เพื่อดูผลลัพธ์
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\n🛑 ปิดโปรแกรม")
    except Exception as e:
        print(f"❌ พบข้อผิดพลาด: {e}")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
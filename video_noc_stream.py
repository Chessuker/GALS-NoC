import serial
import time
import threading
import queue
import cv2
import numpy as np

COM_PORT = 'COM3'
BAUD_RATE = 3000000
WINDOW_SIZE = 4096

VC0_ID = 1  
VC1_ID = 2  
TARGET_DEST = 0b0101 

rx_vc0_buffer = bytearray()
rx_vc1_buffer = bytearray()
vc0_bytes_received = 0
rx_lock = threading.Lock()

display_queue = queue.Queue()
send_vip_flag = False
rx_sync_force = False 

# 🔴 ตัวแปรสำหรับแสดงผลข้อความ VIP บน GUI
vip_display_text = ""
vip_display_timer = 0.0

# ==========================================
# 1. Receiver Thread
# ==========================================
def noc_receiver(ser_ref):
    global rx_vc0_buffer, rx_vc1_buffer, vc0_bytes_received, rx_sync_force
    global vip_display_text, vip_display_timer
    
    sync_state = 0
    header_byte = 0
    
    while True:
        try:
            current_ser = ser_ref[0]
            if current_ser is not None and current_ser.is_open and current_ser.in_waiting > 0:
                raw_data = current_ser.read(current_ser.in_waiting)
                with rx_lock:
                    if rx_sync_force:
                        sync_state = 0
                        rx_sync_force = False
                        
                    for byte in raw_data:
                        if sync_state == 0:
                            header_byte = byte
                            sync_state = 1
                        else:
                            payload_byte = byte
                            tid = (header_byte >> 5) & 0x03
                            tlast = (header_byte >> 7) & 0x01
                            
                            if tid == VC0_ID:
                                rx_vc0_buffer.append(payload_byte)
                                vc0_bytes_received += 1
                                if tlast == 1:
                                    display_queue.put(bytes(rx_vc0_buffer))
                                    
                            elif tid == VC1_ID:
                                rx_vc1_buffer.append(payload_byte)
                                if tlast == 1:
                                    vip_text = bytes([b for b in rx_vc1_buffer if 32 <= b <= 126]).decode('utf-8', 'ignore').strip()
                                    if vip_text:
                                        print(f"\n🚑 [VIP RECEIVED] แทรกคิวสำเร็จ!: '{vip_text}'\n")
                                        # 🔴 ส่งข้อความให้ GUI แสดงผล พร้อมจับเวลา
                                        vip_display_text = f"*** {vip_text} ***"
                                        vip_display_timer = time.time()
                                        
                                    rx_vc1_buffer.clear()
                                    
                            sync_state = 0
            else:
                time.sleep(0.001)
        except Exception:
            time.sleep(0.1)

# ==========================================
# 2. Transmitter Thread
# ==========================================
def noc_transmitter(ser_ref, cap):
    global rx_vc0_buffer, vc0_bytes_received, send_vip_flag, rx_sync_force
    
    encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 40] 
    
    while True:
        ret, frame = cap.read()
        if not ret: continue
        
        frame = cv2.resize(frame, (320, 240))
        _, img_encoded = cv2.imencode('.jpg', frame, encode_param)
        test_data = img_encoded.tobytes()
        total_bytes = len(test_data)
        
        with rx_lock:
            rx_vc0_buffer.clear()
            vc0_bytes_received = 0
            
        tx_idx = 0
        current_rx = 0
        stuck_timer = time.time()
        
        retry_count = 0  
        last_rx = -1     
        
        while current_rx < total_bytes:
            try:
                if send_vip_flag:
                    send_vip_flag = False
                    vip_msg = b"URGENT_OVERRIDE_ACTIVATE" # เปลี่ยนข้อความให้ดูเท่ขึ้น
                    print(f"\n🚀 [VIP TX] กำลังยิงคำสั่ง '{vip_msg.decode()}' ทะลวงคิวเข้า VC1...")
                    vip_packet = bytearray()
                    for i, b in enumerate(vip_msg):
                        last = 1 if i == len(vip_msg)-1 else 0
                        hdr = (last << 7) | (VC1_ID << 5) | TARGET_DEST
                        vip_packet.extend([hdr, b])
                    ser_ref[0].write(vip_packet) 
                
                with rx_lock:
                    current_rx = vc0_bytes_received
                    
                in_flight = tx_idx - current_rx
                
                if tx_idx < total_bytes and in_flight < WINDOW_SIZE:
                    chunk_size = min(WINDOW_SIZE - in_flight, total_bytes - tx_idx)
                    tx_buffer = bytearray()
                    for _ in range(chunk_size):
                        is_last = 1 if tx_idx == (total_bytes - 1) else 0
                        header = (is_last << 7) | (VC0_ID << 5) | TARGET_DEST
                        tx_buffer.extend([header, test_data[tx_idx]])
                        tx_idx += 1
                    ser_ref[0].write(tx_buffer)
                    stuck_timer = time.time()
                    
                else:
                    if time.time() - stuck_timer > 0.5:
                        print(f"💥 [FAULT] วิดีโอสะดุด! ซ่อมแซมตัวเองที่ไบต์ {current_rx}...")
                        
                        if current_rx == last_rx:
                            retry_count += 1
                        else:
                            retry_count = 1
                            last_rx = current_rx
                            
                        if retry_count > 3:
                            print("⚠️ [FRAME DROP] ฮาร์ดแวร์ค้างหนัก! โยนเฟรมทิ้งดึงภาพใหม่...")
                            try:
                                ser_ref[0].reset_input_buffer()
                                ser_ref[0].reset_output_buffer()
                                flush_pkt = bytearray()
                                for _ in range(4):
                                    flush_pkt.extend([(1 << 7) | (VC0_ID << 5) | TARGET_DEST, 0x00])
                                ser_ref[0].write(flush_pkt)
                            except: pass
                            
                            with rx_lock:
                                rx_sync_force = True
                            break 
                        
                        try: 
                            ser_ref[0].reset_input_buffer()
                            ser_ref[0].reset_output_buffer() 
                        except: pass
                        
                        with rx_lock:
                            rx_sync_force = True 
                            
                        tx_idx = current_rx
                        stuck_timer = time.time()
                    else:
                        time.sleep(0.001)
                        
            except Exception as e:
                print(f"\n🔌 [USB ERROR] พอร์ตหลุดระดับ OS ({e})")
                print("⏳ ระบบกำลังพยายามกู้คืน...")
                
                while True:
                    try:
                        if ser_ref[0] is not None:
                            try: ser_ref[0].close()
                            except: pass
                        time.sleep(1.0) 
                        ser_ref[0] = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)
                        ser_ref[0].reset_input_buffer()
                        print("✅ [RECONNECT] ดึงพอร์ตกลับมาสำเร็จ! วิดีโอกำลังคืนชีพ...")
                        break
                    except Exception as reconnect_ex:
                        print(f"⏳ รออุปกรณ์พร้อม...")
                        time.sleep(1.0)
                
                with rx_lock:
                    rx_sync_force = True
                tx_idx = current_rx
                stuck_timer = time.time()

# ==========================================
# 3. Main GUI Thread
# ==========================================
if __name__ == '__main__':
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("❌ หากล้อง Webcam ไม่เจอครับ")
        exit()

    try:
        ser = [serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)]
        ser[0].reset_input_buffer()
        print(f"✅ เชื่อมต่อ {COM_PORT} สำเร็จ เริ่มสตรีมวิดีโอ!")
        
        threading.Thread(target=noc_receiver, args=(ser,), daemon=True).start()
        threading.Thread(target=noc_transmitter, args=(ser, cap), daemon=True).start()
        
        print("\n" + "="*45)
        print("🎥 สตรีมมิ่งกำลังทำงาน...")
        print("👉 กดปุ่ม 'v' ที่หน้าต่างวิดีโอ เพื่อยิงคำสั่งฉุกเฉิน (VIP) ขึ้นจอ")
        print("👉 กดปุ่ม Reset บนบอร์ด (C2) แช่ไว้เพื่อทดสอบระบบอมตะ")
        print("👉 กดปุ่ม 'q' เพื่อออก")
        print("="*45 + "\n")

        while True:
            try:
                frame_data = display_queue.get(timeout=0.01)
                
                nparr = np.frombuffer(frame_data, np.uint8)
                dec_frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                
                if dec_frame is not None:
                    # 🔴 ข้อความพื้นฐานของระบบ
                    cv2.putText(dec_frame, "GALS NoC Live Stream", (10, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
                    
                    # 🔴 ถ้ามีข้อความ VIP และเวลายังไม่เกิน 3 วินาที ให้แสดงผลสีแดง!
                    if time.time() - vip_display_timer < 3.0:
                        # สร้างเอฟเฟกต์กระพริบนิดๆ เพื่อความสมจริง (โชว์ 0.8 วิ หาย 0.2 วิ)
                        if int(time.time() * 5) % 5 != 0:
                            cv2.putText(dec_frame, vip_display_text, (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
                    
                    cv2.imshow("Hardware NoC Video", dec_frame)
                    
            except queue.Empty:
                pass
                
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('v'):
                send_vip_flag = True

    except KeyboardInterrupt:
        pass
    finally:
        cap.release()
        cv2.destroyAllWindows()
        if 'ser' in locals() and ser[0] is not None and ser[0].is_open:
            ser[0].close()
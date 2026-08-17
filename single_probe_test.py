"""
สคริปต์ทดสอบเดี่ยว: ส่ง 1 ข้อความไปที่ NODE_01 แล้วรอดู raw bytes ทุกตัวที่ตอบกลับมา
ไม่มี sync filter ใดๆ ทั้งสิ้น เพื่อดูว่า FPGA ส่งอะไรกลับมาจริงๆ
"""
import serial
import time

COM_PORT = 'COM3'
BAUD_RATE = 3000000
VC0_ID = 1
NODE_01_DEST = 0b0100

ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.5)
ser.reset_input_buffer()
ser.reset_output_buffer()
print(f"เชื่อมต่อ {COM_PORT} สำเร็จ")

time.sleep(0.5)  # รอให้เสถียรก่อนเริ่ม

message = b"NODE_01_SEQ_0000"
tx_buffer = bytearray()
for i, byte in enumerate(message):
    is_last = 1 if i == len(message) - 1 else 0
    header = (is_last << 7) | (VC0_ID << 5) | NODE_01_DEST
    tx_buffer.extend([header, byte])

print(f"กำลังส่ง {len(tx_buffer)} ไบต์: {tx_buffer.hex()}")
ser.write(bytes(tx_buffer))

# รอ 1 วินาที แล้วอ่านทุกอย่างที่กลับมา ไม่กรองอะไรเลย
time.sleep(1.0)
n = ser.in_waiting
raw = ser.read(n) if n > 0 else b''

print(f"\nได้รับกลับมาทั้งหมด {len(raw)} ไบต์:")
print(f"HEX: {raw.hex()}")
print(f"เป็นคู่ (header, data): {[(raw[i], raw[i+1]) for i in range(0, len(raw)-1, 2)]}")

try:
    # ลองถอดเฉพาะไบต์คู่ (data bytes เท่านั้น ตำแหน่งคี่ ถ้า pattern ตรงตามคาด)
    data_only = bytes(raw[i] for i in range(1, len(raw), 2))
    print(f"ลองถอดเฉพาะ data bytes (index คี่): {data_only}")
except Exception as e:
    print(f"ถอดไม่ได้: {e}")

ser.close()

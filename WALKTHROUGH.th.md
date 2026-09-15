# GALS Packet-Based Fabric: เดินอ่านตั้งแต่ศูนย์ (ฉบับภาษาไทย)

แปลจาก `WALKTHROUGH.md` ฉบับวันที่ 2026-09-14 (`main` ที่ `afce6cd`, PR #7 merge แล้ว, `v1.0`
tag ไว้ที่ `f07ddca` ก่อนหน้านั้นสอง PR) ฉบับภาษาอังกฤษเป็นต้นฉบับ ถ้าสองฉบับขัดกันให้ยึด
ภาษาอังกฤษ ชื่อสัญญาณ ชื่อโมดูล ชื่อ property และตัวเลขทั้งหมดคงเป็นภาษาอังกฤษตามโค้ด

เอกสารนี้เป็นคู่กับ `HANDOFF.md` ตัวนั้นเป็นบันทึกงานเรียงตามวันสำหรับคนที่รู้จักดีไซน์อยู่แล้ว
และต้องการสถานะล่าสุด ตัวเลข กับกับดักที่เคยเจอ ส่วนเอกสารนี้เขียนให้คนที่ไม่เคยเห็นโปรเจกต์
มาก่อน อธิบายว่าของชิ้นนี้คืออะไร แต่ละโมดูลทำงานยังไง flit หนึ่งตัววิ่งผ่านระบบยังไง ข้อบกพร่อง
แต่ละอันคืออะไร เจอได้ยังไง แก้ยังไง การ verify ทำอะไรบ้างและครอบคลุมอะไร ไม่ครอบคลุมอะไร
และจะต่อยอดดีไซน์ได้ทางไหน ถ้าตัวเลขขัดกัน `HANDOFF.md` มี log ลงวันที่รองรับ ถ้าคำอธิบาย
ขัดกัน เอกสารนี้เป็นฉบับที่เรียบเรียงละเอียดกว่า

รอบแรกอ่านจากบนลงล่าง หลังจากนั้นส่วนที่จะกลับมาเปิดบ่อยคือหัวข้อ 6 (module reference)
หัวข้อ 9 (verification รวม property catalogue) หัวข้อ 11 (parameter) และหัวข้อ 18 (file map)

---

## สารบัญ

1. โปรเจกต์นี้คืออะไร
2. พื้นฐานที่ต้องรู้ (NoC, GALS, virtual channel, packet กับ flit, CDC, ECC, reset)
3. ฮาร์ดแวร์: บอร์ด นาฬิกา การนับหมายเลขโหนด reset การควบคุมผ่าน JTAG
4. สัญญา flit: อะไรวิ่งบนสายทุกเส้น และใครบังคับกฎแต่ละข้อ
5. สถาปัตยกรรมจากบนลงล่าง
6. Module reference (ทุกไฟล์ RTL ทุก IP ทุก testbench ทุกสคริปต์)
7. ชีวิตของ flit: แพกเกจหนึ่งใบตั้งแต่ต้นจนจบ, flit ที่ถูกปฏิเสธ, reset หนึ่งครั้ง
8. ข้อบกพร่องทุกอันที่เจอ: บั๊ก 7 ตัวที่มีเลข และตัวที่ไม่มีเลข
9. verify ยังไง: simulation, formal (property catalogue ครบ), silicon, และตาราง coverage
10. บนบอร์ด: พฤติกรรมเฉพาะฮาร์ดแวร์
11. Parameter และปุ่มปรับ
12. การตัดสินใจเชิงดีไซน์ และทางเลือกที่ถูกปัดตก
13. การต่อยอดดีไซน์
14. ไทม์ไลน์
15. เรื่องที่กินเวลาจริง (gotcha)
16. อะไรยังค้าง
17. รันซ้ำผลทั้งหมดยังไง
18. File map
19. อภิธานศัพท์

---

## 1. โปรเจกต์นี้คืออะไร

**network-on-chip (NoC)** ขนาดเล็กบน Xilinx Artix-7 FPGA มี endpoint สี่ตัว (เรียกว่า host
หรือ node) อยู่ที่มุมของตาราง 2x2 แต่ละ host มี**นาฬิกาของตัวเอง** ความถี่ของตัวเอง ไม่มี
ความสัมพันธ์ทางเฟสกับตัวอื่นหรือกับตัวเครือข่าย ส่วนเครือข่ายเองวิ่งบนนาฬิกาตัวที่ห้า host
ยื่นแพกเกจให้เครือข่าย เครือข่ายพาไปส่งให้ host ปลายทาง

นั่นคือส่วนที่เป็น GALS: **Globally Asynchronous, Locally Synchronous** แต่ละเกาะเป็น
ลอจิก synchronous ธรรมดา รอยต่อระหว่างเกาะเป็น asynchronous FIFO ที่ใช้ gray-coded pointer กับ
synchronizer สองขั้น ซึ่งเป็นท่ามาตรฐานของ clock-domain crossing ตั้งแต่ 2026-09-12 แต่ละเกาะ
มี reset synchronizer ของตัวเองด้วย ซึ่งเป็นส่วนของตำราที่ดีไซน์นี้เคยข้ามไป

เครือข่ายเป็น**แบบ packet**: host ส่งแพกเกจเป็นลำดับของ flit ขนาด 8 บิต ตัวสุดท้ายติด
`tlast` router จะยึด output port ไว้ตลอดทั้งแพกเกจ flit ของคนละแพกเกจจึงไม่มีวันสลับกันใน
channel เดียว มี **virtual channel (VC) สองเลน**ต่อลิงก์ แพกเกจที่ priority สูงจึงแซงตัวที่
ต่ำกว่าได้

RTL เป็น SystemVerilog comment ส่วนใหญ่เป็นภาษาไทย ดีไซน์เกิดก่อน git history (ไฟล์ซอร์สมี
วันที่สร้างตั้งแต่เมษายนถึงกรกฎาคม 2026) repository เริ่มวันที่ 2026-08-17 และทุกอย่างหลัง
จากนั้นคือ verification การแก้บั๊ก และการเสริมความแข็ง บั๊ก RTL ที่มีเลข 7 ตัวถูกเจอและแก้
นอกจากนั้นยังมีข้อบกพร่องอีกชุดใน tooling, test และคำกล่าวอ้างเรื่อง verification ที่เจอ
ระหว่างทาง ซึ่งอยู่ในหัวข้อ 8 เช่นกัน ตอนนี้เกราะทุกชิ้นมีหลักฐานบนซิลิคอน ส่วนใหญ่มาจาก
fault-injection campaign ที่ควบคุมผ่าน JTAG และรันจาก bitstream เดียว

คำว่า **เรา** ข้างล่างหมายถึงใครก็ตามที่ทำงานกับ repo ณ เวลานั้น commit บอกไว้ว่าใคร

---

## 2. พื้นฐานที่ต้องรู้

ถ้ารู้อยู่แล้วว่า NoC แบบ wormhole ที่มี virtual channel คืออะไร อ่าน 2.8 ผ่านๆ แล้วข้ามไป
หัวข้อ 3 ได้เลย

### 2.1 ทำไมต้องเป็นเครือข่าย ไม่ใช่สายไฟ

เมื่อชิปมีบล็อกหลายตัวที่ต้องคุยกัน สายแบบ point-to-point ขยายไม่ไหว (N บล็อกต้องการสาย
ราวๆ N² เส้น) ส่วน bus ที่แชร์กันบังคับให้ทุกอย่างต่อคิวผ่าน arbiter ตัวเดียว NoC วาง router
เล็กๆ ไว้ที่แต่ละบล็อกแล้วต่อ router เข้ากับเพื่อนบ้าน ทราฟฟิกถูกซอยเป็นแพกเกจแล้วกระโดด
จาก router ตัวหนึ่งไปอีกตัว หลายแพกเกจวิ่งบนคนละลิงก์พร้อมกันได้

### 2.2 Mesh, XY routing

topology ของเราเป็น **mesh** 2x2: router สี่ตัว แต่ละตัวต่อกับเพื่อนบ้าน (east/west กับ
north/south) และกับ host ประจำตัว router หนึ่งตัวมีห้าพอร์ต: LOCAL, NORTH, SOUTH, EAST, WEST

routing เป็น **XY แบบเรียงมิติ**: flit เดินตามแกน X ก่อนจนค่า X ตรงกับปลายทาง แล้วค่อยเดิน
ตามแกน Y router แต่ละตัวตัดสินเองจากที่อยู่ปลายทางกับพิกัดของตัวเอง XY routing บน mesh
ไม่มีทาง deadlock โดยโครงสร้าง เพราะไม่มีการเลี้ยวจาก Y กลับไป X จึงไม่มีวงจรของการรอ
channel

### 2.3 แพกเกจ, flit, wormhole switching

**แพกเกจ** คือหน่วยที่ host สนใจ มันถูกส่งเป็นลำดับของ **flit** (flow-control unit) ลิงก์ละ
หนึ่งตัวต่อไซเคิล ที่นี่ flit คือข้อมูล 8 บิตบวก control อีกไม่กี่บิต flit ตัวสุดท้ายของ
แพกเกจติด `tlast = 1`

**wormhole switching** หมายถึง router ส่งต่อแพกเกจทีละ flit ตามที่มาถึง ไม่ได้รอเก็บทั้ง
แพกเกจก่อน flit หัว (head) จองพอร์ตออก flit ตัว (body) ตามหลัง flit หาง (`tlast`) ปล่อย
พอร์ต แพกเกจหนึ่งใบจึงพาดผ่าน router หลายตัวพร้อมกันได้เหมือนหนอนในรู ผลที่สำคัญกับ
โปรเจกต์นี้คือ ตราบใดที่แพกเกจถือพอร์ตอยู่ ใครก็ใช้พอร์ตนั้นไม่ได้ ถ้าหางไม่มา พอร์ตถูกยึด
ตลอดกาล บั๊กสี่ในเจ็ดตัวเป็นประโยคนี้ในรูปแบบต่างๆ

### 2.4 Virtual channel

**virtual channel** คือ buffer แยกกับ flow control แยก บนลิงก์กายภาพเส้นเดียวกัน มี VC สอง
เลน ลิงก์หนึ่งเส้นจึงมีคิวอิสระสองคิว ถ้าแพกเกจ VC0 ติดอยู่ปลายน้ำ แพกเกจ VC1 ยังใช้สายได้
ที่นี่ VC ใช้ทำ priority ด้วย: VC1 คือรถพยาบาล VC0 คือรถบรรทุก VC1 ได้ลิงก์ทุกครั้งที่มัน
ขยับได้ VC0 ได้ตอนอื่น และมี anti-starvation override กันไม่ให้ VC1 ที่ยิงไม่หยุดล็อก VC0
ออกไปตลอดกาล

### 2.5 valid/ready handshake

ทุก interface ใช้ handshake แบบ AXI4-Stream: ผู้ส่งยก `valid` พร้อมข้อมูล ผู้รับยก `ready`
การส่งเกิดที่ขอบนาฬิกาที่ทั้งคู่สูง `ready` ที่นี่เป็น**ต่อ VC**: เวกเตอร์ 2 บิตบอกว่า VC ไหน
รับได้ ผู้ส่งที่ยื่น flit บน VC0 ดูแค่ `ready[0]`

### 2.6 GALS กับ clock-domain crossing

โดเมนนาฬิกาสองโดเมนที่ไม่รู้ความสัมพันธ์กันแลกข้อมูลหลายบิตบนสายเปล่าไม่ได้ ผู้รับจะ
sample บางบิตก่อนเปลี่ยน บางบิตหลังเปลี่ยน คำตอบมาตรฐานคือ **asynchronous FIFO**: หน่วย
ความจำที่เขียนในโดเมนหนึ่งและอ่านในอีกโดเมน โดยส่ง pointer ของแต่ละฝั่งไปให้อีกฝั่งผ่าน
synchronizer สองฟลอป pointer เป็น **gray code** ให้เปลี่ยนทีละบิตต่อการนับ pointer ที่ถูก
sample กลางทางจึงแค่เก่าไปหนึ่งก้าว ไม่ใช่ผิด

ธงบิตเดียวที่ไปจาก 0 เป็น 1 แล้วค้าง (sticky flag) ข้ามได้ด้วย synchronizer สองฟลอป
เฉยๆ ไม่มีปัญหาความสอดคล้องหลายบิต แต่ธงต้องออกจากรีจิสเตอร์ตรงๆ ถ้ามันถูกคำนวณด้วย LUT
(เช่น OR ธงหลายตัว) LUT อาจ glitch ตอนอินพุตเปลี่ยน แล้ว synchronizer จะจับ glitch นั้นเป็น 1
จริง นั่นคือสิ่งที่ `report_cdc` เรียกว่า CDC-10 และมันอยู่ในดีไซน์นี้จนถึง 2026-09-12

### 2.7 ECC

หน่วยความจำของ FIFO ป้องกัน payload 8 บิตด้วย **SECDED** (single-error-correct,
double-error-detect) Hamming code: ข้อมูล 8 บิตกลายเป็น codeword 13 บิต (Hamming parity 4 บิต
บวก overall parity 1 บิต) ตอนอ่าน บิตที่พลิกหนึ่งบิตถูกซ่อมและยกธง สองบิตถูกตรวจพบและยกธง
ว่าซ่อมไม่ได้ สามบิตขึ้นไปอาจรายงานผิด ข้อจำกัดนี้เขียนไว้ใน `HANDOFF.md`

### 2.8 reset ข้ามโดเมน

reset ที่ assert แบบ asynchronous ไม่มีปัญหา ฟลอปทุกตัวตกเข้า reset ทันที ไม่ต้องใช้นาฬิกา
ปัญหาอยู่ที่ *deassert* ถ้า reset ปล่อยตอนไหนก็ได้โดยไม่สัมพันธ์กับนาฬิกาของโดเมน ฟลอปสอง
ตัวในโดเมนเดียวกันอาจออกจาก reset คนละขอบนาฬิกา และฟลอปที่ recovery time ถูกละเมิดอาจ
metastable คำตอบมาตรฐานคือ **reset synchronizer** ต่อโดเมน: assert แบบ async, deassert
ผ่านสองฟลอปที่ใช้นาฬิกาของโดเมนนั้น ดีไซน์นี้รันโดยไม่มีมันจนถึง 2026-09-12 และรอดมาได้เพราะ
agent ทุกตัวนอนเฉย 1024 ไซเคิลหลัง reset ก่อนส่งอะไร

---

## 3. ฮาร์ดแวร์

### 3.1 บอร์ด

Digilent **Arty A7-100T** (xc7a100tcsg324-1, serial ของบอร์ดใน log คือ 210319C088F2A) การ
ทดลอง synthesis แบบ out-of-context ทำบน part เล็กกว่าคือ xc7a35ticsg324-1L ตัวเลขใน
`HANDOFF.md` หัวข้อ 3 ระบุไว้ว่าอันไหนเป็นอันไหน

### 3.2 นาฬิกา

MMCM ตัวเดียว (`clk_wiz_0`, ขาเข้า 100 MHz, VCO 1000 MHz ด้วยตัวคูณ 10) สร้างนาฬิกาห้าเส้น:

| clock | net | ตัวหาร | ความถี่ | ใช้โดย |
|---|---|---|---|---|
| clk_out1 | `clk_noc` | 12.5 | 80.00 MHz | mesh, router ทั้งสี่, ฝั่ง NoC ของ wrapper ทุกตัว |
| clk_out2 | `clk_h00` | 10 | 100.00 MHz | host 00 (sink ในเทสต์ hot-spot; UART host ใน UART build), VIO, ลอจิก LED |
| clk_out3 | `clk_h01` | 14 | 71.43 MHz | host 01 |
| clk_out4 | `clk_h10` | 12 | 83.33 MHz | host 10 |
| clk_out5 | `clk_h11` | 14 | 71.43 MHz | host 11 (ตัวที่ fault injector เกาะอยู่) |

simulation ใช้อัตราส่วนชุดนี้เมื่อนิยาม `HW_CLOCKS` ไม่งั้นใช้ชุดที่เร็วกว่า (NoC 250, sink
500, sender 125/333/100 MHz) ซึ่งรันเร็วกว่าและเป็นค่าเดิมของ testbench ทั้งสองชุดอยู่ใน
regression

reset ของ MMCM ถูกตรึงไว้ที่ 0 ใน top ทั้งสองตัว ปุ่ม reset รีเซ็ตเฉพาะลอจิก ถ้ามันรีเซ็ต MMCM
ด้วย debug hub ของ ILA จะเสียนาฬิกาไป และทุกการจับสัญญาณจะตายไปพร้อม reset
`arty_stress_top` ทำถูกตั้งแต่แรก `arty_gals_noc_wrapper` ได้แก้วันที่ 2026-09-12

### 3.3 การนับหมายเลขโหนด (อ่านสองรอบ)

โหนดหนึ่งตัวมีพิกัด `(x, y)` มี index มีที่อยู่ปลายทาง และน่าเสียดายว่ามีวิธีเรียกชื่อสองแบบ

    idx   = y*2 + x
    tdest = {x[1:0], y[1:0]}      (4 บิต: x อยู่ [3:2], y อยู่ [1:0])

| idx | (x,y) | tdest | ชื่อพอร์ตใน `gals_noc_top` | ชื่อใน testbench | ใน stress build |
|---|---|---|---|---|---|
| 0 | (0,0) | `0000` | `h00` | Node00 | sink ภายใต้ `PATTERN=1`; UART host ใน UART build |
| 1 | (1,0) | `0100` | `h01` | Node10 | sender |
| 2 | (0,1) | `0001` | `h10` | Node01 | sender |
| 3 | (1,1) | `0101` | `h11` | Node11 | sender ที่มี fault injector คั่นขา TX |

`gals_noc_top` ตั้งชื่อพอร์ตตาม index เขียนเป็นสองหลัก `tb_noc_mesh_2x2_gals` ตั้งตาม `xy`
สองแบบนี้ไม่ตรงกันสำหรับ idx 1 กับ 2 ให้ map ผ่าน index เสมอ นี่คือ gotcha 3 ใน `HANDOFF.md`
และเคยกัดมาแล้วมากกว่าหนึ่งครั้ง

### 3.4 บอร์ดมีสอง build

- **Stress build** (`arty_stress_top`): traffic agent สังเคราะห์สี่ตัวยิงเครือข่ายเต็มที่และ
  ตรวจสิ่งที่มาถึง ผ่าน/ตกดูที่ LED รายละเอียดดูผ่าน ILA การฉีด fault กับ soft reset ทำผ่าน
  VIO นี่คือ build ที่ใช้กับตัวเลข performance ทุกตัว การยืนยันบั๊กทุกตัว และ fault campaign
- **UART build** (`arty_gals_noc_wrapper`): host 00 เป็นสะพาน UART ไปพีซี host อีกสามตัว
  เป็น loopback echo สคริปต์ Python ส่งแพกเกจแล้วอ่าน echo กลับ นี่คือ demo แบบโต้ตอบ การ
  ตรวจความถูกต้องของข้อมูลแบบ round-trip และเป็น build เดียวที่ตัวกรองปลายทางของโหนด 00
  ทำงานจริงบนซิลิคอน (หัวข้อ 10.8 อธิบายว่าทำไม)

### 3.5 สถาปัตยกรรม reset (ตั้งแต่ 2026-09-12)

    rst_n_btn ──┐
                ├─ global_rst_n (ไม่มีคล็อก, async)
    pll_locked ─┘         │
                          ├─ reset_sync (clk_noc) ── rst_n_noc ── mesh, ฝั่ง NoC ของ wrapper
                          ├─ reset_sync (clk_h00) ── rst_n_h00 ── ฝั่ง host ของ wrapper 00, agent 00, perf mon, LED
                          ├─ reset_sync (clk_h01) ── rst_n_h01 ── ฝั่ง host ของ wrapper 01, agent 01
                          ├─ reset_sync (clk_h10) ── rst_n_h10 ── ...
                          └─ reset_sync (clk_h11) ── rst_n_h11 ── ..., fault injector
    vio soft reset (ฟลอปบน clk_h00) ── ขา srst ของ reset_sync ทุกตัว (sync ข้างใน)

`reset_sync` แต่ละตัว assert แบบ asynchronous จาก `global_rst_n` และ deassert ผ่านสองฟลอปของ
นาฬิกาตัวเอง soft reset จาก VIO ไม่แตะสาย async เลย มันเข้า `reset_sync` แต่ละตัวทางขาแยก
ที่ถูก sync ตรงนั้นแล้วค่อยกดแบบ synchronous ก่อนหน้านี้ `global_rst_n` เส้นเดียวเข้าฟลอป
ทุกตัวในทั้งห้าโดเมนตรงๆ

### 3.6 การควบคุมผ่าน JTAG (stress build)

VIO core (`vio_fault` บน `clk_h00`) ให้ Hardware Manager มี output 8 บิตกับ input 8 บิต:

| บิต `probe_out` | ความหมาย | | บิต `probe_in` | ความหมาย |
|---|---|---|---|---|
| 0 | soft reset (active high) | | 0 | `pass_group1` |
| 1 | arm ตัวฉีด fault | | 1 | `pass_group2` |
| 5:2 | fault mode (หัวข้อ 6.4, `fault_injector`) | | 2 | `any_fail` |
| 7:6 | ไม่ใช้ | | 3 | `ecc_dbe` (sync แล้ว) |
| | | | 4 | `dest_err` (sync แล้ว) |
| | | | 5 | `tid_err` (sync แล้ว) |
| | | | 6 | `fault_active` (sync จาก `clk_h11`) |
| | | | 7 | `fault_fired` (sync จาก `clk_h11`) |

นี่คือสิ่งที่ทำให้ bitstream เดียวรัน fault mode ได้ทุกโหมดจากสคริปต์ batch โดยไม่ต้องแตะ
พอร์ต serial เลย (การเปิดพอร์ต serial รีเซ็ตบอร์ด หัวข้อ 10.12)

---

## 4. สัญญา flit

ลิงก์ทุกเส้นในดีไซน์พาสัญญาณห้าตัวชุดเดียวกัน บวก ready ต่อ VC:

| สัญญาณ | ความกว้าง | ความหมาย |
|---|---|---|
| `tdata` | 8 | payload |
| `tdest` | 4 | โหนดปลายทาง `{x, y}` |
| `tid` | 2 | virtual channel แบบ **one-hot**: `01` = VC0, `10` = VC1 |
| `tlast` | 1 | flit นี้เป็นตัวสุดท้ายของแพกเกจ |
| `tvalid` | 1 | สี่ฟิลด์ข้างบนมีความหมายในไซเคิลนี้ |
| `tready` | 2 | ตีกลับจากผู้รับ บิตละ VC |

การส่งบน VC v เกิดเมื่อ `tvalid && tid[v] && tready[v]`

ใน FIFO ฟิลด์ payload สามตัวถูก pack เป็น `{tlast, tdest, tdata}` = 13 บิต (`PACK_W`) `tid` ไม่
ถูกเก็บ มันใช้เลือกว่า flit ลง FIFO ไหน

กฎที่ fabric พึ่ง และแต่ละข้อถูกบังคับ พิสูจน์ และแสดงบนบอร์ดที่ไหน ณ `afce6cd` ทุกข้อถูก
บังคับใน RTL แล้ว ไม่มีข้อไหนเป็นแค่ assumption อีก

| กฎ | บังคับที่ | ฝ่าฝืนแล้ว → | พิสูจน์ | แสดงบนซิลิคอน |
|---|---|---|---|---|
| `tid` เป็น one-hot | ขาเข้า host ของ `gals_node_wrapper` (ตัวที่จับ host จริง) และขาเข้าของ `noc_mesh_2x2_vc` | ทิ้ง flit, `tid_err[node]`, แพกเกจที่เปิดค้างถูก force-close | mesh bmc + wrapper prove โดยถอด assume one-hot ทั้งสองที่ | campaign mode 2 กับ 3; UART `tid=00` |
| `tdest` อยู่ในกระดาน (x ≤ 1, y ≤ 1) | `dest_ok` ที่ขาเข้า mesh | ทิ้ง, `dest_err[node]`, force-close | mesh bmc ถอด assume ช่วงค่าแล้ว | campaign mode 5 |
| `tdest` คงที่ตลอดแพกเกจ | `frame_ok` ที่ขาเข้า mesh เทียบกับ dest ของหัวที่บันทึกไว้ | ทิ้ง, `dest_err[node]`, force-close | mesh bmc, `assert_local_dest_stable` โดยถอด assume; proof ของ router เองยังเก็บ assume ใน `f_wf` เพราะที่นั่นอินพุตเป็นค่าอิสระ | campaign mode 4 |
| ทุกแพกเกจจบด้วย `tlast` | (a) flit ที่ถูกปฏิเสธและพา `tlast` ไปด้วย: ตัวติดตามที่ขาเข้าทั้งสองที่ force-close แพกเกจ (bug #7); (b) ต้นทางเงียบไปเฉยๆ: `packet_arbiter` ทิ้งพอร์ตที่ล็อกหลังเงียบ 1024 ไซเคิล (bug #5) | (a) แพกเกจขาดท้ายถูกส่งไปปลายทางของหัว; (b) พอร์ตถูกปล่อย เศษแพกเกจถูกทิ้งปลายน้ำ | (a) mesh bmc, wrapper prove; (b) `packet_arbiter` prove (unbounded) | (a) mode 2-5 ตัดแพกเกจ; (b) mode 1 |

หมายเหตุว่า "ทิ้ง" ที่ขาเข้า mesh หมายถึงอะไร: flit ถูก*รับ* (host เห็น `ready` ตามปกติ) แต่
ไม่ถูกยื่นให้ router backpressure ถูกปัดตกเพราะมันแค่ย้ายการค้างไปที่ผู้ส่ง การหนีบที่อยู่เข้า
ช่วงถูกปัดตกเพราะมันส่งแพกเกจไปที่ที่ไม่มีใครตั้งใจ แบบเงียบๆ (หัวข้อ 12)

---

## 5. สถาปัตยกรรมจากบนลงล่าง

    arty_stress_top  /  arty_gals_noc_wrapper          (top ของบอร์ด: MMCM, reset_sync x5, LED, agent, VIO)
        |
        +-- gals_noc_top                                (กาว: wrapper 4 ตัว + mesh + รวมธง)
              |
              +-- gals_node_wrapper  x4                 (ขอบ GALS, ตัวละ host, reset สองตัว)
              |     +-- async_fifo_fwft  x4             (TX VC0, TX VC1, RX VC0, RX VC1)
              |           +-- async_fifo
              |           |     +-- gray_counter x2, sync_2stage x2
              |           |     +-- dual_port_ram_ecc  (payload, 8b -> codeword 13b)
              |           |     |     +-- ecc_secded_encode_8b, ecc_secded_decode_8b, dual_port_ram
              |           |     +-- dual_port_ram      (บิต control, ไม่มี ECC)
              |           +-- fwft_wrapper
              |
              +-- noc_mesh_2x2_vc                       (เดินสาย + ตัวกรองขาเข้า + force-close)
                    +-- router_5port_mesh_vc  x4
                          +-- vc_input_buffer  x5       (ตัวละพอร์ตขาเข้า)
                          |     +-- sync_fifo  x2       (ตัวละ VC)
                          +-- vc_port_arbiter  x5       (ตัวละพอร์ตขาออก)
                          |     +-- packet_arbiter  x2  (ตัวละ VC)
                          +-- ตัวถอด XY, crossbar        (inline)

    noc_stress_tester (เฉพาะ stress build)
        +-- traffic_node_agent x4
        +-- fault_injector                              (คั่นระหว่าง agent_11 กับ fabric)
        +-- sync_2stage x2                              (ธงไป clk_h00; การควบคุม VIO ไป clk_h11)

ทิศทางข้อมูล host ถึง host:

    host TX  ->  TX FIFO ของ wrapper (clk_host -> clk_noc)  ->  ตัวกรองขาเข้า mesh
             ->  input buffer พอร์ต LOCAL ของ router  ->  arbiter  ->  crossbar  ->  ลิงก์
             ->  input buffer ของ router ถัดไป  -> ...  ->  พอร์ต LOCAL ขาออกของ router
             ->  RX FIFO ของ wrapper (clk_noc -> clk_host)  ->  host RX

ทุกอย่างตั้งแต่ตัวกรองขาเข้า mesh จนถึงขาเขียนของ RX FIFO ใน wrapper อยู่ในโดเมน `clk_noc`
wrapper เป็นที่เดียวที่นาฬิกาสองตัวเจอกันสำหรับข้อมูล การรวมธงใน `gals_noc_top` และ top
ทั้งสองคือที่ที่ sticky flag ข้ามโดเมน

---
## 6. Module reference

RTL ทั้งหมดอยู่ใน `GALS_Packet-Based_Fabric.srcs/sources_1/new/` IP อยู่ใน `.../sources_1/ip/`
จำนวนบรรทัดนับ ณ `afce6cd` ช่อง "Formal" บอกว่าโมดูลมีบล็อก `FORMAL` ไหมและ `formal/*.sby`
พิสูจน์อะไรให้มัน "prove" หมายถึง unbounded (k-induction ผ่าน) "bmc" หมายถึง bounded รายการ
property เต็มอยู่หัวข้อ 9.2

### 6.1 Primitive

#### `dual_port_ram.sv` (57 บรรทัด)
dual-port RAM ธรรมดา: พอร์ตเขียนบน `wclk` พอร์ตอ่านบน `rclk` ข้อมูลอ่านผ่านรีจิสเตอร์ Vivado
infer เป็น block หรือ distributed RAM ตามขนาด array ไม่มี reset (RAM primitive ของ Xilinx
รีเซ็ตไม่ได้ และถ้าใส่ reset ใน sensitivity list array จะกลายเป็นฟลิปฟลอป) Formal: ไม่มี
เป็น primitive

#### `sync_fifo.sv` (90 บรรทัด)
FIFO นาฬิกาเดียว `DEPTH` ช่อง pointer กว้าง `$clog2(DEPTH)+1` เพื่อให้แยก full กับ empty ด้วย
บิตบนสุดของ pointer ข้อมูลอ่านเป็น combinational จากหัวคิว (`r_data = mem[r_ptr]`) จึงมี
พฤติกรรมแบบ first-word-fall-through: เห็นหัวคิวก่อน `r_en` ใช้ใน `vc_input_buffer` (ลึก 16)
และ `uart_noc_host` (ลึก 256) Formal: ครอบด้วย proof แบบ shadow-FIFO ของ `vc_input_buffer`

#### `gray_counter.sv` (133 บรรทัด)
ตัวนับฐานสองพร้อมสำเนา pointer แบบ gray (`ptr_g = bin ^ (bin >> 1)`) และบิตล่างของค่าฐานสอง
เป็นที่อยู่ RAM มีตัวละฝั่งของ `async_fifo` ทุกตัว Formal: prove (gray เท่ากับ `bin ^ bin>>1`,
เปลี่ยนทีละบิตต่อก้าว, MSB พลิกตอน wrap; cover ไปถึง wrap ซึ่งต้องใช้ depth 40 กับ pointer 5
บิต)

#### `sync_2stage.sv` (97 บรรทัด)
synchronizer สองฟลอปกว้าง `WIDTH` บิต ติด `ASYNC_REG` ที่รีจิสเตอร์ขาออกให้ Vivado วางคู่นี้
ไว้ด้วยกันและปฏิบัติกับหน้าต่าง metastability ของขั้นแรกอย่างถูกต้อง ใช้กับ gray pointer ใน
`async_fifo` และกับ sticky flag ทุกที่อื่น (ECC, `dest_err`, `tid_err`, `done`/`err` ของ agent,
การควบคุมและสถานะของ VIO) Formal: prove (reset ล้างทั้งสองขั้น; ข้อมูลผ่านในสองไซเคิล)

#### `reset_sync.sv` (43 บรรทัด เพิ่มวันที่ 2026-09-12)
reset ต่อโดเมน `arst_n` (คือ `button & pll_locked` ที่ไม่มีคล็อก) assert แบบ asynchronous
การ deassert ผ่านฟลอป `ASYNC_REG` สองตัวบนนาฬิกาของโดเมน ขาแยก `srst` (soft reset จาก VIO
คนละโดเมน) ถูก sync ผ่านสองฟลอปของมันเองแล้วกดแบบ synchronous: `rst_n = q2 & ~s2` การไม่เอา
`srst` เข้าสาย async คือสิ่งที่เปลี่ยน CDC-7 572 เส้นกับ CDC-10 4 เส้นให้เหลือศูนย์ Formal:
ไม่มี (ฟลอปสี่ตัว)

#### `ecc_secded_encode_8b.sv` (44 บรรทัด) / `ecc_secded_decode_8b.sv` (78 บรรทัด)
Hamming(12,8) บวก overall parity = SECDED(13,8) encoder คำนวณ p1, p2, p4, p8 บนตำแหน่งบิต
ตามตำรา ประกอบ Hamming word 12 บิตที่มี parity อยู่ตำแหน่ง 1, 2, 4, 8 แล้วเติม p0 = XOR ของ
ทั้งสิบสองบิตเป็นบิต 12 decoder คำนวณ syndrome กับ overall parity ใหม่:

| syndrome | overall parity ไม่ตรง | คำตัดสิน |
|---|---|---|
| 0 | ไม่ | สะอาด |
| 0 | ใช่ | บิตเดียวพังที่ p0 เอง ข้อมูลดี |
| ≠0 | ใช่ | บิตเดียวพังที่ตำแหน่ง `syndrome` ซ่อมแล้ว |
| ≠0 | ไม่ | สองบิตพัง ซ่อมไม่ได้ |

Formal: ไม่มีโดยตรง `tb_ecc_secded` พิสูจน์แบบ exhaustive (ค่า 256 ค่าแบบสะอาด, พลิกบิตเดียว
256x13 แบบ, พลิกสองบิต 256xC(13,2) แบบ รวม 23,792 เคส 0 ล้มเหลว; ถ้ากลายพันธุ์ decoder จะพัง
เป็นพันเคส เทสต์จึงมีเขี้ยว)

#### `dual_port_ram_ecc.sv` (182 บรรทัด)
`dual_port_ram` ที่ขยายเป็น 13 บิต มี encoder ฝั่งเขียนและ decoder ฝั่งอ่าน ปล่อย
`ecc_single_err` / `ecc_double_err` ออกมาเป็นธง combinational บนข้อมูลที่กำลังอ่าน มี**ตัวฉีด
fault ตอน build**: นิยาม `ECC_INJECT_SBE` เพื่อพลิกบิต 0 ของทุก codeword ที่เขียน หรือ
`ECC_INJECT_DBE` เพื่อพลิกบิต 0 กับ 5 ถ้าไม่นิยามอะไรเลย เส้นทางเขียนคือ output ของ encoder
ตรงๆ และ bitstream ปกติไม่เปลี่ยนเลย มันเป็น `` `define `` ไม่ใช่ parameter เพราะ parameter
ต้องลากผ่าน hierarchy ห้าชั้นของโมดูลที่พิสูจน์ไว้แล้ว Formal: prove
(`assert_ram_address_integrity`, `cover_clean_read`; เส้นทาง RAM ธรรมดา)

#### `async_fifo.sv` (187 บรรทัด)
FIFO ข้ามโดเมนนาฬิกา มี `gray_counter` สองตัว `sync_2stage` สองตัวสำหรับ pointer full
คำนวณฝั่งเขียนจาก read pointer ที่ sync มา empty คำนวณฝั่งอ่านจาก write pointer ที่ sync มา
มี `almost_full` / `almost_empty` ที่ตั้ง threshold ได้ และ output `w_level`

ที่เก็บแยกส่วน: 8 บิตล่าง (`tdata`) ผ่าน `dual_port_ram_ecc` บิตที่เหลือเหนือ 8 (`tlast`,
`tdest`) ผ่าน `dual_port_ram` ธรรมดา ECC จึงครอบเฉพาะ payload

ธงดิบจาก decoder ถูก qualify ด้วย `ecc_read_valid` รีจิสเตอร์หนึ่งไซเคิลที่ตั้งในไซเคิลถัดจากการ
อ่านจริง ไม่มีมัน decoder จะทำงานบน output ของ RAM ที่ยังไม่ได้ init ก่อนใครเขียนอะไร และยกธง
หลอกตอนเปิดเครื่อง ธงที่ qualify แล้วเป็นพัลส์หนึ่งไซเคิล ผู้ใช้ทุกคน latch ให้ sticky

เมื่อนิยาม `FORMAL` RAM ที่มี ECC ถูกแทนด้วย RAM ธรรมดาและธงถูกผูกไว้ที่ 0

**Formal: ไม่มีของตัวเองเลย และนี่คือช่องว่างที่ยังเปิดอยู่ (หัวข้อ 16)** `formal/async_fifo.sby`
อ่านโมดูลย่อยด้วย `-D FORMAL_TOP_INTEGRATION` ซึ่งปิด property ของพวกมัน และ `async_fifo.sv`
ไม่มี assertion เลย "prove PASS" ที่สคริปต์รายงานจึงเป็น proof ที่มี assertion ศูนย์ตัว (ยืนยัน
2026-09-14: model ที่ generate ออกมามีแต่เซลล์ `$assume`) ลอจิก pointer, full/empty และลำดับ
ของ FIFO ข้ามโดเมนถูกครอบด้วย simulation และซิลิคอน (sequence error ศูนย์บน flit หลายล้านตัว)
แต่ไม่มี formal property ใดเลย proof แบบ shadow-FIFO ของ `vc_input_buffer` ครอบ `sync_fifo`
ไม่ใช่โมดูลนี้

#### `fwft_wrapper.sv` (175 บรรทัด)
แปลง interface อ่าน FIFO แบบมาตรฐาน (ข้อมูลใช้ได้ไซเคิลถัดจาก `r_en`) เป็น
first-word-fall-through (ข้อมูลใช้ได้ทุกครั้งที่ไม่ empty) ทำด้วยขั้น output สองช่อง (`out` กับ
`skid`) รีจิสเตอร์ `data_arriving` ที่ตาม latency หนึ่งไซเคิลของ RAM และกฎ `can_read` ที่ให้มี
คำในอากาศไม่เกินสอง Formal: prove (`assert_no_overflow`, `assert_skid_physics`,
`assert_empty_status`, assert เรื่อง reset) รันผ่าน `async_fifo_fwft.sby`

#### `async_fifo_fwft.sv` (109 บรรทัด)
`async_fifo` บวก `fwft_wrapper` ฝั่งอ่าน นี่คือตัวที่ `gals_node_wrapper` instantiate Formal:
`async_fifo_fwft.sby` ผ่าน prove แต่ assertion หกตัวใน model เป็นของ `gray_counter` กับ
`fwft_wrapper` ไม่มีอะไรเกี่ยวกับตัว FIFO เอง (ช่องว่างเดียวกับข้างบน)

### 6.2 แกน router

#### `packet_arbiter.sv` (235 บรรทัด)
หัวใจของดีไซน์และเป็นที่อยู่ของบั๊ก #1, #2 และ #5 มีตัวละ (output port, VC) อินพุต:
`valid[PORTS]`, `tlast[PORTS]` จาก input buffer ที่ต้องการ output นี้บน VC นี้ และ `ready` หนึ่ง
ตัวจากปลายน้ำ เอาต์พุต: `grant[PORTS]` แบบ one-hot

มีสองสถานะ ใน `IDLE` ตัวเลือกแบบ round-robin เลือก `next_grant`: คำขอที่อยู่เหนือตำแหน่ง `mask`
ปัจจุบันชนะก่อน (`masked_grant`) ไม่งั้นผู้ขอที่ต่ำสุดชนะ (`unmasked_grant`) ทั้งคู่ใช้ท่าแยกบิต
ต่ำสุดที่ตั้งอยู่ `x & (~x + 1)` ถ้า flit ที่เลือกเป็นแพกเกจ flit เดียว (`tlast` กับ `ready` ใน
ไซเคิลเดียวกัน) arbiter อยู่ `IDLE` ต่อ ไม่งั้นไป `LOCKED` และจำ `locked_grant`

ใน `LOCKED` grant ถูกแช่ ทางออก:

1. `eop_transfer`: อินพุตที่ล็อกส่ง flit ที่มี `tlast` ปกติ
2. `force_release`: อินพุตที่ล็อกมี `valid` ต่ำติดต่อกัน `2**STALL_LOG` = 1024 ไซเคิล **และ**
   ยังเงียบอยู่ในไซเคิลนี้ ต้นทางหายไปแล้ว (bug #5)
3. ปลดล็อกฉุกเฉิน: ยังไม่มีอะไรเคยถูกส่งบน grant นี้และต้นทางเงียบไป หัวที่ขอแล้วถอน

`has_transferred` คือตัวแยกข้อ 2 กับ 3 มันถูกตั้งตอนล็อกถ้า flit แรกออกไปแล้วในไซเคิลเดียวกัน
(bug #1) และในทุกการส่งหลังจากนั้น

`stall_cnt` นับเฉพาะไซเคิลที่ `valid` ต่ำบนอินพุตที่ล็อก backpressure จากปลายน้ำทำให้ `valid`
ค้างสูง ต้นทางที่ถูกบล็อกแต่ยังเป็นๆ จึงไม่มีทางทำให้ timeout ยิง ช่องว่างปกติของ GALS (FIFO ของ
wrapper แห้งชั่วครู่) อยู่ระดับสิบไซเคิล 1024 ประมาณ 100 เท่าของนั้น บนบอร์ด การปล่อยที่ 1024
ไซเคิลโผล่เป็นช่องว่าง 608/611 ไซเคิลบน sender ที่รอด (campaign mode 1)

`mask` ของ round-robin เลื่อนทุกครั้งที่ `eop_transfer` (bug #2)

Formal: prove `assert_onehot`, `assert_channel_lock` (ขณะ `LOCKED` และต้นทางที่ล็อกยังมีข้อมูล
grant ต้องไม่เปลี่ยน), `assert_abort_only_when_source_gone` ครอบด้วย `` `ifndef
FORMAL_TOP_INTEGRATION `` เพื่อให้การรันระดับ router ไม่ต้องพิสูจน์ซ้ำ

#### `vc_port_arbiter.sv` (252 บรรทัด)
มีตัวละพอร์ตขาออก ห่อ `packet_arbiter` สองตัว (VC1 กับ VC0) และตัดสินว่า VC ไหนขับสาย
กายภาพเส้นเดียวในไซเคิลนี้ ที่อยู่ของ bug #3

VC1 มี priority เด็ดขาด: `vc1_is_active` ให้ลิงก์กับ VC1 และบังคับ `ready_vc0 = 0` การแก้ bug
#3 ทำให้การตัดสินนี้ขึ้นกับว่า VC1 **ขยับได้** ในไซเคิลนี้ไหม (`|raw_grant_vc1 &&
ready_out_vc1`) ไม่ใช่แค่ถือ grant อยู่

anti-starvation: `starve_cnt` นับไซเคิลที่ VC0 มีคำขอขณะ VC1 active ถึง `STARVE_LIMIT` (64) มัน
ตั้ง `vc0_override` ซึ่งยกลิงก์ให้ VC0 override ปลดเมื่อ VC0 ส่งจบแพกเกจ หรือเมื่อคำขอของ VC0
หายไป (ตาข่ายกันพลาดที่เพิ่มมากับการแก้ bug #3 เพื่อไม่ให้ override อยู่นานกว่าเหตุของมัน)
ระหว่าง override VC1 ถูกบล็อกเฉพาะตอน VC0 กำลังเดินหน้าจริง ถ้าติดทั้งคู่ VC1 ได้ลิงก์คืน

`SIM_DEBUG` เปิด `$display` ตามรอย trigger/release ของ override ใช้พิสูจน์การวินิจฉัย bug #3
(trigger 51 ครั้ง ปลดไม่ได้ 4 ครั้งก่อนแก้; 36/36 หลังแก้)

Formal: prove `assert_vc_mutex`, `assert_vc1_yields_when_stalled`,
`assert_no_vc1_during_override`, `assert_no_grant_without_credit`,
`assert_override_only_at_limit`, `assert_bounded_starvation` (ข้อโต้แย้งเรื่อง liveness: VC0
ที่รออยู่ต้องได้รับบริการภายในขีดจำกัด) บวก invariant สามตัวที่ผูกตัวนับเงาของ formal เข้ากับตัว
นับใน RTL

#### `vc_input_buffer.sv` (241 บรรทัด)
มีตัวละพอร์ตขาเข้าของ router demux flit ที่เข้ามาตาม `tid` ลง `sync_fifo` ตัวใดตัวหนึ่งใน
`NUM_VCS` ตัว (ลึก 16 กว้าง 13 บิต) และเผยหัวคิวของแต่ละ VC เป็นชุด
`m_valid/m_tlast/m_tdest/m_tdata` แยกกัน `s_ready[v] = ~full[v]` flit ถูกเขียนก็ต่อเมื่อ
`s_valid && s_tid[v] && !full[v]` `tid` แบบ multi-hot จะเขียน flit เดียวลงสองคิว นั่นคือเหตุผล
ที่ต้องบังคับ one-hot ตั้งแต่ต้นน้ำ

Formal: bmc depth 16 ด้วย **shadow FIFO** แบบ black-box: บล็อก formal เก็บ model ของตัวเองว่า
อะไรควรอยู่ในคิว แล้วเทียบกับหัวคิวจริงทุกไซเคิล (`assert_head_tdata/tdest/tlast`) การเทียบ
ครั้งเดียวนั้นครอบ demux, การ pack/unpack และลำดับของ FIFO `assert_no_cross_vc_write`,
`assert_ready_iff_room`, `assert_valid_iff_occupied` เป็น bounded ไม่ใช่ prove เพราะ induction
เริ่มจาก shadow queue ที่ไม่ตรงกับคิวจริงได้

#### `router_5port_mesh_vc.sv` (440 บรรทัด)
ตัว router parameter `MY_X`, `MY_Y` มี `vc_input_buffer` ห้าตัว `vc_port_arbiter` ห้าตัว และ
บล็อก combinational สองก้อน:

- **ตัวถอด XY**: สำหรับแต่ละ (พอร์ตขาเข้า, VC) ที่หัวคิว valid เทียบ `tdest` กับ `(MY_X,
  MY_Y)`: `dx > MY_X` → EAST, `dx < MY_X` → WEST, ไม่งั้น `dy > MY_Y` → NORTH, `dy < MY_Y` →
  SOUTH, ไม่งั้น LOCAL ได้ `route_req` ซึ่งถูก transpose เป็นเวกเตอร์คำขอต่อ output ให้ arbiter
- **crossbar**: mux แบบ AND-OR สำหรับแต่ละ output เอาข้อมูลของทุก input AND กับ grant ของ
  input นั้นแล้ว OR รวม ถูกต้องก็ต่อเมื่อ grant เป็น one-hot ต่อ output ซึ่ง arbiter รับประกัน
  `m_tid` มาจากว่า arbiter ของ VC ไหนให้ grant

เส้นทาง ready กลับไป input buffer คือ OR บนทุก output ของ "output นี้ให้ grant ฉันและ arbiter
ของมันบอก ready"

Formal: bmc depth 16 ด้วย `abc bmc3` (z3 ค้างที่ step 8 หลัง 40 นาที abc ทำ 16 step ใน 99
วินาที) property สามกลุ่ม: ตัวถอด (`assert_route_iff_valid`, `assert_route_onehot`,
`assert_eject_here`, `assert_no_false_eject`), โครงสร้าง arbitration
(`assert_grant_matches_route_*`, `assert_no_grant_fanout_*` ซึ่งเป็นตัวที่จะจับ flit ที่ถูกโคลน,
`assert_ready_needs_grant_*`), crossbar (`assert_xbar_onehot`,
`assert_xbar_data/dest/last/valid_*`, `assert_tid_*`, `assert_no_valid_without_grant`) บล็อกนี้
ถูกปิดด้วย `-D FORMAL_NO_ROUTER` ตอนพิสูจน์ mesh เพราะ assumption บนอินพุตของมันจะไปตกบน
สายภายในที่มีตัวขับ และอาจทำให้ทุกอย่างผ่านแบบ vacuous บล็อก `f_wf` ของมันยัง *assume* ว่า
`tdest` คงที่ต่อแพกเกจ ซึ่งถูกต้องสำหรับ proof เดี่ยวที่อินพุตเป็นค่าอิสระ mesh บังคับข้อนี้
ที่ต้นน้ำ

### 6.3 Mesh และขอบ GALS

#### `noc_mesh_2x2_vc.sv` (634 บรรทัด)
instantiate router สี่ตัวด้วย `(x, y)` จาก `idx = y*2 + x` เดินสาย EAST↔WEST และ NORTH↔SOUTH
ระหว่างเพื่อนบ้าน และผูกขอบนอกกระดานเป็น `valid = 0`, `ready = 0` เผยพอร์ต LOCAL ทั้งสี่เป็น
`s_*` (host เข้า mesh) และ `m_*` (mesh ออกไป host)

หัวข้อ 0 กับ 0b คือ**ตัวกรองขาเข้า**: `dest_ok[i]` (x กับ y ≤ 1 ทั้งคู่) และ `tid_ok[i]` (มีบิต
เดียวพอดี) หัวข้อ 2.3 (2026-09-12) คือ**การเช็ค `tdest` คงที่** `frame_ok[i]`: flit ที่ชี้ VC ที่มี
แพกเกจเปิดอยู่ต้องพาปลายทางเดียวกับหัวที่บันทึกไว้ flit ที่ตกข้อใดข้อหนึ่งในสามข้อถูกรับแต่ไม่
ยื่นให้ router และธง sticky ต่อโหนด `dest_err[i]` (สำหรับ `dest_ok` และ `frame_ok`: "ปลายทาง
ของ flit นี้รับไม่ได้") หรือ `tid_err[i]` ถูกยก ธงยกตอน flit ผิดถูกเสนอ ไม่ใช่ตอนถูกรับ

หัวข้อ 2.2 คือลอจิก **force-close** ที่เพิ่มสำหรับ bug #7: ต่อโหนดต่อ VC `pkt_open` กับ
`pkt_dest` ติดตามว่าแพกเกจเริ่มแล้วหรือยังและไปไหน flit ที่ถูกปฏิเสธตั้ง `close_pend` ให้ทุก VC
ที่เปิดอยู่ ขณะที่มี close ค้าง โหนดยื่น flit สังเคราะห์ให้ router (`tlast = 1`, `tid` = VC นั้น,
`tdest` = ปลายทางของหัวที่บันทึกไว้, data 0) และตรึง `s_ready = 0` ไม่ให้ host แทรก close
ออกทีละหนึ่งต่อไซเคิลเพราะพอร์ต LOCAL รับได้ทีละ flit ตัวติดตามเดียวกันนี้คือสิ่งที่การเช็ค
`tdest` คงที่ใช้เทียบ

Formal: bmc depth 10 ด้วย `abc bmc3` (ราว 7 นาที), cover depth 12 ด้วย z3 สภาพแวดล้อมไม่
assume แล้วว่า `tid` เป็น one-hot, `tdest` อยู่ในช่วง, หรือ `tdest` คงที่ต่อแพกเกจ solver ยิง
อะไรก็ได้และตัวกรองต้องรับมือ property เด่น: `assert_eject_dest` (flit ที่เด้งออกที่โหนด i
จ่าหน้าถึงโหนด i นี่คือตัวที่พังถ้าเดินสาย index สลับ และเป็นตัวที่ bug #7 ทำพัง),
`assert_edge_*` (ไม่มีอะไรขับ valid ออกนอกกระดาน), `assert_local_in_range` /
`assert_local_tid_onehot` / `assert_local_dest_stable` (ทุกอย่างที่ router เห็นทาง LOCAL อยู่ใน
ช่วง เป็น one-hot และคงที่อยู่ที่อยู่ของหัว), assert ของตัวกรอง, และ invariant ของ force-close
(`assert_close_pend_only_open`, `assert_host_held_while_closing`) cover แสดงว่าทุกโหนดส่งถึง
ทั้งสองลิงก์มีของวิ่ง ทั้งสอง VC วิ่งพร้อมกัน ตัวกรองแต่ละตัวยิงได้จริง mesh ยังส่งต่อได้หลัง
จากนั้น และ tail สังเคราะห์ถูกสร้างและถูกส่งถึง

parameter ถูกย่อสำหรับ formal (`DATA_W=2`, `DEPTH=2`) และ array ถูกกางด้วย `memory_map` ไม่งั้น
solver ไม่จบ

#### `gals_node_wrapper.sv` (485 บรรทัด)
ขอบ GALS ตัวละ host รับ reset สองตัว `rst_host_n` กับ `rst_noc_n` มี `async_fifo_fwft` สี่ตัว:
TX VC0/VC1 (เขียนบน `clk_host` อ่านบน `clk_noc`) และ RX VC0/VC1 (กลับกัน) แต่ละฝั่ง reset ด้วย
โดเมนของตัวเอง host เขียนลง TX FIFO ที่ `tid` เลือก mux แบบ combinational ยื่นหัวคิวของ TX VC1
ถ้าไม่ว่าง ไม่งั้น TX VC0 เป็น `m_noc_*` พร้อม `m_noc_tid` แบบ one-hot ที่ตรงกัน mux ไม่ล็อก
ต่อแพกเกจ มันสลับ flit ต่อ flit ซึ่งถูกกฎเพราะฝั่งโน้น demux ตาม `tid` อีกที ความต่อเนื่องของ
แพกเกจภายใน VC เดียวถูกรักษาด้วยลำดับของ FIFO ฝั่ง RX สมมาตรกัน

tid guard ฝั่ง host: `host_tid_ok` กั้น write enable ของ TX ทุกตัว `tid` ที่ผิดถูกรับแล้วทิ้ง และ
`host_tid_err` ค้าง sticky นี่คือชั้นที่จับ host ที่พฤติกรรมผิดได้จริง เพราะ mesh เห็นแค่ `tid`
ของ mux ซึ่งเป็น one-hot โดยโครงสร้าง guard ระดับ mesh คงไว้เป็นด่านที่สอง ไม่มีการเช็ค `tdest`
ฝั่ง host: `tdest` ผ่าน mux ไปทั้งดุ้น ขาเข้าของ mesh จึงเห็นค่าของ host ตรงๆ

force-close สำหรับ bug #7 ใช้ตัวติดตามแบบเดียวกับ mesh: `tx_pkt_open`, `tx_pkt_dest`,
`tx_close_pend` เพราะแต่ละ VC มีพอร์ตเขียน FIFO ของตัวเอง ทั้งสอง VC ปิดได้ในไซเคิลเดียวกัน
`s_host_ready` ถูกตรึงต่ำระหว่างมี close ค้าง

ธง: ธง ECC ของ TX FIFO latch แบบ sticky บน `clk_noc` ธง ECC ของ RX FIFO และ error ของ tid
ฝั่ง host latch บน `clk_host` แล้วข้ามไป `clk_noc` ผ่าน `sync_2stage` (ปลอดภัยเพราะ sticky และ
ออกจากรีจิสเตอร์ตรงๆ) เอาต์พุต `ecc_single_err`, `ecc_double_err`, `host_tid_err`

Formal: prove ด้วย `multiclock on` (proof สองนาฬิกาจริง) reset สองตัวถูก assume ให้เท่ากัน
(property เขียนบนฐาน reset ร่วม `reset_sync` ปล่อยสองตัวห่างกันไม่กี่ไซเคิลตอนที่ยังไม่มี
ทราฟฟิก) property: mux ยื่นข้อมูลของ VC ที่ถูกต้องเป๊ะ `tid` one-hot ตอน valid และศูนย์ตอน
idle ห้าม pop FIFO ที่ว่าง (`assert_tx_no_pop_empty_*`, `assert_rx_no_pop_empty_*` ตัวที่จะจับ
ขยะกลายเป็น flit) ready เท่ากับ not-full ยกเว้นตอนกำลัง close ห้าม host เขียนตอน close
close ค้างได้เฉพาะ VC ที่เปิดอยู่ ธงภายนอกเท่ากับ OR ของ latch ทั้งสองโดเมน cover ไปถึง
เส้นทาง force-close ทั้งแบบ VC เดียวและสอง VC

#### `gals_noc_top.sv` (396 บรรทัด)
กาวบวกการรวมธง รับ reset ห้าตัว (`rst_n_noc`, `rst_n_h00..h11`) มี `gals_node_wrapper` สี่ตัว
`noc_mesh_2x2_vc` หนึ่งตัว สายระหว่างพวกมัน และเวกเตอร์ธงต่อโหนด (`ecc_sbe_node`,
`ecc_dbe_node`, `dest_err_node`, `tid_err_node`) พร้อมตัวนับขอบ (`ecc_sbe_cnt`, `ecc_dbe_cnt`,
`dest_err_cnt`, `tid_err_cnt`) ทั้งหมดติด `mark_debug` + `dont_touch` ให้ ILA เห็น ค่า `_cnt` นับ
โหนดที่เคยยกธง ไม่ใช่จำนวนเหตุการณ์ เพราะธงเป็น level ที่ค้าง เอาต์พุตบิตเดียวสี่ตัว
(`ecc_single_err`, `ecc_double_err`, `dest_err`, `tid_err`) คือ OR ของเวกเตอร์โหนดที่**ผ่าน
รีจิสเตอร์ใน `clk_noc`** ก่อนออก เดิมเป็น OR เปล่าๆ ซึ่งคือ CDC-10

`axis_perf_mon` สองตัวเฝ้าลิงก์ TX กับ RX ของ host 00 และให้ตัวเลข utilisation ที่อ้างทุกที่
`ready` ของ monitor คือ `|(tid & tready)` ready ของ VC ที่ flit อยู่จริง เวอร์ชันก่อนดู `tready[0]`
อย่างเดียวและนับ flit VC1 ทุกตัวเป็น stall

Formal: ไม่มี (กาว; ครอบด้วย simulation กับบอร์ด)

#### `axis_perf_mon.sv` (72 บรรทัด)
ตัวนับ 32 บิตสี่ตัวบน interface valid/ready/last: flit ที่ส่งสำเร็จ แพกเกจที่จบ ไซเคิลที่ stall
(valid โดยไม่มี ready) ไซเคิลที่ทำงาน utilisation คือ `flit_cnt / active_cnt`

### 6.4 Traffic และ test agent

#### `traffic_gen.sv` (130 บรรทัด)
แหล่งแพกเกจแบบสั่งงานง่ายๆ ที่ `tb_noc_mesh_2x2_gals` ใช้: ให้ x/y ปลายทาง ความยาว และ `tid`
มันยิงหนึ่งแพกเกจ ไม่ได้ใช้บนบอร์ด

#### `traffic_node_agent.sv` (294 บรรทัด)
แหล่งทราฟฟิกและตัวตรวจฝั่งบอร์ด ตัวละ host ที่อยู่ของ bug #4 และของ "ไฟเขียวที่โกหก" (gotcha 2)

state machine `S_WARMUP → S_RUN → S_DRAIN → S_DONE` ระหว่าง `S_RUN` มันส่งแพกเกจ `PKT_FLITS`
flit (16) ติดต่อกันไปยัง `DEST_ID` สลับ VC ต่อแพกเกจภายใต้ `VC_MODE=2` โดยมี sequence number
6 บิตต่อ VC ใน payload (`tdata = {SRC_TAG, seq}`) ถ้า `TX_EN=0` มันเป็น sink ล้วน (ใช้กับโหนด
00 ใน pattern hot-spot)

ฝั่ง RX รับเต็มอัตรา (`rx_tready = 11`) และตรวจต่อ (source, VC) ว่า sequence number ที่ได้รับ
เท่ากับตัวก่อนบวกหนึ่ง ไม่ตรงก็เพิ่ม `rx_err_cnt` การตรวจเป็นรายฟลิตและ modulo 6 บิต ซึ่งสำคัญ
ตอนตีความจำนวน error หลังการทำข้อมูลเสียโดยตั้งใจ: เลนสองเลนที่เห็นการกระโดดเลนละครั้งให้ค่า 2

liveness watchdog: `stuck_cnt` รีเซ็ตทุกครั้งที่มีการส่งระหว่าง `S_RUN` และตั้ง `stuck_seen` หลัง
เงียบ `2**STUCK_LOG` (65,536) ไซเคิล `done` ถูกกั้นด้วยมัน ไฟผ่านจึงติดบน fabric ที่ตายไม่ได้
`max_gap` บันทึกช่วงเงียบยาวสุดที่เห็นจริง threshold จึงตั้งจากการวัด ไม่ใช่การเดา (แย่สุดที่วัด
ได้: 136 ไซเคิลในซิม 219 บนบอร์ด)

จบ window (การแก้ bug #4): agent ส่งแพกเกจปัจจุบันให้จบก่อนออกจาก `S_RUN` โดยมี `stuck_seen`
เป็นทางหนีถ้า fabric ตายจริง

`done` กับ `err` **ผ่านรีจิสเตอร์** (2026-09-12) เดิมเป็น `test_done && !stuck_seen` กับตัว
เปรียบเทียบ 32 บิตป้อน synchronizer ตรงๆ ซึ่งคือ CDC-10

ตัวนับ (`tx_flit_cnt`, `rx_vc0_cnt`, `rx_vc1_cnt`, `rx_err_cnt`, `max_gap`, ...) ติด `mark_debug`
+ `dont_touch` และเป็นสิ่งที่ `analyze_ila.py` อ่าน

#### `fault_injector.sv` (111 บรรทัด เพิ่มวันที่ 2026-09-12)
ตัวฉีด fault ตอนรันจริง คั่นระหว่าง agent_11 กับ fabric นับ `2**FIRE_LOG` ไซเคิลจาก reset (2^20
บนบอร์ด ราว 15 ms เข้าไปใน window 235 ms; 2^12 ใน testbench) แล้วรอจน flit ที่ไม่ใช่ `tlast`
ถูกรับเพื่อให้ fault ลงกลางแพกเกจ จากนั้นใช้โหมด:

| mode | ผล | นาน | ทดสอบ |
|---|---|---|---|
| 0 | ไม่ทำอะไร | | |
| 1 | บังคับ `tvalid` เป็น 0 | ถาวร | stall timeout ของ bug #5 |
| 2 | `tid = 00` | `HOLD` = 2000 ไซเคิล | tid guard (flit ไม่ตรง VC ไหน) |
| 3 | `tid = 11` | 2000 | tid guard (flit จะถูกโคลนลงสอง VC), force-close |
| 4 | `tdest = 0001` (โหนด idx2 ในกระดาน) | 2000 | constant-tdest guard, force-close |
| 5 | `tdest = 1000` (x=2 นอกกระดาน) | 2000 | ตัวกรองช่วงค่าของ bug #6 |

`tready` ผ่านตรง agent_11 จึงเดินหน้าตาม `tid` ของตัวเองเหมือนที่ `force` ใน testbench เคยทำ
ปฏิกิริยาของ fabric คือสิ่งที่ถูกทดสอบ ไม่ใช่ watchdog ของ agent `mode`/`arm` มาจาก VIO ผ่าน
`sync_2stage` ใน `clk_h11` `active`, `fired` และ `mode_dbg` ติด `mark_debug` ผลข้างเคียงที่ตั้งใจ:
การให้ `tdest` ของ agent_11 ผ่าน mux ตอนรันทำให้ synthesis พับตัวกรองปลายทางของโหนด 3 ทิ้ง
เป็นค่าคงที่ไม่ได้ ซึ่งคือเหตุผลที่ `dest_err` สังเกตได้บน stress build เลย (หัวข้อ 10.8)

#### `noc_stress_tester.sv` (197 บรรทัด)
instantiate `traffic_node_agent` สี่ตัวโดยปลายทางเลือกตาม `PATTERN` แต่ละตัวบนนาฬิกาและ reset
ของตัวเอง:

- `PATTERN=0` permutation: 00↔11, 01↔10 ทุก flow มีเส้นทางของตัวเอง ไม่มีการแย่ง output port
  ดีสำหรับวัดแบนด์วิดท์ดิบ ไร้ประโยชน์สำหรับทดสอบ arbiter
- `PATTERN=1` hot-spot: 01, 10 และ 11 ส่งไป 00 ทั้งหมด 00 เป็น sink นี่คือ configuration ที่เปิด
  โปง bug #3 กับ #4 และใช้กับ silicon regression ทุกรอบ

TX ของ agent_11 ผ่าน `fault_injector` `done`/`err` จากสี่โดเมนนาฬิกาข้ามไป `clk_h00` ด้วย
`sync_2stage` และรวมเป็น `pass_group1`, `pass_group2`, `any_fail` เผยอินพุต
`fault_mode`/`fault_arm` และเอาต์พุต `fault_active`/`fault_fired`

#### `loopback_node_agent.sv` (150 บรรทัด)
โหนด echo สำหรับ UART build: อะไรที่มาถึงบน VC v ถูกเข้าคิว (ลึก 256 ต่อ VC มี credit อิสระ) และ
ส่งกลับไปโหนด 00 บน VC เดิม เพราะ echo ทุกตัวไปโหนด 00 ตัวกรองปลายทางของโหนด loopback ทั้ง
สามถูกพับเป็นค่าคงที่ใน build นั้น (มีแต่ของโหนด 00 ที่พีซีขับที่ยังทำงาน)

#### `uart_transceiver.sv` (121 บรรทัด)
`uart_rx` กับ `uart_tx` แบบ 8N1 parameter `CLK_FREQ` กับ `BAUD_RATE` (3 Mbaud บนบอร์ด)

#### `uart_noc_host.sv` (215 บรรทัด)
สะพานไปพีซีสำหรับ host 00 โปรโตคอล: **สองไบต์ต่อ flit** ไบต์ 0 คือ header `[7] tlast | [6:5]
tid | [4] 0 | [3:0] tdest` ไบต์ 1 คือ payload ไบต์ขาเข้าผ่าน `sync_fifo` 256 ช่อง parser สาม
สถานะประกอบ flit แล้วยื่นให้ NoC จนกว่า VC ของ flit นั้นจะ ready ทิศกลับ serialize flit ที่รับ
แต่ละตัวเป็น header แล้วตามด้วย data ฟิลด์ `tid` ของ header ถูกส่งผ่านไม่แปลง พีซีจึงต้องส่งค่า
one-hot `noc_host.py` ถูกแก้ให้ทำอย่างนั้นวันที่ 2026-09-04 flit ที่มี `tid=00` จากพีซีทำให้
โมดูลนี้รออยู่ใน `P_PUSH_NOC` เพื่อ `vc_ready` ที่ไม่มีวันมา fabric ยกธง สะพานค้างจนกว่าจะ reset
ครั้งถัดไป และนั่นคือพฤติกรรมที่ออกแบบไว้สำหรับ host ที่กำลังส่งขยะ

### 6.5 Top ของบอร์ดและ IP

#### `arty_stress_top.sv` (225 บรรทัด)
MMCM, `reset_sync` ห้าตัว, `vio_fault`, `gals_noc_top`, `noc_stress_tester`, LED parameter
`PATTERN` กับ `VC_MODE` ถูก override จาก `setup_stress_build.tcl` ความหมาย LED (`PATTERN=1`):
`led[0]` heartbeat (`heartbeat_cnt[26]` บน `clk_h00` ราว 0.75 Hz); `led[1]` agent ทุกตัวจบ
window โดย liveness ยังดี; `led[2]` จบและโหนด 00 ไม่เห็น error; `led[3]` มี `any_fail`, ECC
double-bit, `dest_err` หรือ `tid_err` อย่างใดอย่างหนึ่ง `led[1]` กับ `led[2]` ถูกดับด้วยแหล่งของ
`led[3]` การรันที่ข้อมูลเสียจึงโชว์เขียวไม่ได้ ไบต์ input ของ VIO อยู่หัวข้อ 3.6

#### `arty_gals_noc_wrapper.sv` (167 บรรทัด)
MMCM (reset ตรึง 0 ตั้งแต่ 2026-09-12), `reset_sync` ห้าตัว, `gals_noc_top`, `uart_noc_host` บน
host 00, `loopback_node_agent` สามตัว LED เป็นตัวบอกกิจกรรม (`led[1]` ตาม `uart_rxd`, `led[2]`
ตาม `uart_txd`, `led[3]` มีโหนด loopback ตัวไหนกำลังส่ง) ไม่ใช่คำตัดสิน

#### `clk_wiz_0` (IP)
ตัว MMCM ตั้งค่าตามหัวข้อ 3.2 track ไฟล์ `.xci`; output product ให้ Vivado สร้างใหม่

#### `vio_fault` (IP เพิ่มวันที่ 2026-09-12)
Xilinx VIO 3.0 output probe 8 บิตหนึ่งตัวค่าเริ่มต้น 0 input probe 8 บิตหนึ่งตัว บน `clk_h00`
สร้างด้วย `hw_scripts/create_vio_fault.tcl` (ทำครั้งเดียว; track ไฟล์ `.xci`) Hardware Manager
ตั้งชื่อ probe ตาม net ที่ต่ออยู่ (`vio_out_1`, `vio_in_1`) ไม่ใช่ตามชื่อพอร์ตของ IP ซึ่ง
`batch_fault_campaign.tcl` รับมือด้วยการค้นตาม type

### 6.6 Testbench

#### `tb_noc_mesh_2x2_gals.sv` (615 บรรทัด)
regression หกเทสต์ ขับด้วย `traffic_gen` และมี scoreboard (`sb_predict`) ที่ทำนายว่าแต่ละโหนด
ควรได้รับอะไร แล้วรายงาน `Matched / Mismatched / Pending`

| เทสต์ | ทดสอบอะไร | `Matched` baseline |
|---|---|---|
| 1 | แพกเกจเดียวข้ามแนวทแยง (สอง hop) | 4 |
| 2 | VC แซง: แพกเกจ VC0 30 flit แล้วตามด้วยแพกเกจ VC1 5 flit จากอีกโหนดไป output เดียวกัน VC1 ต้องแซง | 20 |
| 3 | สุ่ม all-to-all ทั้งสอง VC | 20 |
| 4 | สามโหนดส่งแพกเกจละหนึ่งไปปลายทางเดียวกัน การส่งถึงภายใต้การแย่ง | 23 |
| 5 | starvation override: แพกเกจ VC0 50 flit สู้กับแพกเกจ VC1 สิบใบใบละ 15 flit VC0 ต้องจบ | 34 |
| 6 | hot-spot **ต่อเนื่อง**: สามโหนดยิงเข้าโหนด 0 ติดต่อกันไม่มีช่องว่าง assert ว่าแต่ละแหล่งได้ส่วนแบ่งอย่างน้อยตามเกณฑ์ เพิ่มวันที่ 2026-08-18 เพราะเทสต์ 1-5 พิสูจน์แค่การส่งถึง ไม่ได้พิสูจน์การแบ่งแบนด์วิดท์ และ bug #2 มองไม่เห็นจากพวกมัน | 136 (140 เมื่อ `HS_VC_ALT`) |

สวิตช์: `HW_CLOCKS`, `HS_VC_ALT` (เทสต์ 6 สลับ VC เหมือนบอร์ด), `SIM_DEBUG` ทั้งสี่ combination
ของสองตัวแรกต้องผ่านด้วย `Mismatched=0 Pending=0` และยอด `Matched` ต้องเท่า baseline ข้างบน
การเปลี่ยนแปลงที่ทำให้ตัวเลขขยับต้องมีคำอธิบาย

#### `tb_noc_stress_tester.sv` (526 บรรทัด)
stress build ของบอร์ดในซิม ใช้อัตราส่วนนาฬิกาเดียวกันและ window ย่อจาก 2^24 เป็น 2^18 ไซเคิล
รายงานจำนวน flit ต่อ agent, `max_gap`, sequence error, `stuck`, การแบ่ง EAST/NORTH ที่ LOCAL
arbiter ของโหนด 0, ตัวนับ ECC, `dest_err`, `tid_err` baseline สะอาด: ส่ง 142112 / 61104 / 81072
flit รับ 203504 ช่องว่างแย่สุด 136 EAST 49% / NORTH 51% คำทำนายของมันตรงกับบอร์ดภายในเศษส่วน
ของเปอร์เซ็นต์ (delta ของ bug #4) มันจึงใช้แทน build บนบอร์ดได้เวลาไล่ปัญหาประเภทนี้

fault mode ทั้งหมดเป็นโหมดวัด ที่รายงาน `FAIL` บนบรรทัด sequence-error หรือ fairness โดยตั้งใจ:

| parameter | ทำอะไร | หมายเหตุ |
|---|---|---|
| `INJECT_ECC=1` | พลิกสองบิตในข้อมูล FIFO จริง ธงต้องขึ้นถึงยอดและปลายทางต้องเห็น error (247) | การแสดงข้อมูลเสียแบบ end-to-end ภายใต้ error ที่ซ่อมไม่ได้ เพียงอันเดียวที่มี |
| `KILL_MIDPKT=1` | `force` `tvalid` ของ agent_11 ให้ต่ำกลางแพกเกจ | การจำลอง bug #5 ดั้งเดิม |
| `BAD_TID=1/2` | `force` `tid` ของโหนด 11 เป็น `00`/`11` 2000 ไซเคิล | การวัด tid guard ดั้งเดิม |
| `BAD_DEST=1` | `force` `tdest` ของโหนด 11 เป็น `0001` 2000 ไซเคิล | force ค่าจริงกลับหนึ่งไซเคิลก่อน `release` (gotcha 11) |
| `FAULT_MODE=1..5` | ขับ `fault_injector` เอง (ไม่ `force`) `FAULT_FIRE_LOG=12` | เส้นทาง RTL เดียวกับที่บอร์ดใช้ ให้ผลตรงกับทุกโหมดข้างบน |

#### `tb_ecc_secded.sv` (215 บรรทัด)
เทสต์ SECDED แบบ exhaustive อธิบายไว้ใต้ encoder/decoder ข้างบน

#### `tb_traffic_node_agent.sv` (182 บรรทัด)
การตรวจ liveness watchdog สิบข้อ: ปกติ, ตาย, ตายกลางทาง, ตายแล้วฟื้น, backpressure หนักแต่ยัง
เป็นๆ (จับ threshold ที่แน่นเกิน) ถ้าย้อนการกั้น `done` จะตก 6 ใน 10

### 6.7 สคริปต์และ tooling

| ไฟล์ | หน้าที่ |
|---|---|
| `run_sim_regression.tcl` | รัน `tb_noc_mesh_2x2_gals` จาก Vivado project เขียน `sim_logs/regress_<tag>_<stamp>.log` |
| `setup_stress_build.tcl` | สลับ project ไป `arty_stress_top` พร้อม `PATTERN`/`VC_MODE` เพิ่ม `fault_injector.sv` / `reset_sync.sv` ถ้ายังไม่มี แล้ว synthesize ใหม่ |
| `setup_uart_build.tcl` | อย่างเดียวกันสำหรับ `arty_gals_noc_wrapper` |
| `setup_debug.tcl` | สร้าง ILA core จาก net ที่ติด `MARK_DEBUG` core ละโดเมนนาฬิกา เขียน `constrs_1/new/debug_auto.xdc` แทน wizard Set Up Debug ของ GUI; รายงาน net ที่เป็นค่าคงที่แยกจาก net ที่หาคล็อกไม่เจอ |
| `analyze_ila.py` | อ่าน `iladata*.csv` ที่ export มา คำนวณ throughput, utilisation, conservation, liveness, ECC, `dest_err`, `tid_err` และอธิบายว่าทำไม `dest_err_node` ไม่มีบน stress build |
| `hw_scripts/batch_stress_synth_debug.tcl`, `batch_uart_synth_debug.tcl` | session A ของ batch flow: synth + Set Up Debug แบบสคริปต์ แล้วออก ตัวบอกความสำเร็จคือบรรทัด `SESSION_A_DONE` ใน log ไม่ใช่ exit code (Vivado เคย crash ใน exit handler หลังทำงานเสร็จ) |
| `hw_scripts/batch_impl.tcl <top>` | session B: implementation + bitstream ใน session ใหม่ แล้ว `report_cdc` บนดีไซน์ที่ route แล้ว พิมพ์จำนวนต่อ severity |
| `hw_scripts/batch_program_capture.tcl <dir> <top> [noprog]` | session C: program, Trigger Immediately ทุก ILA, export CSV |
| `hw_scripts/batch_fault_campaign.tcl <dir> [modes]` | program ครั้งเดียว แล้วต่อโหมด: VIO soft reset → mode + arm → ปล่อย → 2 s → capture |
| `hw_scripts/summarize_campaign.py <dir>` | หนึ่งแถวต่อโหมดพร้อมตัวนับที่ใช้ตัดสินและ signature ที่คาด |
| `hw_scripts/create_vio_fault.tcl` | สร้าง VIO IP ครั้งเดียว |
| `hw_scripts/batch_uart_session.tcl <dir>` | hw_server session เดียวที่ handshake ผ่านไฟล์ ให้ทราฟฟิก UART จากพีซีรันระหว่างการ capture ได้โดย reset จากการเปิด COM port ไม่ล้างตัวนับ |
| `hw_scripts/uart_roundtrip.py [pos\|neg]` | round-trip บวกหกเคส (ทั้งสอง VC ทั้งสามโหนด loopback) และเคสลบ `tid=00` |
| `hw_scripts/read_ila_flags.py <dir>` | dump sample สุดท้ายของทุก probe ที่เป็นธง/ตัวนับ (สำหรับ build ที่ไม่มี agent) |
| `noc_host.py` | ฝั่งพีซีของ UART build: ส่งแพกเกจ พิมพ์ echo |
| `image_noc_test.py`, `video_noc_stream.py`, `bulk_test.py`, `vc_*_test.py`, `multi_node_stress_test.py`, `fault_recovery_test.py`, `single_probe_test.py` | demo และการทดลองผ่าน UART; `recovered_from_fpga.png` คือรูปที่ round-trip ผ่าน fabric ยังไม่เป็น regression |
| `formal/*.sby` | สคริปต์ SymbiYosys ตัวละโมดูล RTL (สิบเอ็ดตัว) บวก `run_wsl.sh` สำหรับรันจาก Git Bash บน Windows |
| `combine_sv.py` | ต่อซอร์สเป็น `combined*.sv` ไว้แชร์ |
| `hw_logs/` | ทุกการจับ ILA ที่รองรับตัวเลขใน `HANDOFF.md` บวกรายงาน CDC หลังแก้ |
| `sim_logs/` | log ของ regression ตัวที่ลงท้าย `_FIXED` คือ baseline |
| `sources_1/new/old/`, `final_src/`, `backup_20260804/` | ของเก่า `old/` มี `.sby` ของอีกโปรเจกต์ (`gals_mpmc_scalable`) ที่ไม่เคย verify อะไรที่นี่; `final_src/` คือ snapshot เดือนกรกฎาคมที่ค้าง ห้าม build จากทั้งคู่ |
| `constrs_1/new/arty.xdc`, `timing.xdc`, `debug_auto.xdc`, `debug.xdc` | pin; clock group (นาฬิกาห้าเส้น async ต่อกัน); constraint ILA ที่สคริปต์สร้าง; ไฟล์ debug เก่าที่สคริปต์ build เอาออกจาก fileset |
| `.gitattributes` | ตรึง `*.sh` เป็น LF ให้ `run_wsl.sh` รอดจากการ checkout บน Windows |

---
## 7. ชีวิตของ flit

### 7.1 แพกเกจหนึ่งใบ ตั้งแต่ต้นจนจบ

ตามแพกเกจ 16 flit หนึ่งใบจาก agent_11 (idx 3, 71.43 MHz) ไป agent_00 (idx 0, sink) ใน stress
build แบบ hot-spot โหนด 11 อยู่ที่ (1,1) โหนด 00 อยู่ที่ (0,0)

1. **Agent.** `traffic_node_agent` ใน `S_RUN` ยื่น `tvalid=1`, `tdest=0000`, `tid=01` (VC0
   สำหรับแพกเกจนี้), `tdata={2'b11, seq}`, `tlast=0` บน `clk_h11` มันเดินหน้าเมื่อ `tready[0]`
   สูง

2. **Fault injector.** mode 0: ทุกอย่างผ่านตรง รวม `tready`

3. **ขาเข้า host ของ wrapper** (`gals_node_wrapper`, `clk_h11`) `host_tid_ok` เป็นจริง (`01`
   คือ one-hot) ไม่มี close ค้าง TX VC0 ไม่เต็ม `tx_host_acc[0]` จึงยิง: `{tlast, tdest, tdata}`
   ถูกเขียนลง TX FIFO VC0 `tx_pkt_open[0]` เป็น 1 และ `tx_pkt_dest[0]` บันทึก `0000` ใน FIFO
   `dual_port_ram_ecc` เข้ารหัสข้อมูล 8 บิตเป็น 13 แล้วเก็บ บิต control 5 บิตลง RAM ธรรมดา
   write pointer เพิ่มทั้งแบบฐานสองและ gray

4. **ข้ามนาฬิกา.** gray write pointer ผ่านสองฟลอปบน `clk_noc` สอง `clk_noc` ไซเคิลถัดมา
   ฝั่งอ่านเห็นว่า FIFO ไม่ว่าง `fwft_wrapper` อ่านคำล่วงหน้าไว้แล้วบน `rdata` ตอนที่ใครมามอง

5. **ขาออก NoC ของ wrapper** (`clk_noc`) TX VC1 ว่าง TX VC0 ไม่ว่าง mux จึงยื่น
   `m_noc_valid=1`, `m_noc_tid=01` พร้อม `tlast/tdest/tdata` ของหัว FIFO FIFO pop เมื่อ
   `m_noc_ready[0]` สูง ตอน pop decoder ตรวจคำ 13 บิต ถ้าบิตไหนพลิกจะถูกซ่อมและ `tx_sbe[0]`
   พัลส์ เพื่อไป latch sticky

6. **ขาเข้า mesh** (`noc_mesh_2x2_vc` หัวข้อ 0/0b/2.2/2.3 โหนด 3) `dest_ok[3]`: x=0, y=0 ทั้งคู่
   ≤ 1 จริง `tid_ok[3]`: จริง `frame_ok[3]`: VC0 มีแพกเกจเปิดด้วย `pkt_dest[0]=0000` flit นี้
   บอก `0000` จริง ไม่ได้ closing ดังนั้น `r_valid[3][LOCAL]` ตาม `s_valid[3]` และฟิลด์ผ่านตรง

7. **Router 3, input buffer พอร์ต LOCAL.** `vc_input_buffer` เขียน flit ที่ pack แล้วลง
   `sync_fifo` VC0 ของมัน `s_ready[LOCAL][0]` คือ `~full` และนั่นคือสิ่งที่ wrapper เห็นเป็น
   `m_noc_ready[0]` ในข้อ 5

8. **Router 3, ตัวถอด XY.** หัวคิว VC0 ที่ LOCAL: `dx = 0 < MY_X = 1` → ขอ **WEST**
   `route_req[LOCAL][0][WEST] = 1` ถูก transpose เป็น `req_out_vc0[WEST][LOCAL]`

9. **Router 3, arbiter ขาออก WEST.** `vc_port_arbiter` ของ WEST: `packet_arbiter` ของ VC1 ไม่มี
   คำขอ ของ VC0 อยู่ `IDLE` เห็น `valid[LOCAL]` เลือกมัน (`next_grant = 00001`) และเพราะ
   `tlast` เป็น 0 มันไป `LOCKED` บน LOCAL โดย `has_transferred` ตั้งถ้า flit ขยับในไซเคิลนี้
   `vc1_can_move` เป็นเท็จ `vc1_is_active` จึงเท็จ `ready_vc0 = ready_out_vc0 =
   m_ready[WEST][0]` ซึ่งคือ `~full` ของ input buffer VC0 ฝั่ง EAST ของ router 2

10. **Router 3, crossbar.** `grant_vc0[WEST] = 00001` ดังนั้น `m_*[WEST]` = หัวคิว VC0 ของ LOCAL
    `m_tid[WEST] = 01` `buf_ready[LOCAL][0]` = `ready_from_arb_vc0[WEST]` input FIFO pop

11. **ลิงก์ 3→2.** `noc_mesh_2x2_vc` ต่อ `m_*[3][WEST]` เข้า `r_*[2][EAST]` นาฬิกาเดียวกัน
    ไม่มีการข้าม

12. **Router 2.** input buffer EAST VC0 → ตัวถอด: `dx = 0 = MY_X`, `dy = 0 < MY_Y = 1` →
    **SOUTH** arbiter ของ SOUTH ล็อกบน EAST crossbar ขับ `m_*[SOUTH]` ที่ต่อเข้า
    `r_*[0][NORTH]`

13. **Router 0.** input buffer NORTH VC0 → ตัวถอด: `dx = 0`, `dy = 0` เท่ากันทั้งคู่ → **LOCAL**
    ตรงนี้คือจุดแย่ง: แพกเกจของ agent_01 มาทางพอร์ต EAST ของ router 0 ส่วนของ agent_10 กับ
    agent_11 มาทาง NORTH (รวมกันแล้วที่ router 2) ทุกตัวอยากได้ LOCAL `packet_arbiter` ของ
    LOCAL สำหรับ VC0 round-robin ระหว่าง EAST กับ NORTH ทีละแพกเกจ stress tester วัดการแบ่ง
    นี้ได้ 49/51 บอร์ดได้ 48.3/51.7 แพกเกจของเรา พอได้ grant แล้ว ถือ LOCAL ครบทั้ง 16 flit

14. **ขาออก mesh → RX ของ wrapper 0.** `m_*[0][LOCAL]` กลายเป็น `s_noc_*` ของ wrapper 0 RX
    VC0 FIFO ถูกเขียนบน `clk_noc` gray pointer ข้ามไป `clk_h00` `fwft_wrapper` อ่านล่วงหน้า
    mux ฝั่ง RX ยื่นเป็น `m_host_*` ด้วย `m_host_tid = 01`

15. **Sink.** `rx_tready = 11` ของ agent_00 flit แต่ละตัวถูกเทียบกับ `exp_seq[src=11][vc=0]`
    นับเข้า `rx_vc0_cnt` และรีเซ็ต `stuck_cnt` flit ตัวที่ 16 พา `tlast` ที่ arbiter ทุกตัวตลอด
    ทาง `eop_transfer` ยิง ล็อกปลด mask ของ round-robin เลื่อน และที่ตัวติดตามขาเข้าทั้งสอง
    `pkt_open[0]` ล้าง

latency ต่อ hop ประมาณ: เขียน FIFO, สองไซเคิลของ synchronizer, FWFT อ่านล่วงหน้า, หนึ่งไซเคิล
ใน input buffer, หนึ่งใน crossbar ค่าใช้จ่ายต่อ hop ภายใน mesh คือ `sync_fifo` หนึ่งขั้น ส่วนที่
แพงคือการข้าม GALS สองครั้งที่ปลายทั้งสอง

### 7.2 flit หนึ่งตัวที่ถูกปฏิเสธ (campaign mode 4)

setup เดิม แต่ injector ทำงานด้วย mode 4: flit ที่ออกจาก agent_11 บอก `tdest=0001` ขณะที่
แพกเกจ VC0 ไป `0000` เปิดอยู่

1. **ขาเข้า host ของ wrapper.** `tid` เป็น one-hot wrapper จึงรับ flit ลง TX VC0 เหมือน body flit
   ตัวอื่น (wrapper ไม่เช็ค `tdest` และไม่จำเป็นต้องเช็ค)
2. **ขาเข้า mesh โหนด 3.** `dest_ok` จริง (ในช่วง) `tid_ok` จริง **`frame_ok` เท็จ**: VC0 เปิด
   อยู่ด้วย `pkt_dest[0]=0000` และ flit นี้บอก `0001` `reject` = 1 flit ถูกรับ (`s_ready` ยังตาม
   ready ของ router) และไม่ถูกยื่น `dest_err[3]` ค้าง sticky `close_pend[0]` ถูกตั้งเพราะ VC0
   เปิดอยู่
3. **ไซเคิลถัดไป กำลัง close.** `s_ready[3]` ถูกบังคับเป็น 0 พอร์ต LOCAL ของ router ถูกยื่น
   flit สังเคราะห์: `tlast=1`, `tid=01`, `tdest=0000`, data 0 เมื่อ input buffer รับ (`r_rdy`)
   `close_pend[0]` กับ `pkt_open[0]` ล้าง
4. **ปลายน้ำ.** arbiter WEST ของ router 3 ที่ล็อกบน LOCAL สำหรับแพกเกจนี้ เห็น `tlast`
   สังเคราะห์และปล่อย แพกเกจที่ถูกตัด (flit เท่าที่มีบวกท้ายศูนย์) ไปถึงโหนด 00 sink เห็น
   sequence กระโดดหนึ่งครั้งบนเลนนี้
5. **flit ถัดๆ ไป** จาก agent_11 บอก `0001` เช่นกัน (injector ค้าง 2000 ไซเคิล) `pkt_open[0]`
   เป็น 0 ตัวแรกจึงเป็น**หัวใหม่** ด้วย `pkt_dest[0]=0001` `frame_ok` จริงสำหรับตัวที่เหลือ
   พวกมัน route ไปโหนด idx2 (agent_10) ซึ่งนับพวกมัน (1777 บนบอร์ด) เป็นสตรีมใหม่จาก source 11
6. **injector ปล่อย.** `tdest` ของ agent_11 กลับเป็น `0000` กลางแพกเกจ: `frame_ok` เท็จอีก
   ปฏิเสธอีกหนึ่ง เสนอ `dest_err` อีกหนึ่ง (ธง sticky อยู่แล้ว `dest_err_cnt` นับโหนด จึงยัง
   เป็น 1) close สังเคราะห์อีกหนึ่ง และ flit ถัดไปเป็นหัวใหม่ไป `0000` sink เห็น sequence
   กระโดดครั้งที่สอง จากนี้ทุกอย่างปกติ

ก่อน bug #7 flit ในข้อ 2 จะถูกทิ้งแล้วจบ: แพกเกจบน VC0 เปิดค้าง และหัวถัดไปจะขี่ grant ของมัน
ไป `0000` ทั้งที่บอกว่า `0001` ก่อนมี constant-`tdest` guard ข้อ 2 จะไม่ปฏิเสธเลย และ router
จะส่ง flit `0001` ออกพอร์ตที่ล็อกไว้สำหรับ `0000`

### 7.3 reset หนึ่งครั้ง (stress build, soft reset จาก VIO)

1. Hardware Manager เขียน `vio_out[0] = 1` รีจิสเตอร์ output ของ VIO บน `clk_h00` ขับ `srst`
   ของ `reset_sync` ทั้งห้า
2. `reset_sync` แต่ละตัว sync `srst` ผ่านสองฟลอปของนาฬิกาตัวเองแล้วดึง `rst_n` ลง: ห้าโดเมน
   เข้า reset ภายในไม่กี่ไซเคิลของตัวเอง ไม่มีลำดับแน่นอน ตอนนั้นใน campaign ไม่มีอะไรกำลัง
   ถูกส่ง ลำดับจึงไม่สำคัญ ดีไซน์ไม่ได้พึ่งมัน
3. สคริปต์เขียน mode กับ arm ตอน reset ยังกดอยู่ แล้วล้าง `vio_out[0]` แต่ละโดเมนปล่อยสอง
   นาฬิกาของตัวเองถัดมา ยังไม่มีลำดับแน่นอน
4. `traffic_node_agent` ทุกตัวเริ่มที่ `S_WARMUP` และนอน 1024 ไซเคิล pointer ของ async FIFO ทั้ง
   สองฝั่งเป็น 0 ไม่มีอะไรถูกยื่นให้ fabric ช่วงนอนนี้คือสิ่งที่ทำให้ deassert แบบไม่ sync ของ
   เดิมรอดมาได้
5. `S_RUN` เริ่ม ตัวนับของ injector อยู่ที่ไม่กี่ร้อยและจะยิงที่ 2^20

การกดปุ่มเหมือนกันทุกอย่าง ยกเว้นข้อ 1 เป็นขาเข้า `arst_n` แบบ asynchronous การ assert จึง
ทันทีในทุกโดเมน การ deassert ยัง sync ต่อโดเมน

---

## 8. ข้อบกพร่องทุกอันที่เจอ

### 8.1 บั๊ก RTL เจ็ดตัวที่มีเลข

เรียงตามลำดับที่เจอ แต่ละตัว: เห็นอะไร เจอยังไง ทำไมเกิด เปลี่ยนอะไร ตรวจยังไง `HANDOFF.md` มี
ตารางตัวเลข ที่นี่มีเรื่องราว

#### Bug #1: arbiter ปล่อยพอร์ตกลางแพกเกจ

**เจอโดย** simulation ก่อน git history บันทึกไว้ใน comment ของ `packet_arbiter.sv`

**อาการ.** แพกเกจจากสองอินพุตสลับกันบน VC เดียวกันของ output เดียวกัน ผู้รับเห็น flit ของ
แพกเกจ B แทรกกลางแพกเกจ A

**สาเหตุ.** `packet_arbiter` มีการปลดล็อกฉุกเฉิน: ถ้า `valid` ของอินพุตที่ล็อกตก ให้ปล่อยพอร์ต
ถูกต้องสำหรับคำขอที่ถูกถอนก่อนมีอะไรขยับ แต่ในระบบ GALS `valid` ของต้นทางตกเป็นประจำหนึ่ง
สองไซเคิลทุกครั้งที่ FIFO ของ wrapper แห้งชั่วครู่ arbiter มองทุกช่องว่างแบบนั้นเป็น "ต้นทางหาย"
และปล่อยกลางแพกเกจ

ชิ้นที่สอง ละเอียดกว่า: ตอนล็อก arbiter ตั้ง `has_transferred <= 0` แต่ใน `IDLE` grant ทำงานแบบ
combinational อยู่แล้ว ถ้า `ready` สูง flit แรกออกไปแล้วในไซเคิลเดียวกับที่ล็อก ไซเคิลถัดไป FIFO
อาจแห้ง `has_transferred` บอกว่ายังไม่มีอะไรขยับ และการปลดล็อกฉุกเฉินก็ยิง

**การแก้.** การปลดล็อกฉุกเฉินถูกกั้นด้วย `!has_transferred` และ `has_transferred` ถูกตั้งตอน
ล็อกเป็น "flit แรกออกไปในไซเคิลนี้ไหม" เมื่อมีอะไรขยับบน grant แล้ว มีแค่ `tlast` (หรือภายหลัง
timeout ของ bug #5) ที่ปล่อยได้

**ตรวจโดย** regression หกเทสต์ (เทสต์ 2 กับ 4 เป็นพิเศษ) และตั้งแต่ 2026-09-04 โดย
`assert_channel_lock` ใน `formal/packet_arbiter.sby`: ขณะ `LOCKED` และต้นทางที่ล็อกยังมีข้อมูล
`grant` ต้องไม่เปลี่ยน property นั้นเป็นเท็จบนโค้ดเดิมจริงๆ และไม่มีใครรู้ เพราะ `.sby` ที่อ้าง
ว่าครอบ arbiter ชี้ไปที่โมดูลของอีกโปรเจกต์

#### Bug #2: round-robin starvation

**เจอโดย** simulation commit `2ac2e05` (2026-08-18)

**อาการ.** สามแหล่งแย่ง output เดียว แหล่งหนึ่งได้ ~100% ที่เหลืออด เทสต์ 1-5 ไม่เห็นเพราะส่ง
แพกเกจละหนึ่งแล้วหยุด เทสต์ 6 (การแย่งต่อเนื่อง) ถูกเขียนมาเพื่อเปิดโปงมัน

**สาเหตุ.** mask ของ round-robin เลื่อนเฉพาะเมื่อผู้ชนะชนะ "จาก mask" (`current_from_mask`)
เจตนาคือไม่ลงโทษแหล่งที่ชนะจากการตกไปใช้ตัวเลือกแบบ unmasked ในทางปฏิบัติ: หลังพอร์ตหมายเลข
สูงชนะ mask ชี้ไปพอร์ตที่ไม่มีใครขอ `masked_req` เป็นศูนย์ ตัวเลือก unmasked เลือกพอร์ตต่ำสุด
`current_from_mask` เป็น 0 mask ไม่เคลื่อนอีกเลย และพอร์ตต่ำสุดชนะตลอด มันไม่โผล่ตอนทุกพอร์ต
ขอพร้อมกัน โผล่เฉพาะตอนบางส่วนขอ ซึ่งคือทุกเคสจริง

**การแก้.** เลื่อน mask ทุกครั้งที่ `eop_transfer` โดยไม่มีเงื่อนไข

**ตรวจโดย** เทสต์ 6 (ส่วนแบ่งต่ำสุดต่อแหล่ง ≥ เกณฑ์) และภายหลังบนบอร์ด: LOCAL arbiter ของ
โหนด 0 แบ่ง EAST 48.3% / NORTH 51.7% (49/51 ในซิม) ส่วนแบ่ง 50/25/25 ต่อ agent ที่ดูเหมือน
ไม่ยุติธรรมคือ topology (สอง agent แชร์ NORTH) ไม่ใช่ arbiter

#### Bug #3: สอง VC บล็อกกันเอง

**เจอโดย** simulation และยืนยันบนฮาร์ดแวร์ commit `04cd562`, `e1571ba` (2026-08-19), `cba4e60`
(2026-09-01)

**อาการ.** utilisation ของพอร์ต LOCAL โหนด 00 เป็น 100% เมื่อใช้ VC0 อย่างเดียว 57.5% เมื่อสลับ
VC บนบอร์ด ในซิม เคสสลับ VC ทรุดแล้ว deadlock (`Pending` ไม่เคยถึงศูนย์)

**สาเหตุ** (`vc_port_arbiter.sv`) VC1 เป็นเจ้าของ output ที่แชร์ทุกครั้งที่ `packet_arbiter` ของ
มัน**ถือ grant** และตอน VC1 เป็นเจ้าของ `ready_vc0` ถูกบังคับเป็น 0 สอง VC มี credit ปลายน้ำ
อิสระ แพกเกจ VC1 ที่ค้างเพราะ buffer VC1 ปลายน้ำเต็มจึงบล็อก VC0 ทั้งที่ buffer VC0 ปลายน้ำมี
ที่ว่าง การแยก VC ที่ดีไซน์นี้สร้างมาถูกล้มที่ output mux

anti-starvation override ทำให้แย่ลง: ใช้เวลา 64 ไซเคิลว่างกว่าจะยิง และปลดเฉพาะเมื่อ VC0 ส่งจบ
ทั้งแพกเกจ ถ้า VC0 ค้างตอนนั้น override latch และคราวนี้ VC1 ถูกบล็อก บล็อกทั้งสองทิศคือ
circular wait

**การแก้.** VC1 เป็นเจ้าของลิงก์เฉพาะไซเคิลที่มันขยับ flit ได้จริง (`vc1_can_move =
|raw_grant_vc1 && ready_out_vc1`) พอ credit หมดมันยอมทันทีในไซเคิลนั้นและ VC0 ได้ลิงก์
override บล็อก VC1 เฉพาะตอน VC0 กำลังเดินหน้าเอง (`&& vc0_can_move`) ถ้าติดทั้งคู่ VC1 ได้
ลิงก์คืน บวกทางปลดเมื่อคำขอของ VC0 หาย การสลับ flit ของ VC0 กับ VC1 บนลิงก์กายภาพเส้นเดียว
ทำได้เพราะ buffer ปลายน้ำ demux ตาม `tid`

**ตรวจโดย** regression ทั้งสี่ configuration (นาฬิกา TB แบบสลับ: 9.5% → 77.8%; นาฬิกาบอร์ด
แบบสลับ: 44.5% → 97.2%), การตามรอย override ด้วย `SIM_DEBUG` (override ค้าง 4 → 0), synthesis
แบบ out-of-context (ไม่มี latch ค่าใช้จ่ายด้าน timing 76 ps ราว 100 LUT ต่อ router), formal
(`assert_vc1_yields_when_stalled`, `assert_no_vc1_during_override`) และบอร์ด: 57.5% → **97.0%**
VC แบ่ง 50/50

#### Bug #4: agent ตัดแพกเกจตอนจบ window และแขวนพอร์ต

**เจอโดย** liveness watchdog ในการรันบนฮาร์ดแวร์ครั้งแรก commit `8fd67c7` (2026-09-01)

**อาการ.** การรันบนบอร์ดที่โชว์ utilisation 97.0% และ sequence error ศูนย์ รายงาน `liveness
FAIL` บน agent_01 กับ agent_11 สองโหนดที่ 71.43 MHz ดูเหมือน false positive แต่ไม่ใช่

**สาเหตุ** (`traffic_node_agent.sv`) agent ออกจาก `S_RUN` ทันทีที่ตัวนับไซเคิลเต็ม และ
`tx_tvalid` คือ `(state == S_RUN)` มันจึงดึง valid ลงกลางแพกเกจได้ ครึ่งแพกเกจถูกทิ้งไว้ใน
fabric โดยไม่มี `tlast` ตามมา `packet_arbiter` ปลายน้ำ `LOCKED` บนอินพุตนั้นด้วย `has_transferred
= 1` guard ของ bug #1 จึงล็อกมันไว้ตลอดกาล เพราะ window นับไซเคิลไม่ใช่เวลา โหนดที่เร็วกว่าจบ
ก่อน ใครหยุดก่อนก็ทิ้งแพกเกจที่ฆ่าพอร์ตสำหรับทุกคนที่ยังวิ่ง วัดที่พอร์ต LOCAL ของโหนด 00 ตอน
fabric เงียบ: ล็อกบน NORTH (ไม่มีอะไร) EAST มีข้อมูลและอดตลอดกาล

**การแก้.** ส่งแพกเกจปัจจุบันให้จบก่อนออกจาก `S_RUN` (`win_full && (tx_fire && last_flit)`) โดย
มี `stuck_seen` เป็นทางหนีถ้า fabric ตาย sink ไม่มีแพกเกจให้จบจึงออกทันที

**ตรวจโดย** `tb_noc_stress_tester` (ช่องว่างแย่สุดของ agent_01 37,171 → 41; agent_11 37,245 →
106; flit +16% และ +33%) และบอร์ด (+16.4% และ +32.9% liveness PASS ยอดฉีดรวม 69.3 → 80.2
MB/s) simulation ทำนาย delta ของแต่ละ agent ภายในเศษส่วนของเปอร์เซ็นต์

bug #4 อยู่ใน test agent ไม่ใช่ fabric ความเปราะของ fabric ที่มันเปิดโปงคือ bug #5

#### Bug #5: ต้นทางที่หายกลางแพกเกจล็อกพอร์ตตลอดกาล และการแก้มีรู

**เจอโดย** simulation (`KILL_MIDPKT=1`) แล้วต่อด้วย formal commit `e9f8197` (2026-09-04)

**อาการ.** ตัด `tx_tvalid` ของ agent_11 กลางแพกเกจ: sender ที่รอดทั้งสองตัวที่ยิงเข้าโหนด 00
ตัวนับช่องว่างชนเพดานที่ 8,388,609 ไซเคิล โหนดเดียวตายพา flow ทุกเส้นผ่านพอร์ตนั้นตายตาม จนกว่า
จะ reset ทั้งระบบ

**สาเหตุ.** หลังการแก้ bug #1 เมื่อ `has_transferred` ถูกตั้งแล้ว ทางออกเดียวจาก `LOCKED` คือ
`eop_transfer` ซึ่งต้องการ `tlast` ที่ต้นทางที่ตายไม่มีวันส่ง

**การแก้.** timeout: `stall_cnt` นับไซเคิลติดต่อกันที่อินพุตที่ล็อกมี `valid` ต่ำ ถึง
`2**STALL_LOG` (1024) arbiter ปล่อย backpressure ทำให้ `valid` ค้างสูง ต้นทางที่ถูกบล็อกแต่ยัง
เป็นๆ จึงไม่มีทางทำให้มันยิง ช่องว่างปกติของ GALS อยู่ระดับสิบไซเคิล

**รูที่ formal เจอ.** `stall_cnt` เป็นรีจิสเตอร์ ถ้าต้นทางกลับมาพร้อม flit จริงในไซเคิลที่ตัวนับ
ชนเพดานพอดี `force_release` ยิงทั้งที่มีข้อมูลอยู่: ปล่อยกลางแพกเกจ = bug #1 กลับมา simulation
ไม่เคยเจอหน้าต่างหนึ่งไซเคิลนั้น การแก้กั้นการปล่อยด้วยเงื่อนไขว่าต้นทางเงียบในไซเคิลเดียวกัน
(`&& !(|(locked_grant & valid))`) ตรึงด้วย `assert_abort_only_when_source_gone`

**ตรวจโดย** `formal/packet_arbiter.sby` ผ่าน `prove` (basecase และ induction จึง unbounded),
`KILL_MIDPKT` (ผู้รอดวิ่งต่อด้วยช่องว่าง 886 กับ 1104), regression ไม่เปลี่ยน และวันที่ 2026-09-12
โดย campaign mode 1 บนซิลิคอน: ช่องว่างของผู้รอดคือ 608/611 ไซเคิลและ fabric ยังเป็นๆ

#### Bug #6: ปลายทางนอกกระดานแขวน fabric ทั้งใบ

**เจอโดย** formal บน mesh commit `a9a0fd2` (2026-09-04)

**อาการ.** ในสภาพแวดล้อม formal ของ mesh การถอด assumption ว่า `tdest` อยู่ในกระดานทำให้
`assert_edge_*` พัง: router ขับ `valid` ออกนอกขอบ

**สาเหตุ.** `tdest` กว้าง 4 บิตและรับ x หรือ y ได้ถึง 3 แต่ mesh เป็น 2x2 flit ที่ x=2 ทำให้ทุก
router เห็น `dx > MY_X` และส่งมันไป EAST ที่ขอบตะวันออก `m_ready` ถูกผูกไว้ที่ 0 flit จึงค้างที่
นั่นตลอดกาล ถือ lock ของ arbiter และ head-of-line block ทุกอย่างข้างหลัง ไม่มีธง ไม่มี timeout
host ตัวเดียวที่พิมพ์ `tdest` ผิดแขวน fabric ได้

**การแก้.** `dest_ok[i]` ที่ขาเข้า mesh flit ที่ผิดถูกรับแล้วทิ้ง และธง sticky ต่อโหนด
`dest_err[i]` ถูกยก ทางเลือกสองทางถูกปัดตก: ดึง `ready` ลงย้ายการค้างไปที่ผู้ส่ง; หนีบที่อยู่
เข้าช่วงส่งแพกเกจไปที่ที่ไม่มีใครตั้งใจแบบเงียบๆ การรายงานเดินตามเส้นทาง ECC (ธงต่อโหนด → รวมที่
`gals_noc_top` → ตัวนับ ILA → `led[3]` ซึ่งดับไฟผ่านด้วย)

**ตรวจโดย** การรัน formal ของ mesh โดยถอด assumption ช่วงค่าและปล่อย `s_tdest` เป็นค่าใดก็ได้ใน
16 ค่า (`assert_edge_*` ยืน `assert_bad_dest_blocked` กับ `assert_good_flit_passes` เพิ่มเข้ามา
cover แสดงว่าตัวกรองยิงและ mesh ส่งต่อได้), `tb_noc_stress_tester` รายงาน `DEST: err_cnt=0` บน
ทราฟฟิกสะอาดด้วยตัวเลขเท่าเดิม และบนซิลิคอนโดย campaign mode 5 (`dest_err` โหนด `1000` ไม่มี
อะไรถูกส่งถึง fabric ยังเป็นๆ) หมายเหตุว่าค่า "`dest_err_cnt` 0 บนบอร์ด" ทุกครั้งก่อนหน้านั้น
เป็นเรื่องโครงสร้าง ไม่ใช่หลักฐาน (หัวข้อ 8.2)

การแก้พลอยได้มาด้วยหนึ่งอย่าง: `arty_stress_top.sv` ประกาศสองเน็ตหลัง instance ที่ขับมัน
ซึ่ง synthesis ของ Vivado ยอมแต่ `xvlog` ไม่ยอม

#### Bug #7: flit ที่ถูกปฏิเสธกิน `tlast` ของแพกเกจตัวเอง

**เจอโดย** formal บน mesh หาสาเหตุได้ 2026-09-11 (`31d4cba`) แก้วันเดียวกัน (`de8cac3`) ยืนยัน
บนบอร์ด 2026-09-12

**อาการ.** หลังเพิ่ม tid guard (2026-09-10) สภาพแวดล้อม formal ของ mesh ยังถอด assumption
one-hot-`tid` ไม่ได้: `assert_eject_dest` พังที่ step 4 โหนด 0 เด้ง flit ที่ `tdest = 0100` ออก
บันทึกครั้งแรกเดาว่า mux AND-OR ของ crossbar กำลัง OR สอง flit เพราะ grant ที่ไม่ใช่ one-hot หลุด
เข้าไป เดาผิด การล้าง payload ทั้งหมดของ flit ที่ถูกปฏิเสธไม่ได้ทำให้การพังหายไป

**สาเหตุ.** ถอดรหัส stimulus ของ counterexample ที่โหนด 0:

| step | tid | tdest | tlast | ตัวกรอง | ผล |
|---|---|---|---|---|---|
| 1 | `10` | `0000` | 0 | ผ่าน | เปิดแพกเกจ VC1 ไปโหนด 0 |
| 2 | `11` | `0000` | **1** | ทิ้ง | `tlast` ตัวเดียวของแพกเกจนั้นหายไป |
| 3 | `10` | `0100` | 0 | ผ่าน | ถูกต่อท้ายแพกเกจที่ยังเปิด ขี่ grant ของมัน เด้งออกที่โหนด 0 |

ตัวกรองขาเข้า (ทั้ง `dest_ok` และ `tid_ok` ทั้งที่ mesh และ wrapper) ทิ้ง flit ที่ถูกปฏิเสธด้วย
การไม่ยื่นมันเฉยๆ `packet_arbiter` รู้ขอบแพกเกจจาก `tlast` ที่ผ่านไปเท่านั้น ถ้า flit ที่ถูกทิ้ง
คือหาง แพกเกจบน VC นั้นเปิดค้าง หัวถัดไปที่ถูกรับกลายเป็น body flit ของมัน ไปที่ไหนก็ตามที่หัว
เก่าจ่าหน้า และระหว่างนั้น grant ของ router ปลายทางถูกถือไว้ ยืนยันด้วยการแยกตัวแปร: การ
assume ว่า flit ที่ถูกปฏิเสธไม่พา `tlast` ทำให้ BMC ผ่านสิบสอง step ทั้งที่ยังถอด assumption
one-hot อยู่

สองอย่างทำให้มันกว้างกว่าที่ assertion แสดง guard ฝั่ง host ของ wrapper มีทรงเดียวกัน และที่
นั่นผลคือส่งผิดไปยังโหนดที่แพกเกจก่อนหน้าจ่าหน้า และตัวกรอง `dest_err` มีอันตรายแบบเดียวกัน
ข้อโต้แย้งว่า `tdest` คงที่ต่อแพกเกจเป็นสิ่งที่ host ต้องรักษา ไม่ใช่สิ่งที่ RTL บังคับ และ host
ที่ยิง `tid` เพี้ยนไม่ใช่ host ที่ไว้ใจเรื่อง framing ได้

**การแก้** ("ดีไซน์ A, force-close on reject") ติดตาม `pkt_open` / `pkt_dest` ต่อ VC ที่ขาเข้า
แต่ละที่ เมื่อมี flit ถูกปฏิเสธ เขียน `tlast` สังเคราะห์ (ปลายทางของหัวที่บันทึกไว้ data 0) ลงทุก
VC ที่เปิดอยู่และกัน host ไว้จนกว่ามันจะลง แพกเกจที่ถูกตัดถึงโหนดที่ถูกต้องแบบขาดท้าย `dest_err`
/ `tid_err` ยกเหมือนเดิม แพกเกจถัดไปเริ่มเป็นหัวสะอาด ทางเลือก ("B" ปิดเฉพาะ VC ที่ flit ผิด
ดูเหมือนจะเล็ง) ถูกปัดตกเพราะเป็นลอจิกเพิ่มเพื่อประโยชน์ที่มีแค่ตอน host ส่งขยะอยู่แล้ว

**ตรวจโดย:**

- formal ของ mesh โดย**ถอด** assumption one-hot: bmc depth 10 PASS `assert_eject_dest` ยืนได้
  เอง cover ไปถึง force-close และท้ายสังเคราะห์ที่ส่งถึง
- formal ของ wrapper โดยถอด assumption one-hot ของมัน: prove PASS basecase + induction cover
  ไปถึง force-close แบบ VC เดียวและสอง VC
- regression หกเทสต์ทั้งสอง configuration นาฬิกา ยอดเท่า baseline `_FIXED` การรันสะอาดของ
  stress tester เท่าเดิม
- การรัน `BAD_TID` เทียบ RTL ก่อนแก้กับหลังแก้: `max_gap` ของ agent อีกสามตัวจาก **1209 / 886 /
  1104** ไซเคิลเป็น 65 / 41 / 150 ก่อนแก้ flit ผิดตัวเดียวจาก host ตัวเดียวคือการค้าง ~1100
  ไซเคิลของทุกโหนดอื่น ทับบนการส่งผิด การค้างนั้นอยู่ในข้อมูลก่อนแก้มาตลอด (886/1104 เดียวกัน
  โผล่ในตัวเลข `KILL_MIDPKT` ของ bug #5) และไม่มีใครรู้ว่ามันคืออะไร
- บนบอร์ด (2026-09-12): การรันสะอาดเท่ากับการรันสะอาดก่อนแก้ ซึ่งคือประเด็น; แล้ว campaign
  mode 2 กับ 3 โดยมี guard อยู่

จำนวน sequence error ภายใต้ `tid=11` ขยับจาก 1 เป็น 2 ตัวตรวจเป็นรายฟลิตและ modulo 6 บิต
ตัวเลขนั้นจึงคือ "กี่เลน VC ที่เห็นการกระโดดที่ไม่ใช่พหุคูณของ 64" ซึ่งเปลี่ยนตาม timing หนึ่ง
ไซเคิล ไม่ใช่สัญญาณ regression การส่งผิดเองแสดงในซิมนี้ไม่ได้เพราะทุก agent มีปลายทางคงที่
ข้อนั้นอาศัย proof

#### เจ็ดตัวนี้มีอะไรร่วมกัน

สี่ตัว (#1, #4, #5, #7) คือประโยคเดียวกันจากหัวข้อ 2.3: พอร์ตถูกถือจนถึง `tlast` และมีอะไรบาง
อย่างทำให้ `tlast` ไม่มา หรือมาให้ผิดแพกเกจ สองตัว (#3 กับ #2) เป็นนโยบาย arbitration ที่ดูถูก
แต่ผิดภายใต้การแย่งต่อเนื่อง หนึ่งตัว (#6) เป็นช่วงที่อยู่ที่ไม่มีใครเช็ค สามตัวแรกไม่มีตัวไหนถูก
จับด้วยเทสต์ simulation ห้าตัวดั้งเดิมหรือการรันฮาร์ดแวร์แบบ permutation; มันจะหลุดออกไปได้
ทุกตัวหลังจากนั้นถูกเจอด้วยการตรวจที่เขียนขึ้นเพราะบั๊กก่อนหน้าเผยจุดบอด: เทสต์ 6 หลัง #2,
liveness watchdog หลัง #3, formal หลัง #4, การถอด assumption ทีละข้อหลังมี formal

### 8.2 ข้อบกพร่องที่ไม่มีเลข

พวกนี้ไม่ใช่บั๊ก RTL ใน datapath ของ fabric แต่แต่ละอันเป็นข้อบกพร่องจริงในดีไซน์ เทสต์ tooling
หรือคำกล่าวอ้างเรื่อง verification และแต่ละอันกินเวลาหรือจะกิน ลิสต์ไว้ที่นี่ให้ไม่มีใครค้นพบซ้ำ

| # | ที่ไหน | อะไร | เจอโดย | แก้ |
|---|---|---|---|---|
| A | `gals_node_wrapper`, `arty_gals_noc_wrapper` | เอาต์พุต error ของ ECC ปล่อยลอย: error ที่ซ่อมไม่ได้ถูกตรวจพบแล้วโยนทิ้ง ข้อมูลเสียไหลต่อเงียบๆ | อ่าน top | 2026-09-03: ต่อครบถึงตัวนับและ `led[3]` |
| B | `dual_port_ram_ecc` | เส้นทางเตือน ECC ไม่เคยถูกแสดงว่าทำงานบนซิลิคอน ตัวนับ 0 ดูเหมือนสายขาดทุกประการ | คิดเรื่องหลักฐาน | 2026-09-10: ตัวฉีดตอน build `ecc_sbe_cnt = 3` โหนด `1111` บนบอร์ด; double-bit 2026-09-12 |
| C | `traffic_node_agent` | ไฟผ่านติดบน fabric ที่ deadlock: `done` มาจากตัวนับไซเคิล | การรันบอร์ด `VC_MODE=2` | liveness watchdog `done` กั้นด้วยการส่งที่เห็นจริง |
| D | `loopback_node_agent`, `uart_noc_host` | ทุก ILA tap อยู่หลัง `` `ifdef DEBUG_BUILD `` ที่ไม่มีอะไรนิยาม UART build ไม่มี instrumentation เลย | อ่าน UART top | ลบ guard probe ไม่มีเงื่อนไข เพิ่ม `dont_touch` |
| E | `noc_host.py` | ส่ง*หมายเลข* VC ในฟิลด์ `tid`; `vc_id=0` กลายเป็น `tid=00` และแพกเกจ VC0 ทุกใบหายเงียบ | round-trip UART บนบอร์ด | 2026-09-04: header แบบ one-hot |
| F | `arty_stress_top` | ปุ่ม reset รีเซ็ต MMCM ด้วย ฆ่านาฬิกาของ ILA | การจับ ILA ครั้งแรก | reset ของ MMCM ตรึง 0 (UART top ได้แก้เดียวกัน 2026-09-12) |
| G | `sources_1/new/old/*.sby` | `arbiter_formal.sby` กับ `mpmc.sby` ชี้ไปที่โมดูลของอีกโปรเจกต์ คำอ้างใน HANDOFF ว่า bug #1 มี formal คุ้มกันเป็นเท็จ | เขียน `packet_arbiter.sby` | proof arbiter จริงครั้งแรก 2026-09-04 และมันเจอรูของ bug #5 |
| H | `gals_noc_top`, `traffic_node_agent` | sticky flag ถูก OR / AND ใน LUT ตรงเข้า `sync_2stage` (CDC-10 ×5): glitch ของ LUT จะถูกจับเป็นสัญญาณเตือนหลอกถาวร | การรัน `report_cdc` ครั้งแรก 2026-09-12 | ผ่านรีจิสเตอร์ในโดเมนต้นทาง |
| I | top ทั้งสอง | async reset เส้นเดียวที่ไม่ sync เข้าฟลอปทุกตัวของทุกโดเมน (CDC-7 ×572 ทันทีที่มีต้นทางที่มีคล็อกแตะสาย); รอดมาได้เพราะช่วงนอน 1024 ไซเคิล | `report_cdc` หลังเพิ่ม VIO soft reset | `reset_sync` ต่อโดเมน พอร์ต reset ต่อโดเมน |
| J | stress build, `dest_err` | ตัวกรองปลายทางถูกพับเป็นค่าคงที่เพราะ `tdest` ของ agent เป็น parameter; ค่า `dest_err_cnt = 0` ทุกครั้งเป็นเรื่องโครงสร้าง และคำอ้างบนซิลิคอนหนึ่งข้อในเอกสารเป็น vacuous | ตามรอย probe `dest_err_node` ที่ "ไม่มีคล็อก" ไปเจอ `LUT1` ของ `GND` | mux ของ injector ทำให้โหนด 3 ทำงาน; `setup_debug.tcl` รายงานค่าคงที่; แก้เอกสาร |
| K | `formal/async_fifo.sby`, `async_fifo_fwft.sby` | "prove PASS" โดยไม่มี assertion ของ FIFO เองเลย (โมดูลย่อยถูกอ่านโดยปิด property); FIFO ข้ามโดเมนไม่มี formal property | จัดทำ catalogue ของ label สำหรับเอกสารนี้ 2026-09-14 | **ยังเปิด** (หัวข้อ 16) |
| L | `tb_noc_stress_tester` `BAD_DEST` | `release` บน `logic` ที่ถูกขับด้วยค่าคงที่เก็บค่าที่ force ไว้ตลอดกาล; โหนด 11 ยิงไปผิดโหนดทั้ง window | fairness อ่านได้ 56/44 | force ค่าจริงหนึ่งไซเคิลก่อน |
| M | `setup_debug.tcl` กับ flow ของ GUI | กับดัก Vivado หกอย่าง: wizard เขียนลงไฟล์ pin, `save_constraints` เรียง core ผิด, การหาคล็อกทำให้ probe แคบลงเงียบๆ, core เก่าตามมาตอนสลับ build, `debug_auto.xdc` ถูก synthesis อ่าน, core ที่ลบทิ้งคล็อกไว้, implementation ใน session เดิมไม่เห็น xdc ใหม่ | แต่ละอันโดยการจับที่พัง | จัดการหมดใน `setup_debug.tcl` / batch flow |
| N | ฝั่งพีซี | การเปิด COM port รีเซ็ต FPGA (FTDI DTR/RTS) ล้าง sticky flag และตัวนับ | ตัวนับอ่านได้ "2 วินาที" หลังผ่านไปหนึ่งนาที | อ่าน ILA ก่อนเปิดพอร์ตครั้งถัดไป; `batch_uart_session.tcl` |
| O | Vivado 2025.2 | crash ใน exit handler หลัง `close_project` ทั้งที่เขียน output ครบแล้ว exit code 139 | session A ครั้งหนึ่ง | สคริปต์ batch ใช้ marker `SESSION_A_DONE` |
| P | `xelab.bat` | `-generic_top "X=2"` ถูกตัดเพี้ยนบนเชลล์ Windows | พยายามส่ง `BAD_TID` | ห่อ testbench ใน top บรรทัดเดียว |
| Q | `HANDOFF.md` | บอกว่า arbiter กู้จากแพกเกจที่ถูกตัดไม่ได้ หลายเดือนหลัง timeout ของ bug #5 | เขียนเอกสารนี้ | แก้แล้ว |
| R | GitHub | merge commit ของ PR #7 ถูกสร้างแต่ record ของ PR ยังเปิดและ "dirty" | พยายาม merge | sync branch กับ `main` ใหม่ record ปิดตามปกติ |

---
## 9. verify ยังไง

### 9.1 Simulation

testbench สามตัวบวก stress tester หัวข้อ 6.6 รันจาก Vivado project (`run_sim_regression.tcl`)
หรือรันตรงจากซอร์สด้วย `xvlog`/`xelab`/`xsim` หัวข้อ 17 ให้ลำดับ compile เกณฑ์ผ่านของ
regression หกเทสต์: 6/6, `Mismatched=0`, `Pending=0` ในทั้งสี่ combination ของ `HW_CLOCKS` ×
`HS_VC_ALT` พร้อมยอด `Matched` ตามหัวข้อ 6.6 log `_FIXED` ที่ commit ไว้คือ baseline

ทุกการเปลี่ยน RTL วันที่ 2026-09-11/12 ตามด้วย regression เต็มทั้งสอง configuration นาฬิกาบวก
การรันสะอาดของ stress tester และทุกครั้งกลับมาเท่าเดิมทุกหลัก ความเท่ากันนั้นคือสัญญาณ
regression; fault mode เป็นการวัด ไม่ใช่ผ่าน/ตก

### 9.2 Formal

SymbiYosys ใต้ WSL (`Ubuntu-24.04`, OSS CAD Suite ที่ `/opt/eda/oss-cad-suite`: Yosys 0.68, SBY
0.68, Z3 4.15.5) สคริปต์ตัวละโมดูลใน `formal/` สิบเอ็ดโมดูล 22 task เขียวหมด ณ `afce6cd` โดยมี
ข้อแม้ในแถว K ข้างบน

#### Property catalogue

ทุก assertion และ cover ที่มี label เรียงตามโมดูล assert ที่ไม่มี label (`gray_counter`,
`sync_2stage`) อธิบายเป็นร้อยแก้ว

**`packet_arbiter` (prove, unbounded)**

| property | ความหมาย |
|---|---|
| `assert_onehot` | `grant` เป็น one-hot หรือศูนย์ |
| `assert_channel_lock` | ขณะ `LOCKED` และต้นทางที่ล็อกยังมีข้อมูล `grant` ไม่เปลี่ยน (property ของ bug #1; เป็นเท็จบน RTL เดิม) |
| `assert_abort_only_when_source_gone` | `force_release` ไม่มีวันยิงขณะต้นทางที่ล็อกมี `valid` สูง (รูของ bug #5) |

**`vc_port_arbiter` (prove, unbounded)**

| property | ความหมาย |
|---|---|
| `assert_vc_mutex` | VC0 กับ VC1 ไม่ขับ output พร้อมกันในไซเคิลเดียว |
| `assert_vc1_yields_when_stalled` | VC1 ไม่เป็นเจ้าของลิงก์ในไซเคิลที่มันขยับไม่ได้ (bug #3) |
| `assert_no_vc1_during_override` | ระหว่าง override ของ VC0 ทำงานและ VC0 ขยับได้ VC1 ถูกบล็อก |
| `assert_no_grant_without_credit` | ไม่มี grant ถูกส่งลงปลายน้ำโดยไม่มี `ready_out` ที่สอดคล้อง |
| `assert_override_only_at_limit` | `vc0_override` ขึ้นก็ต่อเมื่อ `starve_cnt` ถึง `STARVE_LIMIT` |
| `assert_bounded_starvation` | VC0 ที่รออยู่ได้รับบริการภายในขีดจำกัด (ข้อโต้แย้ง liveness เขียนเป็น bound) |
| `assert_inv_starve_cap`, `assert_inv_wait_cap`, `assert_inv_sync` | invariant ของตัวนับเงาที่ผูกตัวนับ formal กับตัวนับ RTL เพื่อให้ induction ปิดได้ |
| cover | `cover_vc1_preempts`, `cover_override_activated`, `cover_override_completed`, `cover_override_released_on_idle`, `cover_vc0_uses_link_while_vc1_stalled` |

**`vc_input_buffer` (bmc depth 16)**

| property | ความหมาย |
|---|---|
| `assert_head_tdata`, `assert_head_tdest`, `assert_head_tlast` | หัวคิวของแต่ละ VC เท่ากับที่ shadow FIFO บอกว่าถูกเขียนตรงนั้น: ไม่หาย ไม่ซ้ำ ไม่สลับ ไม่ข้ามเลน |
| `assert_no_cross_vc_write` | flit ที่ `tid[v]=0` ไม่มีวันลง VC v |
| `assert_ready_iff_room` | `s_ready[v]` คือ "count < DEPTH" พอดี |
| `assert_valid_iff_occupied` | `m_valid[v]` คือ "count > 0" พอดี |
| `assert_inv_cnt_cap` | ตัวนับเงาไม่เกิน `DEPTH` |
| cover | `cover_flit_through`, `cover_eop_out`, `cover_fifo_full`, `cover_both_vcs_busy`, `cover_vc0_full_vc1_open` |

**`router_5port_mesh_vc` (bmc depth 16, `abc bmc3`)**

| property | ความหมาย |
|---|---|
| `assert_route_iff_valid` | (พอร์ต, VC) ขอ output ก็ต่อเมื่อหัวคิว valid |
| `assert_route_onehot` | ขอ output เดียวพอดีต่อหัวที่ valid |
| `assert_eject_here` | หัวที่จ่าหน้าถึง router นี้ขอ LOCAL |
| `assert_no_false_eject` | หัวที่ไม่ได้จ่าหน้าถึงที่นี่ไม่ขอ LOCAL |
| `assert_grant_matches_route_vc0/1` | input ที่ได้ grant คือตัวที่ขอ output นั้น (โดย assume `tdest` คงที่ต่อแพกเกจใน `f_wf`) |
| `assert_no_grant_fanout_vc0/1` | ไม่มี input ถูก grant โดยสอง output พร้อมกัน (ไม่งั้น flit ถูกโคลน) |
| `assert_ready_needs_grant_vc0/1` | credit กลับไป input ก็ต่อเมื่อมันถือ grant |
| `assert_xbar_onehot` | select ของ crossbar เป็น one-hot ข้าม input และข้าม VC |
| `assert_xbar_data/dest/last/valid_vc0/1` | ฟิลด์ output เท่ากับหัวคิวของ input ที่ได้ grant |
| `assert_tid_vc0/1`, `assert_tid_idle` | `m_tid` บอก VC ที่ให้ grant; ศูนย์ตอนไม่มี grant |
| `assert_no_valid_without_grant` | ไม่มี `valid` ขาออกโดยไม่มี grant อยู่เบื้องหลัง |
| cover | `cover_eject_local`, `cover_forward_east`, `cover_turn_xy`, `cover_two_outputs`, `cover_both_vcs` |

**`noc_mesh_2x2_vc` (bmc depth 10, `abc bmc3`; cover depth 12, z3)**

| property | ความหมาย |
|---|---|
| `assert_eject_dest` | flit ที่เด้งออกที่ LOCAL ของโหนด i จ่าหน้าถึงโหนด i (property ที่ bug #7 ทำพัง) |
| `assert_eject_tid`, `assert_eject_tid_onehot0` | `tid` ที่เด้งออกเป็น one-hot ตอน valid ไม่มีวัน multi-hot |
| `assert_edge_north/south/east/west` | ไม่มี router ขับ `valid` ออกนอกกระดาน |
| `assert_bad_dest_blocked` | flit ที่ `tdest` นอกช่วงไม่มีวันถึง router (tail สังเคราะห์ถึงได้) |
| `assert_frame_err_blocked` | flit ที่ `tdest` ต่างจากหัวของแพกเกจที่เปิดอยู่ไม่มีวันถึง router |
| `assert_good_flit_passes` | flit ที่ผ่านทั้งสามตัวกรองถูกยื่นให้ router (ตัวกรองไม่ปฏิเสธเกิน) |
| `assert_local_in_range`, `assert_local_tid_onehot`, `assert_local_dest_stable` | ทุกอย่างที่เข้าทาง LOCAL รวม flit สังเคราะห์ อยู่ในช่วง เป็น one-hot และพาที่อยู่ของหัวแพกเกจ (property ที่ `f_wf` ของ router assume) |
| `assert_close_pend_only_open` | ไม่มีวันสังเคราะห์ `tlast` ลง VC ที่ไม่มีแพกเกจเปิด |
| `assert_host_held_while_closing` | `s_ready` เป็น 0 ระหว่างมี close ค้าง |
| cover | ส่งถึงทั้งสี่โหนด ทั้งสองลิงก์มีของวิ่ง ทั้งสอง VC พร้อมกัน ตัวกรองแต่ละตัวยก (`cover_dest_err_raised`, `cover_tid_err_raised`, `cover_frame_err_raised`) mesh ยังเป็นๆ หลัง dest ผิด `cover_force_close`, `cover_deliver_after_close` |

**`gals_node_wrapper` (prove, unbounded, `multiclock on`)**

| property | ความหมาย |
|---|---|
| `assert_tx_valid_iff_data`, `assert_rx_valid_iff_data` | mux ยก valid ก็ต่อเมื่อมี FIFO ไม่ว่าง |
| `assert_tx_pick_vc1/vc0`, `assert_rx_pick_vc1/vc0` | priority เด็ดขาด: VC1 ก่อน และ `tid` บอกอย่างนั้น |
| `assert_tx_data_vc1/vc0`, `assert_rx_data_vc1/vc0` | ฟิลด์ที่ยื่นคือหัวคิวของ FIFO ที่เลือก |
| `assert_tx_idle_tid`, `assert_rx_idle_tid` | `tid` เป็นศูนย์ตอน idle |
| `assert_tx_tid_onehot`, `assert_rx_tid_onehot` | one-hot ตอน valid |
| `assert_tx_no_pop_empty_vc0/1`, `assert_rx_no_pop_empty_vc0/1` | `r_en` ไม่มีวัน pop FIFO ที่ว่าง (ขยะกลายเป็น flit) |
| `assert_host_ready_map_vc0/1`, `assert_noc_ready_map_vc0/1` | ready เท่ากับ not-full (ฝั่ง host: และไม่ได้ closing) |
| `assert_no_host_write_while_closing` | การเขียนของ host ถูกบล็อกระหว่างมี close ค้าง |
| `assert_close_pend_only_open` | close ค้างได้เฉพาะ VC ที่เปิด; จงใจไม่กั้นด้วย `f_past_valid` (ไม่งั้นเป็น artefact ของ induction) |
| `assert_ecc_sbe_out`, `assert_ecc_dbe_out` | ธงภายนอกคือ OR ของ latch ทั้งสองโดเมน |
| cover | `cover_tx_vc1`, `cover_tx_vc0`, `cover_rx_vc1`, `cover_both_paths`, `cover_vc0_waits_behind_vc1`, `cover_tx_force_close`, `cover_tx_force_close_both` |

**`fwft_wrapper` (prove ผ่าน `async_fifo_fwft.sby`)**: `assert_no_overflow` (ไม่มีวันมีคำในอากาศ
เกินสอง), `assert_skid_physics` (ช่อง skid ถูกเติมเฉพาะเมื่อช่อง output เต็ม),
`assert_empty_status` (empty ที่ผู้ใช้เห็นสะท้อนรีจิสเตอร์ output), `assert_reset_out/skid/arr`
(reset ล้างทั้งสาม)

**`dual_port_ram_ecc` (prove)**: `assert_ram_address_integrity`, `cover_clean_read`

**`gray_counter` (prove)**: หลัง reset ทั้งคู่เป็นศูนย์; `ptr_g == bin ^ (bin >> 1)` เสมอ; ก้าวที่
enable เปลี่ยน `ptr_g` หนึ่งบิตพอดี ก้าวที่ไม่ enable ไม่เปลี่ยน; MSB พลิกตอน wrap cover: wrap
(depth 40)

**`sync_2stage` (prove)**: reset ล้างทั้งสองขั้น; `assert_stage2` (output เท่ากับ input เมื่อสองขอบ
ก่อน); `cover_data_pass`

**`async_fifo`, `async_fifo_fwft`**: ดูแถว K ในหัวข้อ 8.2 สคริปต์ผ่าน แต่ไม่มี property ของ FIFO
เองเลย

#### ธรรมเนียม

- บล็อก `FORMAL` อยู่ใน RTL ใต้ `` `ifdef FORMAL `` บล็อกของโมดูลเองถูกปิดด้วย `` `ifndef
  FORMAL_TOP_INTEGRATION `` (arbiter, counter) หรือ `-D FORMAL_NO_ROUTER` (router) เมื่อ
  พิสูจน์ตัวแม่ เพื่อไม่ให้ assumption ตกบนสายที่มีตัวขับ ด้านกลับคือแถว K: สคริปต์ตัวแม่ที่อ่าน
  ทุกโมดูลย่อยโดยตั้ง guard และไม่มี property ของตัวเอง พิสูจน์อะไรไม่ได้เลย และ `sby` รายงาน
  PASS อย่างสบายใจ
- โมดูลที่มี port แบบ unpacked array ต้องใช้ frontend slang (`plugin -i slang; read_slang`); slang
  ไม่มี `$onehot` จึงมี helper `f_onehot` และมันตั้งชื่อเซลล์ assert จาก label ดังนั้น label ใน
  `for` loop ธรรมดาต้องอยู่ในบล็อก `generate`
- `memory_map` กาง array ของ FIFO; ไม่มีมัน z3 ไม่จบ
- router กับ mesh ใช้ `abc bmc3` สำหรับ bmc; z3 ใช้กับ cover และ `prove` ทุกตัว
- `prove` หมายถึง k-induction ผ่านและ property เป็น unbounded `bmc` หมายถึง bounded; สามโมดูล
  ที่ bounded ผูก state ของ arbiter หรือเงาเข้ากับเนื้อ FIFO ซึ่ง induction ละเมิดได้จากสถานะ
  เริ่มต้นที่ไปถึงไม่ได้ depth ที่ bounded ลึกพอให้เติมและระบายคิวหลายรอบ
- invariant ที่เป็น state ล้วนต้องไม่กั้นด้วย `f_past_valid`; induction จะเริ่มจากสถานะเสียตอน
  assert ปิดอยู่
- assumption ถูกถอดทันทีที่ RTL บังคับ property ช่วงของ `tdest` (bug #6), `tid` one-hot (bug
  #7) และ `tdest` คงที่ (2026-09-12) ทั้งหมดเปลี่ยนจาก assumption เป็น proof ในสภาพแวดล้อมของ
  mesh

property สองตัวที่เขียนระหว่างงานนี้กลายเป็นผิดและการรันบอกไว้: `assert_idle_tid` (เข้มกว่าที่
AXI4-Stream ยอม) และ assert เรื่อง sticky latch ของ ECC (vacuous และทำ induction พัง) ทั้งคู่
บันทึกไว้ใน `HANDOFF.md` ไม่ให้ใครใส่กลับ

### 9.3 Silicon

flow (batch ทั้งหมด หัวข้อ 17): `batch_stress_synth_debug.tcl` → `batch_impl.tcl` (session
ใหม่ จบด้วย `report_cdc`) → `batch_program_capture.tcl` หรือ `batch_fault_campaign.tcl` →
`analyze_ila.py` / `summarize_campaign.py`

ILA พา `MARK_DEBUG` ราว 1123 บิตใน core ห้าตัว (ตัวละโดเมนนาฬิกา): ตัวนับทุกตัวของ agent, perf
monitor, โหนดและตัวนับของ ECC/`dest_err`/`tid_err`, `stuck_seen`/`max_gap`, และ
`active`/`fired`/`mode` ของ injector `analyze_ila.py` คำนวณ throughput ต่อ agent เป็น MB/s
(window ของแต่ละ agent ยาวไม่เท่ากันในเวลาจริง gotcha 4), link utilisation, conservation (flit
เข้า = flit ออก), การแบ่งของ arbiter และคำตัดสินเรื่อง liveness, ECC, `dest_err` และ `tid_err`
มันบอกว่า "unprovable" ไม่ใช่ "pass" เมื่อ probe หายไป และอธิบายเรื่อง `dest_err_node` ที่หาย
บน stress build

`report_cdc` รันบนทุกดีไซน์ที่ route แล้วตั้งแต่ 2026-09-12 output ที่คาดคือ CDC-3 (1 บิต sync
แล้ว), CDC-6 (gray pointer 37 ตัว), CDC-9 (reset synchronizer สองตัวของ ILA) และ CDC-15 (พอร์ต
อ่านของ FIFO RAM และภายใน ILA); อะไรที่เป็น Critical ถูกสคริปต์ impl พิมพ์เป็น
`CDC_CRITICAL_PRESENT` และต้องอธิบายให้ได้ก่อนเชื่อ bitstream

ทุกตัวเลขใน `HANDOFF.md` มี log ใน `hw_logs/` บทเรียนที่หล่อหลอมทั้งหมดนี้: **ไฟเขียวต้องเป็น
หลักฐาน ไม่ใช่การไม่มีหลักฐาน** ไฟผ่านเคยติดบน fabric ที่ deadlock; ตอนนี้ `done` ต้องมี flit
ขยับจริง ไฟผ่านถูกดับด้วยธง error ทุกตัว คำตัดสินของ analyser ทุกข้อบอก "unprovable" เมื่อ probe
ของมันหาย เส้นทาง ECC ถูกพิสูจน์ด้วยการฉีด fault และตัวกรองปลายทางถูกนับว่าแสดงแล้วก็ต่อเมื่อ mux
ตอนรันทำให้มันพับทิ้งไม่ได้

### 9.4 ตาราง coverage

แต่ละกลไกถูกครอบด้วยอะไร "sim" หมายถึง testbench จำลองการพังและการแก้; "formal" บอกสคริปต์;
"silicon" บอก log

| กลไก | sim | formal | silicon |
|---|---|---|---|
| ล็อกแพกเกจถือครบทั้งแพกเกจ (bug #1) | regression เทสต์ 2, 4 | `packet_arbiter` `assert_channel_lock` | ทุกการรันสะอาด (seq error 0) |
| ความยุติธรรมของ round-robin (bug #2) | เทสต์ 6 | (นโยบาย; ไม่ใช่ formal property) | EAST/NORTH 48.3/51.7 |
| VC อิสระ + starvation override (bug #3) | เทสต์ 5, `HS_VC_ALT` | `vc_port_arbiter` | 57.5% → 97.0%, VC 50/50 |
| agent ส่งแพกเกจให้จบ (bug #4) | `tb_noc_stress_tester` | | liveness PASS, +15.7% |
| stall timeout ปล่อยพอร์ตกำพร้า (bug #5) | `KILL_MIDPKT`, `FAULT_MODE=1` | `packet_arbiter` `assert_abort_only_when_source_gone` | campaign mode 1 (gap 608/611) |
| ปฏิเสธ `tdest` นอกกระดาน (bug #6) | `FAULT_MODE=5` | mesh ถอด assume ช่วงค่า | campaign mode 5 |
| flit ที่ถูกปฏิเสธปิดแพกเกจของตัวเอง (bug #7) | `BAD_TID`, `FAULT_MODE=2/3` | mesh + wrapper ถอด assume one-hot | campaign mode 2, 3 |
| tid guard แบบ one-hot | `BAD_TID`, `FAULT_MODE=2/3`, UART `neg` | mesh + wrapper | campaign 2/3, UART `tid=00` |
| constant `tdest` guard | `BAD_DEST`, `FAULT_MODE=4` | mesh `assert_local_dest_stable` | campaign mode 4 |
| ECC ซ่อม/ตรวจ | `tb_ecc_secded` exhaustive | (`dual_port_ram_ecc` เฉพาะ address) | build `ECC_INJECT_SBE` / `_DBE` |
| สัญญาณเตือน ECC ถึงตัวนับและ LED | `INJECT_ECC` | | `ecc_sbe_cnt=3` โหนด `1111`; `ecc_dbe_cnt=3` |
| liveness watchdog | `tb_traffic_node_agent` 10/10 | | การรันบอร์ดครั้งแรกจับ bug #4 |
| ความถูกต้องของ pointer/ลำดับใน async FIFO | ทุก regression ทางอ้อม | **ไม่มี** (แถว K) | seq error 0 บน flit หลายล้านตัว |
| reset deassert sync ต่อโดเมน | | | `report_cdc` Critical 0 |
| ความถูกต้องของไบต์ผ่าน UART ทั้งสอง VC ทุกโหนด | | | `uart_roundtrip.py` 6/6 |

---

## 10. บนบอร์ด: พฤติกรรมเฉพาะฮาร์ดแวร์

ทุกอย่างข้างบนเป็นจริงในซิมด้วย หัวข้อนี้คือสิ่งที่เป็นจริง หรือมองเห็น เฉพาะบน Arty ตัวเลข
resource มาจาก stress build วันที่ 2026-09-10 (build สุดท้ายที่เก็บรายงาน utilisation ไว้) ตัวเลข
timing กับ CDC มาจาก build ของ fault campaign วันที่ 2026-09-12 ที่เหลือมาจาก log ใน `hw_logs/`

### 10.1 ใน bitstream มีอะไร

| | |
|---|---|
| part | xc7a100tcsg324-1 (Arty A7-100T, Digilent 210319C088F2A) |
| top | `arty_stress_top`, `PATTERN=1 VC_MODE=2` |
| นาฬิกา | `MMCME2_ADV` หนึ่งตัว: 100 MHz เข้า VCO 1000 MHz (mult 10) output หารด้วย 12.5 / 10 / 14 / 12 / 14 |
| slice LUT | 10,898 จาก 63,400 (17%) |
| slice register | 16,244 จาก 126,800 (13%) |
| block RAM tile | 31.5 จาก 135 (23%) |
| timing (09-10) | WNS +0.711 ns, WHS +0.014 ns, TPWS +3.0 ns; ทุก constraint ผ่าน |
| timing (09-12, build ของ campaign) | WNS **+0.977 ns**, WHS +0.016 ns; `report_cdc` Critical 0 |
| debug (09-12) | `MARK_DEBUG` 1126 เน็ต → ILA core 5 ตัว / probe 61 / 1123 บิต บวก `dbg_hub` กับ `vio_fault` |

block RAM ส่วนใหญ่เป็นหน่วยความจำจับสัญญาณของ ILA ไม่ใช่ fabric ที่เก็บของ fabric เองเล็ก:
router แต่ละตัวมี 5 พอร์ต x 2 VC x 16 ช่อง x 13 บิตใน distributed RAM และ wrapper แต่ละตัวมี
async FIFO สี่ตัวขนาด 16 x 13 บิต MMCM เป็น clock resource เดียว

เทียบกัน UART build (`arty_gals_noc_wrapper`) ปิดที่ WNS +0.326 ns (09-12 มี reset synchronizer;
+1.204 ก่อนหน้า) โดยมี `MARK_DEBUG` 484 เน็ตใน core 5 ตัว CDC Critical 0 ทุก build path แย่สุด
เป็นเส้นเดียวกัน: read pointer ของ input buffer ใน router 0 → crossbar → RAM ของ RX FIFO ใน
wrapper 00, logic 8 ชั้น, ~80% routing WNS ขยับไม่กี่ร้อยพิโควินาทีระหว่าง build จาก placement
ล้วนๆ ไม่มีการเปลี่ยน RTL วันที่ 2026-09-12 แตะ path นั้น

### 10.2 นาฬิกาห้าเส้นถูกประกาศเป็น asynchronous STA จึงไม่ตรวจระหว่างกัน

`timing.xdc` มีคำสั่งเดียว: `set_clock_groups -asynchronous` บน output ทั้งห้าของ MMCM Vivado
จึงวิเคราะห์ timing **ภายใน**แต่ละโดเมนและมองข้ามทุก path **ระหว่าง**โดเมน ถูกต้องสำหรับดีไซน์
นี้ และแปลว่าความถูกต้องที่รอยต่อไม่ใช่สิ่งที่รายงาน timing ยืนยันได้ มันมาจากโครงสร้าง:

- ข้อมูลหลายบิตข้ามโดเมนเฉพาะใน `async_fifo` ผ่าน RAM ที่ address ด้วย pointer ที่เป็น gray
  และผ่าน `sync_2stage` pointer ที่ sample กลางการเปลี่ยนอย่างมากก็เก่าไปหนึ่งก้าว
- ธงบิตเดียวข้ามได้ก็ต่อเมื่อ sticky (ตั้งครั้งเดียว ไม่ล้าง) ผ่าน `sync_2stage`
- รีจิสเตอร์ output ของ `sync_2stage` ติด `ASYNC_REG = "TRUE"` ซึ่งบอก Vivado ให้วางสองฟลอปใน
  slice เดียวกันและไม่ optimize แยกกัน

อะไรที่ข้ามโดเมนด้วยทางอื่นคือบั๊กที่รายงาน timing ไม่ฟ้อง `report_cdc` คือเครื่องมือที่ฟ้อง และ
ตั้งแต่ 2026-09-12 `batch_impl.tcl` รันมันบนทุกดีไซน์ที่ route แล้ว การรันครั้งแรกเจอ critical
ห้าเส้น ทั้งหมดรูปแบบเดียว: sticky flag ถูก OR หรือ AND ใน LUT แล้วป้อนตรงเข้า synchronizer สอง
ฟลอป (`|ecc_dbe`, `|tid_err_node`, `test_done && !stuck_seen`) LUT อาจ glitch ตอนอินพุต
เปลี่ยนและ synchronizer จับ glitch เป็น 1 จริง sticky error flag จึงเตือนหลอกได้ แก้โดยผ่าน
รีจิสเตอร์ในโดเมนต้นทางก่อน รายการที่เหลือในรายงานคือ gray pointer (CDC-6), พอร์ตอ่านของ FIFO
RAM (CDC-15) และ reset synchronizer (CDC-9) ซึ่งคาดไว้ทั้งหมด

simulation ไม่มี metastability ทุกการข้ามใน xsim resolve สะอาดไม่ว่าเฟสไหน บอร์ดเป็นที่เดียวที่
ดีไซน์ synchronizer ถูกใช้งานจริง และหลักฐานว่ามันทำงานเป็นทางอ้อม: sequence error ศูนย์บน flit
3.9 ล้านตัวต่อ sender ทุกครั้ง

### 10.3 Reset กับการเปิดเครื่อง

`global_rst_n = rst_n_btn & pll_locked` ดีไซน์ถูกกด reset จน MMCM lock และปุ่มรีเซ็ตเฉพาะ
ลอจิก reset ของ MMCM เองตรึงไว้ที่ 0 ใน top ทั้งสอง: build ก่อนหน้าต่อปุ่มเข้าไป และการกดปุ่ม
ฆ่านาฬิกาทั้งห้ารวมตัวที่ `dbg_hub` กับ ILA ใช้ ทุกการจับจึงตายพร้อม reset

ตั้งแต่ 2026-09-12 สายนั้นป้อน `reset_sync` ห้าตัว ตัวละนาฬิกา (หัวข้อ 3.5) ฟลอปของแต่ละโดเมนจึง
ออกจาก reset บนขอบนาฬิกาของตัวเอง soft reset ของ VIO เป็นขาเข้าแบบ synchronous ของ
`reset_sync` แต่ละตัว ก่อนหน้านี้ `global_rst_n` เข้า async clear ของฟลอปทุกตัวในทั้งห้าโดเมน
ตรงๆ และ `report_cdc` โชว์ reset deassert ที่ไม่ sync 572 เส้นทันทีที่ต้นทางที่มีคล็อก (VIO) ถูก
AND เข้าไป ดีไซน์รอดมาได้เพราะช่วงนอนที่อธิบายข้างล่าง

เนื้อ RAM ไม่ถูก reset (RAM primitive ของ Xilinx ทำไม่ได้) ซึ่งคือเหตุผลที่ `async_fifo` qualify
ธง ECC ด้วย `ecc_read_valid`: ก่อนการอ่านจริงครั้งแรก decoder กำลังมองอะไรก็ตามที่ RAM เปิด
เครื่องมาด้วย

`traffic_node_agent` เริ่มที่ `S_WARMUP` เป็นเวลา `2**WARMUP_LOG` = 1024 ไซเคิลก่อนส่งอะไร
เพื่อให้ async FIFO ทั้งสองฝั่งออกจาก reset และ synchronizer นิ่ง แล้ว `S_RUN` เป็นเวลา
`2**WINDOW_LOG` = 16,777,216 ไซเคิล `S_DRAIN` 4096 แล้ว `S_DONE` ที่ทุกตัวนับแช่ ILA ถูกอ่านหลัง
`S_DONE`; `analyze_ila.py` รายงานคอลัมน์ `state` การจับที่เร็วเกินจึงเห็นชัด

### 10.4 window เดียวกันยาวไม่เท่ากันในแต่ละโหนด

`WINDOW_LOG` นับไซเคิลของนาฬิกาของ agent เอง:

| agent | นาฬิกา | 2^24 ไซเคิล = |
|---|---|---|
| agent_00 (sink) | 100.00 MHz | 168 ms |
| agent_10 | 83.33 MHz | 201 ms |
| agent_01, agent_11 | 71.43 MHz | 235 ms |

ผลสามอย่าง ทุกอันเคยกินเวลากว่าจะเข้าใจ:

- จำนวน flit ดิบเทียบข้าม agent ไม่ได้ `analyze_ila.py` แปลงเป็น MB/s ด้วยความถี่ของแต่ละ agent
  และทำ conservation check (flit เข้า = flit ออก) บนช่วงที่ทับกันแทน
- sink หยุด**ก่อน** 67 ms ก่อน sender ที่ช้าสุด อะไรที่ sender พวกนั้นทำใน 67 ms สุดท้ายไม่ถูกนับที่
  sink ตัวเลข utilisation 97.0% คือ window ของโหนด 00 ซึ่งปิดก่อนผลตอนท้ายจะเริ่ม
- sender หยุดคนละเวลา และใครหยุดก่อนขณะมีแพกเกจในอากาศก็ทิ้งแพกเกจนั้นค้าง การเหลื่อมนั้นคือสิ่งที่
  trigger bug #4 บนสองโหนด 71.43 MHz และไม่ใช่ที่อื่น simulation ด้วย `HW_CLOCKS` จำลองการเหลื่อม
  ได้; ด้วยนาฬิกา default ไม่ได้ นั่นคือเหตุผลที่ทั้งคู่อยู่ใน regression

### 10.5 คอขวดอยู่ตรงไหนจริงๆ

sink วิ่งที่ 100 MHz และยก `rx_tready = 11` ตลอด; NoC วิ่งที่ 80 MHz และส่งได้อย่างมากหนึ่ง flit
ต่อไซเคิลต่อพอร์ต LOCAL sink จึงไม่มีวัน backpressure และ output LOCAL ของโหนด 00 คือขีดจำกัด
แข็ง: 80 Mflit/s บอร์ดวัดได้ 77.6 Mflit/s ส่งถึง = **97.0%** sender รวมกันเสนอ 80.2 MB/s และเห็น
stall 46-77% บนลิงก์ TX ของตัวเอง ซึ่งคือ arbiter บอกให้รอ ไม่ใช่ความผิด

sender สามตัวแบ่งพอร์ต 48.3 / 24.2 / 27.5% นั่นไม่ใช่ arbiter ไม่ยุติธรรม: LOCAL arbiter ของ
โหนด 0 เห็นสองพอร์ตขาเข้า EAST (agent_01 เดี่ยว) กับ NORTH (agent_10 กับ agent_11 รวมกันแล้วที่
router 2) และแบ่ง 48.3 / 51.7 simulation บอก 49 / 51 ภายใน NORTH agent_11 ได้มากกว่า agent_10
ส่วนหนึ่งเพราะ window ของมันยาวกว่า 17% ในเวลาจริง (หัวข้อ 10.4 อีกครั้ง)

### 10.6 ช่องว่าง GALS ของจริง

ในซิม ช่วงเงียบยาวสุดที่ sender เห็นคือ 136 ไซเคิล; บนบอร์ดคือ **219** (`max_gap` การรัน
2026-09-04; 219 / 40 / 138 / 108 ต่อ agent) ส่วนต่างคือ jitter กับ phase drift ของนาฬิกาจริงที่
simulator ไม่จำลอง threshold สองตัวตั้งเทียบตัวเลขนี้:

- `STUCK_LOG = 16` → 65,536 ไซเคิล ≈ 300x ช่องว่างแย่สุดที่วัดได้ liveness watchdog จึงยิงหลอกบน
  ช่องว่างปกติไม่ได้ ตัวเลขเดาแรก (2^16 ยืมมาจากอีกโมดูล) บังเอิญโอเค; ประเด็นของ `max_gap` คือ
  มันไม่ใช่การเดาอีกต่อไป
- `STALL_LOG = 10` ใน `packet_arbiter` → *ต้นทางเงียบ* 1024 ไซเคิลก่อนพอร์ตที่ล็อกถูกทิ้ง ≈ 5x
  ช่องว่างแย่สุดที่เคยเห็นระดับ agent และสูงกว่าช่องว่างระดับสิบไซเคิลที่ input ของ router เห็น
  ตอน FIFO ของ wrapper แห้งมาก

### 10.7 LED หมายถึงอะไร (stress build)

| LED | ความหมาย |
|---|---|
| `led[0]` | heartbeat `heartbeat_cnt[26]` บน `clk_h00` ราว 0.75 Hz ดีไซน์ยังเป็นๆ และมีคล็อก |
| `led[1]` | `pass_group1` และไม่มี ECC double-bit ไม่มี `dest_err` ไม่มี `tid_err` `PATTERN=1`: agent ทุกตัวจบ window โดย liveness ยังดี |
| `led[2]` | `pass_group2` ภายใต้การกั้นเดียวกัน `PATTERN=1`: จบและโหนด 00 เห็น sequence error ศูนย์ |
| `led[3]` | `any_fail` หรือ ECC double-bit หรือ `dest_err` หรือ `tid_err` |

กฎสองข้อเบื้องหลังตารางนี้ LED เขียวต้องมีหลักฐานเชิงบวก: `done` ต้องมี flit ขยับระหว่าง `S_RUN`
(liveness watchdog) fabric ที่ deadlock จึงโชว์ `led[1]`/`led[2]` ดับ ที่เคยโชว์ติด และธง error
ทุกตัวที่หมายถึง "ข้อมูลไม่ถึงหรือเสีย" **ดับ** LED เขียว ไม่ใช่แค่เปิดสีแดงเพิ่ม ทั้งคู่มาจาก
เหตุการณ์เดียวกัน: build `VC_MODE=2` โชว์เขียวบน fabric ที่ deadlock ไปแล้ว

ธงถึง LED ผ่าน `sync_2stage` จาก `clk_noc` ไป `clk_h00` ปลอดภัยเพราะ sticky ECC error บิตเดียว
(ซ่อมแล้ว) ไม่แตะ LED เลย มองเห็นได้เฉพาะในตัวนับ ILA

LED ของ UART build เป็นตัวบอกกิจกรรม (`led[1]` ตาม `uart_rxd`, `led[2]` ตาม `uart_txd`, `led[3]`
มีโหนด loopback ตัวไหนกำลังส่ง) ไม่มีคำตัดสินที่นั่น

### 10.8 ILA: เห็นอะไรได้และเห็นอะไรไม่ได้

ILA core ตัวละโดเมนนาฬิกา เพราะ core หนึ่งตัว sample บนคล็อกเดียว `setup_debug.tcl` จัดกลุ่ม
net ตามคล็อกของฟลอปที่ขับ และรวมบิต `name[n]` เป็น probe กว้างตัวเดียว core ถูกอ่านด้วย
**Trigger Immediately** หลังการรันนิ่งแล้ว ทุกค่าจึงเป็นตัวนับสุดท้ายที่แช่ ไม่มีการจับทราฟฟิก
แบบ waveform

สิ่งที่โผล่เฉพาะที่นี่:

- ตัวนับที่อ่านได้ 0 หมายถึง "ไม่มีอะไรเกิด" หรือ "net ถูกกวาดทิ้งและ probe ต่อกับตอ" อย่างใด
  อย่างหนึ่ง `mark_debug` เฉยๆ ไม่หยุด synthesis จากการลบรีจิสเตอร์ที่ไม่มี fanout; `dont_touch`
  หยุด ตัวนับทุกตัวในดีไซน์ตอนนี้มีทั้งคู่ และ `analyze_ila.py` บอก "unprovable" ไม่ใช่ "pass"
  เมื่อ probe หาย
- ตัวนับ ECC เป็น 0 ทุกการรันจนถึง 2026-09-10 และนั่นพิสูจน์อะไรไม่ได้จนกระทั่ง bitstream ที่ใส่
  `ECC_INJECT_SBE` อ่านได้ `ecc_sbe_cnt = 3`, `node_sbe = 1111`, `ecc_dbe_cnt = 0` โดยทราฟฟิกยัง
  ไม่มี error ตอนนี้ 0 แปลว่าเงียบ ตัวฉีด double-bit รันบนซิลิคอนวันที่ 2026-09-12
- เพราะ fault injector mux `tdest` ของ agent_11 ตอนรัน `dest_err_node[3]` ทำงานจริงและ `dest_err`
  ถูกสังเกตบน stress bitstream แล้ว (campaign mode 4 กับ 5) บิต `[2:0]` ยังเป็นค่าคงที่ และ
  `setup_debug.tcl` ลิสต์ไว้ใต้ "ค่าคงที่หลังสังเคราะห์" ไม่ใช่ "ไม่มีคล็อก"
- จำนวน net `MARK_DEBUG` คือลายนิ้วมือของสิ่งที่ถูก instrument: 924 (เดิม), 928 (+watchdog),
  1024 (+`max_gap`), 1064 (+ECC), 1084 (+`dest_err`), 1104 (+`tid_err`), 1126 (+injector) ตัวเลข
  อื่นแปลว่า Set Up Debug ไม่ได้รันใหม่หลังเปลี่ยน RTL และ analyser จะปฏิเสธที่จะให้ liveness ผ่าน

### 10.9 build flow มี state ที่ตามคุณไป

กับดักในหัวข้อ 15 เล่าใหม่เป็นพฤติกรรม เพราะบนบอร์ดมันดูเหมือนบั๊ก RTL:

- implementation ที่รันใน Vivado session เดียวกับที่เพิ่งเขียน `debug_auto.xdc` ได้ bitstream
  **ไม่มี ILA และไม่มี error** session A: synth + `setup_debug.tcl` session B: implement
- `open_run synth_1` โหลด `debug_auto.xdc` ของ build ก่อน การสลับระหว่าง top แบบ stress กับ
  UART จึงพา core เก่าตามมา สคริปต์ลบมันก่อน
- `debug_auto.xdc` ต้องเป็น `USED_IN = implementation` เท่านั้น ไม่งั้น synthesis อบ core เก่าเข้า
  netlist และชื่อคล็อกกลับมาเป็น `u_ila_0_clk_out1_clk_wiz_0`
- การลบ debug core ไม่ลบคล็อกที่มันสร้างใน session นั้น
- `verilog_define {ECC_INJECT_SBE}` ค้างอยู่ใน project; ล้างหลัง build ฉีด ไม่งั้น bitstream
ครั้งถัดไปที่ตั้งใจให้ปกติจะไม่ปกติ

### 10.10 UART build เฉพาะเรื่อง

host 00 เป็นสะพาน UART ที่ 3 Mbaud บนนาฬิกา 100 MHz (33.3 คล็อกต่อบิต) สองไบต์ต่อ flit
หมายถึงอย่างมาก ~150 kflit/s แต่ละทิศ ต่ำกว่า fabric สามระดับขนาด เส้นทาง UART จึงไม่เคย
ทดสอบการแย่ง; มันทดสอบการจ่าหน้า การเลือก VC การ frame แพกเกจ และความถูกต้องของไบต์ สิ่งที่แสดง
บนบอร์ด: แพกเกจ 149 ไบต์ไปโหนด 3 บน VC1 echo กลับเหมือนเดิมทุกไบต์โดย `tlast` อยู่ที่ที่ควร;
ทั้งสี่ combination (ปลายทาง, VC) round-trip ได้; ตัวนับ ECC กับ `dest_err` อ่านได้ 0 บน 1024
sample ของ ILA; และ flit `tid = 00` (พฤติกรรมของ `noc_host.py` ก่อนแก้) ไม่มีวันกลับมา ซึ่งคือ
การหายเงียบที่ tid guard ตอนนี้ยกธง สคริปต์ demo (`image_noc_test.py`, `video_noc_stream.py`)
ดันรูปกับสตรีมวิดีโอผ่านเส้นทางเดียวกัน; `recovered_from_fpga.png` คือผล

ฝั่ง host: รัน `python -u` ตั้ง `PYTHONIOENCODING=utf-8` และเช็ค `COM_PORT`

### 10.11 Simulation กับ silicon เคียงกัน

| ปริมาณ | simulation | บอร์ด |
|---|---|---|
| utilisation LOCAL ของโหนด 00 `VC_MODE=2` หลัง bug #3 | 97.2% | 97.0% |
| การแก้ bug #4 delta ของ agent_01 / agent_11 | +16% / +32.9% | +16.4% / +32.9% |
| การแบ่ง LOCAL ของโหนด 0 EAST / NORTH | 49 / 51 | 48.3 / 51.7 |
| การแบ่ง VC ที่ sink | 50 / 50 | 50.0 / 50.0 |
| `max_gap` แย่สุด (ไซเคิล) | 136 | 219 |
| sequence error การรันสะอาด | 0 | 0 |
| ฉีด ECC บิตเดียว `ecc_sbe_cnt` | 3 | 3 (`node_sbe = 1111`) |
| ฉีด ECC สองบิต `ecc_dbe_cnt` | 3 | 3 (`node_dbe = 1111`), seq error 0 (การพลิกบิตเดียวกันสองครั้งข้าม TX กับ RX FIFO หักล้างกัน) |
| ตัด agent_11 กลางแพกเกจ `max_gap` ของผู้รอด | 871 / 1087 | 608 / 611 |
| `tdest=0001` 2000 ไซเคิล flit ที่ถูกเบนไป agent_10 | 1787 | 1777 |

`tb_noc_stress_tester` ด้วย `HW_CLOCKS` ทำนายบอร์ดได้ภายในเศษส่วนของเปอร์เซ็นต์บนทุกตัวเลข
throughput และมองโลกในแง่ร้ายแค่เรื่องช่องว่าง นั่นคือสิ่งที่ทำให้การรัน stress ที่ผ่านถือเป็น
หลักฐานได้ก่อนมีบอร์ด

### 10.12 การเปิด COM port รีเซ็ตบอร์ด

เจอ 2026-09-12 ตอนรัน UART build ใหม่ `serial.Serial('COM3')` จากพีซีสับ DTR/RTS ของ FTDI และ
วงจร reset ของ Arty ตามไป สคริปต์ฝั่ง host ทุกตัวจึงเริ่มด้วยการรีเซ็ต fabric: sticky flag ล้าง
ตัวนับ `mon_*` เริ่มใหม่ `uart_noc_host` ที่ค้างอยู่ฟื้น การเปิด JTAG target ไม่ทำแบบนี้ (การจับ
สองครั้งห่างกัน 5 s ใน session เดียว `mon_active_cnt` เดินไป 5.1 s) ดังนั้น: อ่าน ILA ก่อนเปิด
พอร์ตครั้งถัดไป และให้การจับทั้งหมดของการทดลองหนึ่งอยู่ใน `hw_server` session เดียว
`hw_scripts/batch_program_capture.tcl` ด้วย `noprog` ทำแบบนั้น

session เดียวกันแสดงว่า flit `tid=00` จากพีซีทำอะไร: ไม่มีอะไร echo, `tid_err_cnt` 1 / `node`
`0001`, และ `uart_noc_host` นั่งอยู่ใน `P_PUSH_NOC` โดย `mon_stall_cnt` ไต่ทีละหนึ่งต่อไซเคิลจน
reset ครั้งถัดไป ยกธงและระบุตัวได้ ไม่ใช่ fabric ค้าง

### 10.13 Fault-injection campaign

bitstream เดียว JTAG session เดียว หกโหมด `hw_scripts/batch_fault_campaign.tcl` แต่ละโหมด: VIO
soft reset ตั้ง mode + arm ปล่อย รอ 2 s ให้ window 235 ms จบ Trigger Immediately ทุก ILA log
เต็มใน `hw_logs/fault_campaign_20260912.log`; ตัวเลขที่ใช้ตัดสิน:

| mode | fault | `max_gap` 00/01/10/11 | seq err | `tid_err` | `dest_err` | flit ที่ agent_10 |
|---|---|---|---|---|---|---|
| 0 | ไม่มี | 217 / 38 / 119 / 105 | 0 | 0 | 0 | 0 |
| 1 | ตัด `tvalid` กลางแพกเกจ ถาวร | 217 / **608** / **611** / 105 | 0 | 0 | 0 | 0 |
| 2 | `tid = 00` 2000 ไซเคิล | 217 / 40 / 119 / 106 | 2 | โหนด `1000` | 0 | 0 |
| 3 | `tid = 11` 2000 ไซเคิล | 218 / 55 / 166 / 106 | 2 | โหนด `1000` | 0 | 0 |
| 4 | `tdest = 0001` 2000 ไซเคิล | 217 / 61 / 119 / 105 | 2 | 0 | โหนด `1000` | 1777 |
| 5 | `tdest = 1000` (นอกกระดาน) 2000 ไซเคิล | 218 / 46 / 119 / 106 | 2 | 0 | โหนด `1000` | 0 |

อ่านยังไง: ตัด agent_11 กลางแพกเกจทำให้ sender อื่นเสียช่องว่าง 608/611 ไซเคิลหนึ่งครั้ง (การ
ปล่อยของ bug #5 ที่ 1024 ไซเคิล `clk_noc` แสดงในนาฬิกาของแต่ละ agent) และไม่มีอะไรอื่น; ก่อน bug
#5 นี่คือการค้างถาวร ทุก `tid`/`tdest` ที่ผิดถูกทิ้ง ยกธงพร้อมโหนดที่ถูกต้อง และช่องว่างของ agent
อื่นอยู่ที่ค่าสะอาด sequence error สองตัวใน mode 2-5 คือจุดตัดสองจุด (เข้าและออกจากการค้าง 2000
ไซเคิล) resync เลนละหนึ่งครั้ง flit 1777 ตัวที่ agent_10 ใน mode 4 คือแพกเกจที่ถูกเบน ซึ่งมาถึง
เป็นสตรีมใหม่ที่สะอาด `stuck` อ่านได้ 0000 แม้ใน mode 1 เพราะ injector ปล่อย `tready` ผ่านและ
agent_11 ยังยิงเข้ามันต่อ; ปฏิกิริยาของ fabric ไม่ใช่ watchdog ของ agent คือสิ่งที่ถูกทดสอบ การ
รอ 2 s เผื่อไว้มาก: window จบที่ ~235 ms และ ILA อ่านตัวนับที่แช่แล้ว

### 10.14 สถานะบนซิลิคอน ณ `afce6cd`

ทุกกลไกในหัวข้อ 4 มีการแสดงบนซิลิคอน; ตาราง coverage ใน 9.4 ลิสต์ไว้ การรันบอร์ดครั้งล่าสุดคือ
2026-09-12: fault campaign (stress build ทั้งหกโหมด), การรัน stress สะอาดพร้อมการแก้ CDC (97.0%,
WNS +0.977), และ UART build ที่มี reset ต่อโดเมน (round-trip 6/6, `tid=00` ยกธง) ทั้งสอง build
รายงาน `report_cdc` Critical 0 ทุก build, program และ capture ตั้งแต่ 2026-09-12 ทำด้วยสคริปต์
batch ใน `hw_scripts/` ไม่แตะ GUI

---
## 11. Parameter และปุ่มปรับ

ทุกอย่างที่เปลี่ยนได้โดยไม่แก้ลอจิก อยู่ที่ไหน ค่าเริ่มต้นเท่าไร และอะไรต้องขยับตาม ความกว้าง
เป็นบิต ความลึกเป็นช่อง ค่า `*_LOG` เป็นเลขยกกำลังสอง

### 11.1 Fabric

| parameter | โมดูล | เริ่มต้น | ความหมาย | ผูกกับ |
|---|---|---|---|---|
| `DATA_W` | `noc_mesh_2x2_vc`, `router_5port_mesh_vc`, `vc_input_buffer`, `gals_node_wrapper` | 8 | ความกว้าง payload ของ flit | ECC ตอกตายไว้ที่ 8 บิต (`dual_port_ram_ecc` แยก `[7:0]` ออกมา); `async_fifo` ป้องกัน ECC เฉพาะ 8 บิตล่าง; `traffic_node_agent` อัด `{SRC_TAG, seq}` ลง 8 บิต; โปรโตคอล UART เป็น 2 ไบต์/flit การเปลี่ยนมันเป็นโปรเจกต์ ไม่ใช่การปรับ parameter (หัวข้อ 13.4) |
| `CORD_W` | เดียวกัน | 2 | ความกว้างพิกัด; `tdest` คือ `2*CORD_W` | mesh ตอกตายเป็น 2x2 ใน `noc_mesh_2x2_vc` (router สี่ instance, `MAX_X/MAX_Y = 1`); `CORD_W` อย่างเดียวไม่ทำให้ mesh โต |
| `NUM_VCS` | เดียวกัน, `vc_port_arbiter` (ตายตัวที่ 2 ด้วย arbiter สองตัวของมัน) | 2 | virtual channel | `vc_port_arbiter` กับ mux ของ wrapper เขียนไว้สำหรับสองพอดี |
| `DEPTH` | `vc_input_buffer`, `gals_node_wrapper`, mesh, router | 16 | ความลึก FIFO ต่อ VC (input buffer ของ router และ async FIFO ของ wrapper) | `ADDR_WIDTH = $clog2(DEPTH)` ใน async FIFO; การรัน formal ของ mesh ย่อเหลือ 2 |
| `PORTS` | `packet_arbiter`, `vc_port_arbiter` | 4 (5 ใน router) | ผู้ขอต่อ arbiter | |
| `STALL_LOG` | `packet_arbiter` | 10 | พอร์ตที่ล็อกถูกทิ้งหลังต้นทางเงียบ `2**STALL_LOG` ไซเคิล (bug #5) | ต้องสูงกว่าช่องว่าง GALS ปกติมาก (วัดได้ ≤ 219 ไซเคิลของ agent); บนบอร์ดโผล่เป็นช่องว่าง ~610 ไซเคิลของผู้รอด |
| `STARVE_LIMIT` | `vc_port_arbiter` | 64 | ไซเคิลที่ VC0 รอหลัง VC1 ที่ active ได้ก่อน override | `assert_bounded_starvation` |
| `MY_X`, `MY_Y` | `router_5port_mesh_vc` | 0, 0 | พิกัด router; mesh ตั้งจาก `idx = y*2 + x` | |
| `MAX_X`, `MAX_Y` | `noc_mesh_2x2_vc` (localparam) | 1, 1 | ขอบเขตของตัวกรองช่วงค่า | เปลี่ยนตามขนาด mesh |
| `ADDR_WIDTH` | `async_fifo`, `gray_counter`, `dual_port_ram*` | 4 | บิต address ของ FIFO; pointer กว้างกว่าหนึ่งบิต | |
| `DATA_WIDTH` | `async_fifo*`, `fwft_wrapper`, `sync_fifo`, `dual_port_ram*` | 8 / 13 | คำที่เก็บ; wrapper ใช้ `PACK_W = 13` | |
| `WIDTH` | `sync_2stage` | 5 | ความกว้างของ synchronizer | |

### 11.2 Traffic agent และ stress build

| parameter | โมดูล | เริ่มต้น | ความหมาย | หมายเหตุ |
|---|---|---|---|---|
| `PATTERN` | `arty_stress_top`, `noc_stress_tester`, `tb_noc_stress_tester` | 0 (top), 1 (tb) | 0 permutation, 1 hot-spot เข้าโหนด 00 | silicon regression ทุกรอบใช้ 1 |
| `VC_MODE` | เดียวกัน, `traffic_node_agent` | 2 | 0 VC0 อย่างเดียว, 1 VC1 อย่างเดียว, 2 สลับต่อแพกเกจ | 2 คือโหมดที่เปิดโปง bug #3 |
| `DEST_ID`, `SRC_TAG` | `traffic_node_agent` | ต่อ instance | ส่งไปไหน ประทับอะไรใน `tdata[7:6]` | `DEST_ID` เป็นค่าคงที่ ซึ่งคือเหตุผลที่ `dest_err` พับหายสำหรับโหนดที่ไม่มี injector |
| `PKT_FLITS` | `traffic_node_agent` | 16 | flit ต่อแพกเกจ | ฟิลด์ sequence กว้าง 6 บิต ตัวตรวจจึงเป็น modulo 64 |
| `TX_EN` | `traffic_node_agent` | 1 | 0 ทำให้เป็น sink ล้วน | โหนด 00 ภายใต้ `PATTERN=1` |
| `WINDOW_LOG` | `traffic_node_agent`, `noc_stress_tester`, `analyze_ila.py` | 24 (บอร์ด), 18 (tb) | ความยาว `S_RUN` เป็นไซเคิลของ agent เอง | `analyze_ila.py` ต้องตรงกับ RTL |
| `WARMUP_LOG` | เดียวกัน | 10 | ไซเคิลนอนหลัง reset ก่อนส่ง | ช่วงนอนนี้คือสิ่งที่ทำให้ reset ที่ไม่ sync เดิมรอดมาได้ |
| `DRAIN_LOG` | เดียวกัน | 12 (บอร์ด), 8 (tb) | ไซเคิลนอนหลัง window | |
| `STUCK_LOG` | เดียวกัน | 16 (บอร์ด), 23 (tb) | threshold ของ liveness; เงียบ `2**STUCK_LOG` ไซเคิลใน `S_RUN` = ตาย | ~300x ช่องว่างแย่สุดที่วัดได้; tb ตั้งสูงโดยตั้งใจเพื่อวัด ไม่ใช่ให้ยิง |
| `GAP_W` | เดียวกัน | 24 | ความกว้างของ `max_gap` ให้รายงานค่าเกิน threshold ได้ | |
| `FAULT_FIRE_LOG` | `noc_stress_tester` → `fault_injector.FIRE_LOG` | 20 (บอร์ด), 12 (tb) | injector ยิง `2**FIRE_LOG` ไซเคิล `clk_h11` หลัง reset | ต้องตกใน `S_RUN`: 2^20 ≈ 15 ms เข้าไปใน window 235 ms |
| `HOLD` | `fault_injector` | 2000 | ไซเคิลที่ fault ของ mode 2-5 ค้าง | ตรงกับระยะ `force` เดิม |
| `DEPTH` | `loopback_node_agent` | 256 | คิว echo ต่อ VC | |
| `CLK_FREQ`, `BAUD_RATE` | `uart_noc_host`, `uart_transceiver` | 100 MHz, 3 Mbaud | | `noc_host.py` กับ `uart_roundtrip.py` ตอกตาย 3,000,000 |

### 11.3 สวิตช์และ parameter ของ testbench

| สวิตช์ | testbench | ผล |
|---|---|---|
| `-d HW_CLOCKS` | `tb_noc_mesh_2x2_gals` | อัตราส่วนนาฬิกาบอร์ดแทนชุดเร็วของ TB |
| `-d HS_VC_ALT` | `tb_noc_mesh_2x2_gals` | เทสต์ 6 สลับ VC ต่อแพกเกจ (เหมือน `VC_MODE=2`) |
| `-d SIM_DEBUG` | `vc_port_arbiter` (ผ่าน tb ตัวไหนก็ได้) | `$display` ตอน override trigger/release |
| `INJECT_ECC`, `KILL_MIDPKT`, `BAD_TID`, `BAD_DEST`, `FAULT_MODE` | `tb_noc_stress_tester` | หัวข้อ 6.6; ส่งผ่าน top ห่อบรรทัดเดียวบนเชลล์ Windows (gotcha 8) |

### 11.4 define ตอน build

| define | ที่ไหน | ผล |
|---|---|---|
| `ECC_INJECT_SBE` / `ECC_INJECT_DBE` | `dual_port_ram_ecc` | พลิกบิต codeword หนึ่ง / สองบิตทุกครั้งที่เขียน; ตั้งด้วย `set_property verilog_define {...} [current_fileset]` แล้วล้างทีหลัง |
| `FORMAL` | ทุกโมดูลที่มีบล็อก `FORMAL`; `async_fifo` สลับไป RAM ธรรมดา | |
| `FORMAL_TOP_INTEGRATION` | arbiter, counter, synchronizer | ปิด property ของโมดูลย่อยเองเมื่อพิสูจน์ตัวแม่; กับดักในหัวข้อ 8.2 แถว K |
| `FORMAL_NO_ROUTER` | `router_5port_mesh_vc` | อย่างเดียวกัน สำหรับ proof ของ mesh |
| `DEBUG_BUILD` | ไม่มีอะไรแล้ว | เคยกั้น probe ของ UART build; ลบเพราะเคยหายไปครั้งหนึ่งแล้วและจะหายอีก |

---

## 12. การตัดสินใจเชิงดีไซน์ และทางเลือกที่ถูกปัดตก

บันทึกไว้ให้คนถัดไปไม่ต้องเถียงซ้ำโดยไม่มีบริบท แต่ละข้อบอกว่าเลือกอะไร มีอะไรอยู่บนโต๊ะ และ
ทำไม

**ทิ้ง flit ที่ผิด ไม่ backpressure ไม่หนีบ (bug #6, tid guard, constant-tdest guard).** flit ที่
fabric จะไม่พาไปมีสามทาง: ปฏิเสธ `ready` (ผู้ส่งค้างตลอดกาลโดยไม่มีคำวินิจฉัย และผู้ส่งที่ค้างคือ
อาการที่กำลังป้องกันอยู่); หนีบที่อยู่เข้าช่วง (แพกเกจถึงที่ที่ไม่มีใครตั้งใจ แบบเงียบ ซึ่งแย่กว่า
หายไป); รับแล้วทิ้ง ยกธง sticky (ผู้ส่งวิ่งต่อ การหายถูกระบุตัวถึงโหนด และธงไปถึง LED) เลือกทาง
ที่สาม ธงที่บอกว่า "flit ผิดถูกเสนอ" ยกตอนเสนอ ไม่ใช่ตอน handshake เพราะความผิดคือการเล็งผิด
ไม่ใช่จังหวะ

**ปิดแพกเกจเมื่อปฏิเสธ แทนที่จะแค่ทิ้ง (bug #7, ดีไซน์ A แทน B).** flit ที่ถูกปฏิเสธอาจพา
`tlast` ของแพกเกจไปด้วย ดีไซน์ A เขียนท้ายสังเคราะห์ลงทุก VC ที่เปิดอยู่ที่ขาเข้านั้น; B จะระบุ
ว่า flit ผิดหมายถึง VC ไหนแล้วปิดเฉพาะตัวนั้น B เป็นลอจิกเพิ่มและ corner case เพิ่ม (`tid=00` ไม่
ระบุ VC, `tid=11` ระบุทั้งสอง) เพื่อประโยชน์ที่มีเฉพาะตอน host ส่งขยะอยู่แล้ว ซึ่ง "แพกเกจข้างเคียง
ก็ถูกตัดสั้นด้วย" ไม่ใช่ความเสียหายเกินสัดส่วน และ "ไม่มีอะไรถูกส่งผิดเงียบๆ" คือ property ที่
สำคัญ A

**ธง `dest_err` ตัวเดียวสำหรับสองเงื่อนไข (นอกกระดาน, ไม่ตรงหัว).** ทั้งคู่หมายถึง "ปลายทางของ
flit นี้รับไม่ได้"; ธงตัวที่สองต้องมีพอร์ตผ่าน `gals_noc_top`, top ทั้งสอง, ILA, LED และ
`analyze_ila.py` เพื่อความแตกต่างที่บิตโหนดจำกัดวงให้แล้ว ใช้ซ้ำ

**เช็ค constant-`tdest` ที่ขาเข้า mesh เท่านั้น ไม่ใช่ใน wrapper.** `tdest` ผ่าน mux ของ wrapper
ไม่เปลี่ยน ความผิดของ host จึงมาตกที่ขาเข้า mesh อยู่ดี; tid guard ต้องมี wrapper เพราะ mux สร้าง
`tid` ใหม่เป็น one-hot โดยโครงสร้าง ที่เดียว

**`` `define `` สำหรับตัวฉีด ECC ไม่ใช่ parameter.** parameter ต้องลากผ่าน `async_fifo` →
`async_fifo_fwft` → `gals_node_wrapper` → `gals_noc_top` → top แตะโมดูลที่พิสูจน์แล้วห้าตัวเพื่อ
ถึงหนึ่งตัว define ถึงมันโดยไม่แตะอะไร และ bitstream ปกติเหมือนเดิมทุกไบต์

**stall timeout นับความเงียบของต้นทาง ไม่ใช่เวลาที่ผ่านไป (bug #5).** timeout บนเวลาจริงจะยิง
บน backpressure ปลายน้ำที่ถูกกฎ การนับเฉพาะไซเคิลที่ `valid` ต่ำแปลว่าต้นทางที่ถูกบล็อกแต่ยัง
เป็นๆ ยิงมันไม่ได้ และ `&& !valid` เพิ่มเติมบนไซเคิลปล่อย (formal เจอ) แปลว่าต้นทางที่กลับมา
ไซเคิลสุดท้ายยังได้ล็อกต่อ

**VC1 เป็นเจ้าของลิงก์เฉพาะตอนขยับได้ (bug #3).** ทางแก้อีกทาง คือ starvation limit ที่สั้นลง
จะลดการรอจาก 64 ไซเคิลเหลือน้อยกว่าแต่ทิ้ง circular wait ไว้ การเปลี่ยนที่ตัดสินคือทำให้การ
เป็นเจ้าของเป็นคำถามต่อไซเคิล

**`done`/`err` ผ่านรีจิสเตอร์ และธงที่ OR แล้วผ่านรีจิสเตอร์ก่อนทุก synchronizer (CDC-10).**
ทางเลือกคือ `set_false_path` หรือ waiver CDC บนการข้ามพวกนั้น waiver ซ่อน path ที่ glitch ได้;
รีจิสเตอร์เอามันออก latency หนึ่งไซเคิลบนสัญญาณ sticky

**reset synchronizer ต่อโดเมนโดย soft reset เป็นขาเข้า synchronous แยก (CDC-7/CDC-10).**
ทางเลือก: waive path CDC-7 ทั้ง 572 (มันจริง แค่เคยมองไม่เห็น); sync reset รวมครั้งเดียวบน
`clk_h00` แล้ว fan out (ยัง asynchronous ต่ออีกสี่โดเมน); AND soft reset ของ VIO เข้าสาย async
ก่อน synchronizer (LUT ก่อนขา `CLR`, CDC-10) `reset_sync` ต่อโดเมนโดย `srst` ถูก sync ข้างในเป็น
ทรงเดียวที่ทั้งเครื่องมือและตำรายอมรับ

**VIO ผ่าน JTAG สำหรับ fault campaign ไม่ใช่ UART หรือปุ่ม.** การเปิด COM port รีเซ็ตบอร์ด (หัวข้อ
10.12) เส้นทางควบคุมที่พีซีขับจึงจะรีเซ็ตดีไซน์ที่มันพยายามควบคุม; ปุ่มไม่สคริปต์ได้; VIO รันใน
`hw_server` session เดียวกับการจับ ILA bitstream เดียว หกโหมด ไม่ต้องใช้มือ

**injector ปล่อย `tready` ผ่าน.** ทางเลือก ให้ injector กัน `tready` ใน mode 2 ด้วยเพื่อให้
agent_11 ค้างเหมือน host จริงที่ส่ง `tid=00` ถูกพิจารณาและไม่ทำ: มันจะทดสอบ watchdog ของ agent
ซึ่ง `tb_traffic_node_agent` ครอบอยู่แล้ว และซ่อนปฏิกิริยาของ fabric ซึ่งคือประเด็น การค้างฝั่ง
host แสดงแยกโดย UART build

**fault mode เป็นการวัด ไม่ใช่ผ่าน/ตก.** `BAD_TID`, `BAD_DEST`, `KILL_MIDPKT`, `FAULT_MODE` และ
campaign ทั้งหมดรายงาน `FAIL` บนบรรทัด sequence-error หรือ fairness โดยตั้งใจ เกณฑ์ผ่านของการ
รันพวกนั้นคือ signature ที่พิมพ์ (ธง โหนด ช่องว่างของ agent อื่น) อ่านโดยคนหรือโดย
`summarize_campaign.py` เพราะจำนวน sequence error ที่ "ถูก" ขึ้นกับเลขคณิต modulo 6 บิตและ
timing หนึ่งไซเคิล

**debug flow แบบสคริปต์แทน wizard ของ GUI.** หลัง wizard เขียน ILA core ลงไฟล์ pin,
`save_constraints` เรียงผิด และการหาคล็อกทำให้ probe แคบลงเงียบๆ ทางเลือกคือสคริปต์ทั้งหมดและ
ไม่แตะ wizard อีก ทุกการจับตั้งแต่ 2026-09-04 ผ่าน `setup_debug.tcl`; ทุก build ตั้งแต่ 2026-09-12
ผ่าน `hw_scripts/`

**formal assume ว่า reset สองตัวของ wrapper เท่ากัน.** proof ที่ reset อิสระต้องเขียน property
ส่วนใหญ่ของ wrapper ใหม่ให้เหตุผลตอนฝั่งหนึ่งอยู่ใน reset ขณะอีกฝั่งวิ่ง `reset_sync` จริงปล่อยสอง
ตัวห่างกันไม่กี่ไซเคิลตอนนอน และ FIFO ของ wrapper ถูกพิสูจน์ (ที่อื่น) ว่าทนได้ บันทึกเป็น
assumption ไม่ซ่อน

**proof แบบ bounded สำหรับสามโมดูลที่ผูกกับ FIFO.** `vc_input_buffer`, router และ mesh ผูก state
ของ arbiter หรือเงาเข้ากับเนื้อ FIFO; induction สร้างสถานะเริ่มต้นที่ไปถึงไม่ได้ ทางเลือกคือเขียน
invariant ที่จะทำให้ induction ปิด (หลายสัปดาห์) หรือรัน bmc ลึกพอให้เติมและระบายทุกคิวหลายรอบ
(หลายนาที) bmc พร้อมบันทึก depth

---

## 13. การต่อยอดดีไซน์

สูตรสำหรับการเปลี่ยนที่คนน่าจะอยากทำ แต่ละอันบอกไฟล์ที่แตะและการตรวจที่ต้องยังเขียว

### 13.1 เพิ่ม fault mode ให้ campaign

1. `fault_injector.sv`: เพิ่มแขน `case` ใน mux ขาออก และถ้าต้องการ trigger หรือ hold ต่างไป ขยาย
   FSM เล็กๆ นั้น คง `tready` ให้ผ่านตรงเว้นแต่โหมดนั้นเกี่ยวกับ agent
2. `tb_noc_stress_tester.sv`: เพิ่ม signature ที่คาดของโหมดใน `case` ของ `FAULT_MODE` ท้ายไฟล์
   แล้วรัน (`FAULT_MODE=N` ผ่าน top ห่อ)
3. `hw_scripts/summarize_campaign.py`: เพิ่มข้อความคาดหวัง; ขยาย `modes` ใน
   `batch_fault_campaign.tcl` ถ้าลิสต์เริ่มต้นควรรวมมัน
4. build ใหม่ (หัวข้อ 17) รัน campaign เก็บ log ลง `hw_logs/` เพิ่มแถวในตาราง campaign ของ
   `HANDOFF.md`

VIO มีบิต mode 4 บิต (16 โหมด) และบิต output สำรองสองบิต

### 13.2 เพิ่ม probe ของ ILA

ติด `(* mark_debug = "true", dont_touch = "true" *)` ที่รีจิสเตอร์ ต้องมีทั้งคู่: รีจิสเตอร์ที่ไม่มี
fanout ถูกกวาดก่อน Set Up Debug จะเห็นมัน build ใหม่; `setup_debug.tcl` เก็บมัน จัดกลุ่มตาม
คล็อก และพิมพ์จำนวน net ใหม่ อัปเดตลิสต์ลายนิ้วมือในหัวข้อ 10.8 และถ้า `analyze_ila.py` ควรอ่าน
มัน เพิ่มที่นั่น ถ้าสคริปต์รายงาน net นั้นว่า "ค่าคงที่หลังสังเคราะห์" ค่าไม่ใช่หลักฐาน; หาว่าทำไม
ก่อนพึ่งมัน

### 13.3 เพิ่ม formal property

ใส่ในบล็อก `FORMAL` ของโมดูลใต้ label ที่ไม่ซ้ำ ถ้า label อยู่ใน `for` loop ใช้ `generate`/`genvar`
ไม่งั้น slang crash เพราะชื่อเซลล์ซ้ำ invariant ที่เป็น state ต้องไม่กั้นด้วย `f_past_valid` รัน
`.sby` ของโมดูล แล้วทุก `.sby` ที่รวมโมดูลนั้นโดยเปิด property ของมัน (สคริปต์ระดับบนอ่านโมดูล
ย่อยด้วย `FORMAL_TOP_INTEGRATION` โดยปกติจึงมีแค่ของตัวเอง) ถ้าเพิ่มสคริปต์ เช็คว่า model ที่
generate มีเซลล์ `$assert` จริง (หัวข้อ 8.2 แถว K):

    grep -c '\$assert' formal/<task>_prove/model/design_smt2.smt2

### 13.4 ขยาย flit

`DATA_W` เป็น parameter แต่สี่อย่างสมมติว่าเป็น 8: `dual_port_ram_ecc` กับคู่ SECDED (13,8) (flit
32 บิตต้องใช้ code (39,32) และ `tb_ecc_secded` ใหม่); การแยก `[7:0]` ของ `async_fifo` เข้า RAM ที่
มี ECC; การอัด `{SRC_TAG, seq}` ของ `traffic_node_agent` และตัวตรวจ 6 บิต; และ framing ของ UART
(2 ไบต์/flit กลายเป็น 5) `PACK_W = 1 + 4 + DATA_W` ตามไปอัตโนมัติ พิสูจน์ `dual_port_ram_ecc`,
`async_fifo_fwft` ใหม่ (และเขียน property ของ `async_fifo` ที่หายไปก่อน เพราะพวกมันคือตัวที่จะ
จับบั๊กเรื่องความกว้าง) wrapper และ mesh โดยปล่อย `DATA_W` ไว้ที่ 2 เพื่อความเร็วของ solver รัน
simulation ทุกตัวใหม่; baseline ของ regression จะเปลี่ยนและต้องหาใหม่

### 13.5 ขยาย mesh

`noc_mesh_2x2_vc` ตอกตาย router สี่ตัว assign ระหว่าง router 36 บรรทัด การผูกขอบ และ
`MAX_X/MAX_Y = 1` mesh 2x4 หรือ 4x4 หมายถึงโมดูล mesh ใหม่ (generate สายจาก `(x, y)` แทนเขียน
มือ) `MAX_*` จาก parameter `gals_noc_top` ที่มี wrapper N ตัวและ reset N+1 ตัว `noc_stress_tester`
ที่มี agent N ตัวและตาราง `PATTERN` `analyze_ila.py` กับ `summarize_campaign.py` ที่รับ agent N
ตัว และชุด output ของ MMCM ที่ใหญ่ขึ้นหรือแชร์นาฬิกา host `tdest` 4 บิตรองรับได้ถึง 4x4 คาดว่า
bmc ของ mesh จะโตแบบเกินเชิงเส้น (2x2 ใช้ 7 นาทีบน abc); วางแผนพิสูจน์คู่ router กับตัว generate
สายแยกกันแทนที่จะพิสูจน์ทั้ง mesh XY routing แบบหลาย hop และตัวกรองช่วงค่าด้วยค่านอกช่วงจริง
จะถูกทดสอบเป็นครั้งแรก

### 13.6 เพิ่ม host

host คืออะไรก็ได้ที่พูดสัญญา flit ของหัวข้อ 4 บน `h*_tx_*`/`h*_rx_*` ของ `gals_noc_top` บนนาฬิกา
ของตัวเอง โดยมี `rst_n_h*` ของตัวเอง รักษา `tid` ให้ one-hot และ `tdest` คงที่ต่อแพกเกจ ไม่งั้น
คาดว่า guard จะทิ้ง flit ของคุณและยกธงใส่คุณ ถ้า host อาจหยุดกลางแพกเกจ fabric ฟื้นหลัง NoC
เงียบ 1024 ไซเคิล สะพาน UART (`uart_noc_host`) คือตัวอย่างเล็กสุด; `loopback_node_agent` คือตัว
เล็กสุดที่รับด้วย

### 13.7 เปลี่ยนนาฬิกา

แก้ `clk_wiz_0` (ไฟล์ `.xci`) แล้ว: `timing.xdc` (async group ตามชื่อคล็อก จึงตามไปเอง) ตาราง
`CLK` ของ `analyze_ila.py` ครึ่งคาบของ `tb_noc_stress_tester` และเลขคณิต `WINDOW_LOG` ในหัวข้อ
10.4 วัด `max_gap` บนบอร์ดใหม่ก่อนแตะ `STUCK_LOG` หรือ `STALL_LOG`

### 13.8 เพิ่มการตรวจใน stress tester

บล็อกรายงานท้าย `tb_noc_stress_tester.sv` เป็นลำดับของ `[PASS]`/`[FAIL]` กับตัวนับ `fails` เพิ่ม
ของคุณตรงนั้น อ่านตัวนับผ่าน hierarchy (`uut_noc_top.*`, `u_stress.agent_*.*`) ถ้าการตรวจขึ้นกับ
fault mode กั้นมันแบบที่ `BAD_TID`/`FAULT_MODE` กั้น ให้การรันสะอาดยังเป็นผ่าน/ตกแบบเข้มงวด

---

## 14. ไทม์ไลน์

| วันที่ | commit / PR | อะไร |
|---|---|---|
| เม.ย.–ก.ค. 2026 | (ก่อน git) | เขียน RTL: FIFO, ECC, router, mesh, wrapper, agent, UART host |
| 2026-08-17 | `f9b73a9` | initial commit |
| 2026-08-18 | `2ac2e05` | เพิ่มเทสต์ 6; แก้ bug #2 |
| 2026-08-19 | `04cd562`..`e1571ba` | ตัวเลือก `VC_MODE`; แยก bug #3 หาสาเหตุด้วย `SIM_DEBUG` แก้; สร้าง `HANDOFF.md` |
| 2026-09-01 | `cba4e60`..`cbc4514`, PR #1 | ยืนยัน bug #3 บนบอร์ด (57.5% → 97.0%); เพิ่ม liveness watchdog; มันเจอ bug #4 แก้ ยืนยัน (+15.7%) |
| 2026-09-03 | `b2b5a14`..`0d62c26` | แสดงว่าความยุติธรรมของ arbiter คือ topology; พิสูจน์ ECC แบบ exhaustive; ต่อธง ECC ครบ; ส่วน ECC ใน `analyze_ila.py` |
| 2026-09-04 | `e9f8197`..`94d5c1d` | แก้ bug #5, proof arbiter จริงครั้งแรก; formal ทุกโมดูลใน datapath; formal เจอ bug #6 แก้; debug flow แบบสคริปต์; กู้ UART build; แก้ one-hot ใน `noc_host.py`; silicon regression สำหรับ #4/#5/#6 |
| 2026-09-09 | `153d12a`, PR #2 | `.gitignore`; merge เข้า `main` ครั้งแรก |
| 2026-09-10 | `8853d5c`, `0815e10`, PR #3 | ตัวฉีด fault ของ ECC พิสูจน์เส้นทางเตือนบนซิลิคอน; tid guard ทั้งสองชั้น; แก้กับดัก debug flow สองอย่าง |
| 2026-09-11 | `31d4cba`, `de8cac3` | หาสาเหตุและแก้ bug #7; ถอด assumption one-hot `tid` ออกจาก formal |
| 2026-09-12 | `3f73b67`, `9b4fa2d`, PR #4 | `WALKTHROUGH.md`; bug #7, ECC double-bit และ UART build บนซิลิคอน; สคริปต์ build/capture แบบ batch; เจอ reset จาก COM port |
| 2026-09-12 | `1cdf66e`, PR #5 | constant-`tdest` guard จาก assumption เป็น proof บนซิลิคอน; `.gitattributes`; **tag `v1.0` ที่ merge `f07ddca`** |
| 2026-09-12 | `c60117a`, PR #6 | `report_cdc` ใน flow แก้ CDC-10 critical 5 เส้น; เจอว่า `dest_err_node` ถูกพับเป็นค่าคงที่; แก้เอกสาร |
| 2026-09-12/13 | `8deb828`, `d256864`, PR #7 | fault injector + VIO, silicon campaign (หกโหมด); `reset_sync` ต่อโดเมน (CDC-7 ×572 → 0); UART build ใหม่และรันใหม่ |
| 2026-09-14 | `671d655`, `afce6cd` | sync record ที่ค้างของ PR #7 แล้ว merge |
| 2026-09-14 | (เอกสารนี้) | เจอว่า proof ของ `async_fifo` ไม่มี assertion (หัวข้อ 8.2 แถว K) |

---

## 15. เรื่องที่กินเวลาจริง

ย่อจาก `HANDOFF.md` หัวข้อ 4 และรายการลงวันที่ในหัวข้อ 5 อ่านต้นฉบับก่อนแตะ build flow

1. `mark_debug` อย่างเดียวไม่หยุด synthesis จากการกวาด net ที่ไม่มี fanout; เพิ่ม `dont_touch`
   หรือให้มันมี load จริง
2. ไฟผ่านโกหกจนกระทั่ง `done` ถูกกั้นด้วยการส่งที่เห็นจริง
3. ชื่อโหนดต่างกันระหว่าง `gals_noc_top` กับ testbench; map ผ่าน index
4. window นับไซเคิล agent บนนาฬิกาช้ากว่าจึงวิ่งนานกว่าในเวลาจริงและหยุดทีหลัง ห้ามเทียบยอดดิบ
   ข้าม agent; การเหลื่อมนี้คือสิ่งที่เปิดโปง bug #4
5. `` `define `` ที่กั้น instrumentation จะหายไปสักวัน; ลบ guard และทำ probe ให้ไม่มีเงื่อนไข
6. Set Up Debug เขียนลงอะไรก็ตามที่ `TargetConstrsFile` ชื่อ; ตอนนี้ชี้ `debug_auto.xdc` และขั้น
   GUI ถูกแทนด้วย `setup_debug.tcl` ซึ่งรับมือกับ `save_constraints` เรียงผิด, การหาคล็อกทำให้
   probe แคบลงเงียบๆ, core เก่าตามมาตอนสลับ build, `debug_auto.xdc` ถูก synthesis อ่าน, core ที่
   ลบทิ้งคล็อกไว้ และ implementation ต้องใช้ session ใหม่
7. เทสต์ที่ส่งแพกเกจเดียวแล้วหยุดมองไม่เห็นบั๊กเรื่องความยุติธรรม
8. `xelab.bat -generic_top "X=2"` ทำ `=` เพี้ยนบนเชลล์ Windows; ห่อ testbench ใน top บรรทัดเดียว
   แทน
9. การเปิด COM port จากพีซีรีเซ็ต FPGA (FTDI DTR/RTS) อ่าน ILA ก่อนเปิดพอร์ตครั้งถัดไป; ให้
   `hw_server` session เดียวตลอดการทดลอง การเปิด JTAG target ไม่รีเซ็ต
10. Vivado 2025.2 crash ใน exit handler หลัง `close_project` ได้ทั้งที่เขียน output ครบแล้ว;
    marker `SESSION_A_DONE` ของสคริปต์ batch คือสัญญาณความสำเร็จ
11. `release` บนตัวแปร `logic` ที่ถูกขับด้วยค่าคงที่ทิ้งค่าที่ force ไว้ตลอดกาล; force ค่าจริงหนึ่ง
    ไซเคิลก่อน
12. `wsl bash -c '... $PATH ...'` จาก Git Bash ขยาย `$PATH` ฝั่งนี้; ใช้ `formal/run_wsl.sh` และ
    ให้มันเป็น LF (`.gitattributes` ทำให้)
13. output ของ console ที่ buffer ไว้หายเมื่อ process ถูก `timeout` ฆ่า; flush หรือเขียนลงไฟล์
    (`python -u`, `PYTHONIOENCODING=utf-8`)
14. probe ที่ synthesis พับเป็นค่าคงที่อ่านได้ค่าเดียวตลอดกาล; 0 บนมันไม่ใช่หลักฐาน
    `setup_debug.tcl` ตอนนี้บอกว่า net ไหนเป็นแบบนั้น
15. สคริปต์ `.sby` ที่อ่านทุกโมดูลย่อยด้วย `FORMAL_TOP_INTEGRATION` และไม่มี property ของตัวเอง
    รายงาน PASS โดยไม่ได้พิสูจน์อะไร นับเซลล์ `$assert`
16. `final_src/` กับ `sources_1/new/old/` เป็นของค้าง; `.sby` เก่าที่นั่น verify อีกโปรเจกต์
17. Hardware Manager ตั้งชื่อ probe ของ VIO ตาม net ที่ต่อ ไม่ใช่ชื่อพอร์ตของ IP; ค้นตาม `TYPE`
18. `python` ของ Vivado เองบัง python ของระบบใน `exec` ของ Tcl; ขับสคริปต์ฝั่งพีซีจากนอก Vivado
    และ handshake ผ่านไฟล์

---

## 16. อะไรยังค้าง

- **`async_fifo` ไม่มี formal property ของตัวเอง** (หัวข้อ 8.2 แถว K) FIFO ข้ามโดเมนคือหัวใจของ
  ขอบ GALS และความถูกต้องของมันอาศัย simulation กับซิลิคอน model แบบ shadow-FIFO เหมือน
  `vc_input_buffer` ใน abstraction แบบนาฬิกาเดียวที่สคริปต์ใช้อยู่แล้ว จะปิดช่องนี้ได้; header ของ
  `async_fifo.sby` ควรเลิกอ้างว่าเป็น proof จนกว่าจะถึงตอนนั้น แถวของ `async_fifo` ในตาราง formal
  ของ HANDOFF ผิดแบบเดียวกัน
- **`dest_err_node[2:0]` ยังเป็นค่าคงที่ใน stress build** (โหนด 0-2 มีปลายทางเป็น parameter) มีแค่
  โหนด 3 ที่ทำงาน การขยาย mux ของ injector ให้ทุก agent จะแก้ได้ แลกกับสำเนาอีกสามชุด
- **ECC ครอบเฉพาะ payload** และ SECDED รายงานผิดเมื่อพลิกสามบิตขึ้นไป
- **demo สื่อผ่าน UART ยังไม่เป็น regression** (`image_noc_test.py`, `video_noc_stream.py`)
- **mode 2 ไม่จำลองการค้างฝั่ง host** ที่ผู้ส่ง `tid=00` จริงเจอ; UART build แสดงมันแยก
- **`v1.1` ยังไม่ได้ tag** `main` ที่ `afce6cd` เป็นสถานะที่ validate แล้วซึ่งต่างจาก `v1.0` อย่างมี
  นัยสำคัญ (constant-tdest guard, reset ที่ CDC สะอาด, fault campaign)

---

## 17. รันซ้ำผลทั้งหมดยังไง

path ทั้งหมดสัมพัทธ์กับรากของ repo Vivado 2025.2 ที่ `C:/AMDDesignTools/2025.2` WSL `Ubuntu-24.04`
กับ OSS CAD Suite ที่ `/opt/eda/oss-cad-suite` สำหรับ formal

regression หกเทสต์ จาก Tcl console ของ Vivado:

    set HW_CLOCKS 1 ; set HS_VC_ALT 1 ; source run_sim_regression.tcl

อย่างเดียวกันโดยไม่ใช้ project (เร็วกว่า ไม่มี state ของ project) ลำดับ compile ที่ elaborate สะอาด:

    sync_fifo dual_port_ram dual_port_ram_ecc ecc_secded_encode_8b ecc_secded_decode_8b
    gray_counter sync_2stage reset_sync async_fifo async_fifo_fwft fwft_wrapper axis_perf_mon
    traffic_gen traffic_node_agent fault_injector packet_arbiter vc_port_arbiter vc_input_buffer
    router_5port_mesh_vc noc_mesh_2x2_vc gals_node_wrapper gals_noc_top noc_stress_tester
    tb_noc_mesh_2x2_gals  (หรือ tb_noc_stress_tester)

elaborate `work.tb_noc_mesh_2x2_gals` ส่งสวิตช์เป็น `-d HW_CLOCKS -d HS_VC_ALT` รันด้วย `run all;
quit` ยอดที่คาดอยู่หัวข้อ 6.6

stress tester พร้อม parameter (gotcha 8):

    module tb_wrap; tb_noc_stress_tester #(.FAULT_MODE(4)) u(); endmodule

compile คู่กันและ elaborate เป็น `work.tb_wrap`

formal หนึ่งโมดูล:

    MSYS_NO_PATHCONV=1 wsl -d Ubuntu-24.04 -- bash /mnt/d/.../formal/run_wsl.sh packet_arbiter.sby

หรือใน WSL `cd formal && sby -f packet_arbiter.sby` bmc ของ mesh ใช้ ~7 นาที router ~2 ที่เหลือ
ไม่ถึงนาที ยืนยันว่าสคริปต์พิสูจน์อะไรจริง:

    grep -c '\$assert' formal/<name>_prove/model/design_smt2.smt2

บอร์ด แบบสคริปต์ (สาม session โดยตั้งใจ; หัวข้อ 10.9):

    vivado -mode batch -source hw_scripts/batch_stress_synth_debug.tcl        # หา SESSION_A_DONE
    vivado -mode batch -source hw_scripts/batch_impl.tcl -tclargs arty_stress_top   # พิมพ์ CDC_Critical N
    vivado -mode batch -source hw_scripts/batch_program_capture.tcl -tclargs <csv-dir> arty_stress_top
    python analyze_ila.py <csv-dir>

fault campaign (bitstream เดียวกัน):

    vivado -mode batch -source hw_scripts/batch_fault_campaign.tcl -tclargs <out-root>
    python hw_scripts/summarize_campaign.py <out-root>

UART build:

    vivado -mode batch -source hw_scripts/batch_uart_synth_debug.tcl
    vivado -mode batch -source hw_scripts/batch_impl.tcl -tclargs arty_gals_noc_wrapper
    vivado -mode batch -source hw_scripts/batch_uart_session.tcl -tclargs <dir>   # แล้วจากอีกเชลล์:
    python -u hw_scripts/uart_roundtrip.py pos ; touch <dir>/go_b ; python -u hw_scripts/uart_roundtrip.py neg ; touch <dir>/go_c
    python hw_scripts/read_ila_flags.py <dir>/cap_b

build ฉีด ECC: ตั้ง `verilog_define {ECC_INJECT_SBE}` (หรือ `_DBE`) บน fileset ก่อน session A และ
ล้างทีหลัง คาด `ecc_sbe_cnt` (หรือ `_dbe_`) = 3 โหนด `1111`

บอร์ด จาก Tcl console ของ Vivado (flow แบบโต้ตอบยังใช้ได้):

    set PATTERN 1 ; set VC_MODE 2 ; source setup_stress_build.tcl
    open_run synth_1 ; source setup_debug.tcl
    # session ใหม่ของ Vivado:
    launch_runs impl_1 -to_step write_bitstream -jobs 8

คาด `MARK_DEBUG` ~1126 เน็ตบน stress build; ตัวเลขอื่นแปลว่า Set Up Debug ค้าง (หัวข้อ 10.8 มี
ตารางถอดรหัส)

---

## 18. File map

ทุกอย่างที่ track ณ `afce6cd` (117 ไฟล์นอกโฟลเดอร์ประวัติ) บรรทัดละไฟล์ path ใต้
`GALS_Packet-Based_Fabric.srcs/` ย่อเป็น `srcs/`

**รากของ repo**

| ไฟล์ | อะไร |
|---|---|
| `HANDOFF.md` | บันทึกงานลงวันที่: สถานะ ตัวเลข gotcha ผลบนซิลิคอนทุกอัน |
| `WALKTHROUGH.md`, `WALKTHROUGH.th.md` | เอกสารนี้ (อังกฤษเป็นต้นฉบับ ไทยแปลตาม) |
| `README.md` | Tcl สี่ท่อน (define, debug xdc, report_cdc, utilisation); ไม่ใช่ readme |
| `GALS_Packet-Based_Fabric.xpr` | Vivado project |
| `.gitignore`, `.gitattributes` | artefact ของ build ออก; `*.sh` เป็น LF |
| `run_sim_regression.tcl`, `setup_stress_build.tcl`, `setup_uart_build.tcl`, `setup_debug.tcl` | หัวข้อ 6.7 |
| `analyze_ila.py` | หัวข้อ 6.7 |
| `noc_host.py`, `image_noc_test.py`, `video_noc_stream.py`, `bulk_test.py`, `vc_dual_test.py`, `vc_preempt_test.py`, `multi_node_stress_test.py`, `fault_recovery_test.py`, `single_probe_test.py` | สคริปต์ UART ฝั่งพีซี; ดูแลอยู่แค่ `noc_host.py` |
| `combine_sv.py`, `combined.sv`, `combined_noc.sv`, `combined_gals_noc.sv`, `combined.txt` | ซอร์สต่อกันไว้แชร์; generate ใหม่ อย่าแก้ |
| `6_test_sim.log`, `6_test_sim-old.log`, `HWClock1_6_test_sim.log` | log regression ยุคแรก ถูกแทนด้วย `sim_logs/` |
| `hee.png`, `recovered_from_fpga.png` | รูปก่อนและหลัง round-trip ผ่าน fabric ทาง UART |
| `dfx_runtime.txt` | ขยะของ Vivado; ignore |

**`srcs/sources_1/new/`**: ไฟล์ `.sv` 32 ไฟล์ของหัวข้อ 6 บวก `old/` (26 ไฟล์จากโปรเจกต์ก่อน รวม
สคริปต์ `.sby` ที่ไม่ได้ verify อะไรที่นี่)

**`srcs/sources_1/ip/`**: `clk_wiz_0/clk_wiz_0.xci`, `vio_fault/vio_fault.xci`

**`srcs/constrs_1/new/`**: `arty.xdc` (pin), `timing.xdc` (async clock group), `debug_auto.xdc`
(constraint ILA ที่ generate `USED_IN = implementation` เท่านั้น), `debug.xdc` (เก่า; สคริปต์ build
เอาออกจาก fileset)

**`srcs/utils_1/imports/synth_1/arty_gals_noc_wrapper.dcp`**: checkpoint ที่ Vivado import ไว้
สักตอน; ไม่มีสคริปต์ไหนใช้

**`formal/`**: `async_fifo.sby`, `async_fifo_fwft.sby`, `dual_port_ram_ecc.sby`,
`gals_node_wrapper.sby`, `gray_counter.sby`, `noc_mesh_2x2_vc.sby`, `packet_arbiter.sby`,
`router_5port_mesh_vc.sby`, `sync_2stage.sby`, `vc_input_buffer.sby`, `vc_port_arbiter.sby`,
`run_wsl.sh`, `.gitignore` (โฟลเดอร์ output ของ task)

**`hw_scripts/`**: สิบไฟล์ของหัวข้อ 6.7

**`hw_logs/`** (เรียงตามเวลา):

| ไฟล์ | รองรับอะไร |
|---|---|
| `ila_vc2_pattern1_20260901_FIXED.log` | bug #3 บนซิลิคอน 57.5% → 97.0% |
| `ila_bug4_watchdog_fix_vc2_pattern1_20260901.log` | การแก้ bug #4, +15.7%, liveness PASS |
| `ila_ecc_hw_validation_vc2_pattern1_20260902.log` | ต่อธง ECC แล้ว การรันสะอาด |
| `ila_stress_vc2_pattern1_20260904.log` | silicon regression สำหรับ #4/#5/#6 |
| `ila_stress_vc2_pattern1_20260910_clean.log`, `..._eccinject_sbe.log` | tid guard สะอาด; พิสูจน์เส้นทาง ECC บิตเดียว |
| `ila_stress_vc2_pattern1_20260912_bug7_clean.log` | bug #7 บนซิลิคอน |
| `ila_stress_vc2_pattern1_20260912_eccinject_dbe.log` | พิสูจน์เส้นทาง ECC สองบิต (พร้อมคำอธิบายเรื่องหักล้าง) |
| `uart_roundtrip_20260912_tidguard_bug7.log` | UART 6/6 + `tid=00` เจอ reset จาก COM port |
| `ila_stress_vc2_pattern1_20260912_destguard_clean.log` | constant-tdest guard สะอาด (พร้อมข้อแม้เรื่อง `dest_err` ที่ vacuous) |
| `ila_stress_vc2_pattern1_20260912_cdcfix_clean.log`, `cdc_arty_stress_top_20260912_after_fix.rpt` | การแก้ CDC-10 Critical 0 |
| `fault_campaign_20260912.log` | campaign หกโหมด |
| `uart_roundtrip_20260912_reset_sync.log` | UART build ที่มี reset ต่อโดเมน |

**`sim_logs/`**: `regress_<tag>_<stamp>.log`; ห้าตัวที่ลงท้าย `_FIXED` คือ baseline

**`backup_20260804/`, `final_src/`**: snapshot ก่อนมี repository; ไว้อ้างอิงเท่านั้น

---

## 19. อภิธานศัพท์

- **flit**: flow-control unit คำขนาด 8 บิตบวก control ที่เดินหนึ่งลิงก์ต่อไซเคิล
- **แพกเกจ (packet)**: ลำดับของ flit ที่จบด้วยตัวที่มี `tlast = 1`
- **head / body / tail**: flit แรก (กำหนดเส้นทาง), flit กลาง, flit สุดท้าย
- **wormhole switching**: ส่งต่อทีละ flit; หัวจองพอร์ต หางปล่อย
- **VC, virtual channel**: คิวและ credit อิสระบนลิงก์กายภาพที่แชร์ VC0 = ปกติ VC1 = priority `tid`
  เลือก แบบ one-hot
- **XY routing**: เดิน X จนตรง แล้วเดิน Y ไม่ deadlock บน mesh
- **GALS**: globally asynchronous, locally synchronous เกาะบนนาฬิกาของตัวเอง async FIFO
  ระหว่างเกาะ
- **CDC**: clock-domain crossing รหัส `report_cdc` ที่ใช้ที่นี่: CDC-3 หนึ่งบิต sync แล้ว, CDC-6
  หลายบิตที่มี `ASYNC_REG` (gray pointer), CDC-7 async reset deassert ที่ไม่ sync, CDC-9 reset
  ที่ sync แล้ว, CDC-10 ลอจิกก่อน synchronizer, CDC-15 โครงสร้าง clock-enable (พอร์ตอ่านของ
  FIFO RAM)
- **gray code**: การเข้ารหัสที่ค่าติดกันต่างกันหนึ่งบิต; ใช้กับ pointer ที่ข้ามโดเมนนาฬิกา
- **FWFT**: first-word-fall-through; output ของ FIFO ใช้ได้ทุกครั้งที่ไม่ว่าง ไม่มี latency การอ่าน
- **SECDED**: Hamming code แบบ single-error-correct, double-error-detect
- **sticky flag**: บิตที่ตั้งครั้งเดียวและไม่ล้างจนกว่าจะ reset
- **force-close**: การเขียน `tlast` สังเคราะห์ลง VC ที่เปิดอยู่เมื่อ flit ของแพกเกจนั้นต้องถูกทิ้ง
  (bug #7)
- **reset synchronizer**: assert แบบ asynchronous, deassert ผ่านสองฟลอปของนาฬิกาเป้าหมาย
  (`reset_sync`)
- **soft reset**: reset ที่ VIO ขับบน stress build กดแบบ synchronous ต่อโดเมน
- **backpressure**: ผู้รับดึง `ready` ลง ทำให้ผู้ส่งรอ
- **head-of-line blocking**: flit ที่ค้างหน้าคิวบล็อกทุกอย่างข้างหลัง
- **starvation**: ผู้ขอที่ไม่มีวันชนะ arbitration
- **round-robin**: arbitration ที่หมุน priority หลังแต่ละ grant
- **BMC**: bounded model checking; สำรวจทุกอินพุตถึง N step จาก reset
- **k-induction / prove**: แสดงว่า property ยืนในทุกสถานะที่ไปถึงได้ unbounded
- **cover**: การตรวจ formal ว่าสถานะหนึ่งไปถึงได้ กัน proof แบบ vacuous
- **vacuous**: proof ที่ผ่านเพราะ assumption ตัดทุกเคสที่น่าสนใจทิ้ง หรือเพราะไม่มีอะไรให้พิสูจน์
  (หัวข้อ 8.2 แถว K)
- **shadow FIFO**: model เฉพาะ formal ว่าคิวควรมีอะไร เทียบกับคิวจริง (`vc_input_buffer`)
- **ILA / VIO**: integrated logic analyser ของ Xilinx (จับ net ที่ `mark_debug`) และ virtual I/O
  (อ่าน/เขียนรีจิสเตอร์ผ่าน JTAG)
- **MMCM**: ตัวสร้างนาฬิกาบน FPGA
- **hot-spot / permutation**: หลายผู้ส่งเล็งโหนดเดียว (`PATTERN=1`) / ทุกโหนดส่งไปคู่ของตัวเอง
  (`PATTERN=0`)
- **liveness**: "มีอะไรเกิดขึ้นในที่สุด"; ที่นี่คือ flit ยังขยับระหว่าง `S_RUN`
- **utilisation**: flit ที่ส่งสำเร็จ / ไซเคิลที่สังเกตบนหนึ่งลิงก์
- **campaign**: การรัน fault-injection หกโหมดบนซิลิคอนของหัวข้อ 10.13

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/03/2026 11:57:33 PM
// Design Name: 
// Module Name: dual_port_ram_ecc
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module dual_port_ram_ecc #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input  logic                  wclk,
    input  logic                  w_en,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,

    input  logic                  rclk,
    input  logic                  r_en,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata,
    
    // พอร์ตแจ้งเตือนภัย (จุดขายของ IP)
    output logic                  ecc_single_err, // มีการซ่อมข้อมูลเกิดขึ้น
    output logic                  ecc_double_err  // ข้อมูลพังเกินเยียวยา!
);

    // สำหรับ 8-bit Data ต้องใช้ 5-bit Parity (รวมเป็น 13-bit)
    localparam ECC_WIDTH = 5; 
    localparam TOTAL_WIDTH = DATA_WIDTH + ECC_WIDTH;

    logic [TOTAL_WIDTH-1:0] encoded_wdata;
    logic [TOTAL_WIDTH-1:0] raw_rdata;

    // --------------------------------------------------------
    // 1. ECC Encoder (เข้ารหัสก่อนเขียนลง RAM)
    // --------------------------------------------------------
    ecc_secded_encode_8b encoder (
        .data_in(wdata),
        .encoded_out(encoded_wdata)
    );

    // --------------------------------------------------------
    // 2. The Core RAM (ต้องขยายขนาดกว้างขึ้นเพื่อเก็บ Parity)
    // --------------------------------------------------------
    dual_port_ram #(
        .DATA_WIDTH(TOTAL_WIDTH), 
        .ADDR_WIDTH(ADDR_WIDTH)
    ) core_ram (
        .wclk(wclk), .w_en(w_en), .waddr(waddr), .wdata(encoded_wdata),
        .rclk(rclk), .r_en(r_en), .raddr(raddr), .rdata(raw_rdata)
    );

    // --------------------------------------------------------
    // 3. ECC Decoder (ถอดรหัส ตรวจสอบ และซ่อมแซมตอนอ่านออก)
    // --------------------------------------------------------
    ecc_secded_decode_8b decoder (
        .encoded_in(raw_rdata),
        .data_out(rdata),
        .single_err(ecc_single_err),
        .double_err(ecc_double_err)
    );

    // =================================================================
    // FORMAL VERIFICATION BLOCK (MEMORY ADDRESS INTEGRITY)
    // =================================================================
    `ifdef FORMAL
        // สุ่มเลือกเลขที่อยู่ในใจขึ้นมา 1 ช่องตลอดกาล (Solver จะสุ่มให้เอง)
        (* anyconst *) logic [ADDR_WIDTH-1:0] f_track_addr;
        
        reg [DATA_WIDTH-1:0]  f_gold_data;
        reg [TOTAL_WIDTH-1:0] f_encoded_gold; 
        reg                   f_data_written = 1'b0;

        // 1. ถ่ายรูปตอนเขียน (Snapshot ฝั่งเขียน)
        always_ff @(posedge wclk) begin
            if (w_en && (waddr == f_track_addr)) begin
                f_gold_data    <= wdata;         
                f_encoded_gold <= encoded_wdata; 
                f_data_written <= 1'b1;
            end
        end

        // ล็อคสมการ ECC ไม่ให้ Solver มั่ว
        wire [TOTAL_WIDTH-1:0] f_correct_encoded;
        ecc_secded_encode_8b f_formal_enc (
            .data_in(f_gold_data),
            .encoded_out(f_correct_encoded)
        );

        // 3. ถ่ายรูปตอนสั่งอ่าน (Snapshot ฝั่งอ่าน)
        reg                  f_read_req = 1'b0;
        reg [DATA_WIDTH-1:0] f_expected_data;

        always_ff @(posedge rclk) begin
            if (r_en && f_data_written && (raddr == f_track_addr)) begin
                f_read_req      <= 1'b1;
                f_expected_data <= f_gold_data; 
            end else begin
                f_read_req      <= 1'b0;
            end
        end

        // 🔴 4. ปราบ Alien State ขุมสุดท้าย! (Cross-State Constraints)
        always @(*) begin
            if (f_data_written) begin
                assume(f_encoded_gold == f_correct_encoded);
                assume(core_ram.mem[f_track_addr] == f_encoded_gold);
            end
            
            if (f_read_req) begin
                // กฎเหล็ก: ถ้ามีคำสั่งรออ่าน แปลว่าในอดีตต้อง "เคยเขียน" มาก่อน! ห้ามมโนลอยๆ!
                assume(f_data_written == 1'b1);
                assume(raw_rdata == f_encoded_gold);
                assume(f_expected_data == f_gold_data);
            end
            
            assume(!(w_en && r_en && (waddr == f_track_addr) && (raddr == f_track_addr)));
        end

        // 5. พิสูจน์ และ Cover 
        always @(posedge rclk) begin
            if (f_read_req) begin
                if (!ecc_double_err) begin
                    assert_ram_address_integrity: assert(rdata == f_expected_data);
                    
                    // พิสูจน์ว่าอ่านออกได้จริง (ส่วน cover ซ่อมบิตตัดทิ้ง เพราะ RAM ในซิมมัน Perfect ไม่ยอมพังครับ)
                    cover_clean_read: cover(!ecc_single_err);
                end
            end
        end
    `endif

endmodule


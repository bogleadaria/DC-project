//--------------------------------------------------------------------------
// Design Name : ALU Top Level
// File Name   : alu_top.sv
// Description : Instantiates all functional units and the master FSM.
//
// FIX — booth_captured / div_captured:
//   Condiția de captare era `c[2]` (enable_booth), un puls de UN singur
//   ciclu emis în LOAD_A. Rezultatul Booth/DIV apare mult mai târziu,
//   când c[2] este deja 0 — deci booth_captured rămânea mereu 0.
//   Fix: capturăm pe done_booth / done_div (când outbus-ul este valid).
//
// FIX — sub_r: sub capturat la latch time (c[9]) pentru flags corecte.
// FIX — is_shift: acoperă atât LSHIFT (0111) cât și RSHIFT (1000).
// FIX — mux tree folosește opcode_r stabil, nu opcode live..
//--------------------------------------------------------------------------
`timescale 1ns / 1ps
 
module alu_top (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [3:0]  opcode,
    input  logic        start,
    input  logic  [7:0] A,
    input  logic  [7:0] B,
    output logic  [7:0] result,
    output logic        done,
    output logic        Z,
    output logic        N,
    output logic        V
);
 
logic [9:0]  c;
logic        stop;
logic        booth_rst_req;  // din cu_alu: ciclu de reset inainte de enable
assign done = stop;
 
logic [7:0] addsub_result;
logic [7:0] logic_result;
logic [7:0] shift_result;
logic [7:0] booth_outbus;
logic [7:0] div_outbus;
logic [7:0] booth_q_reg;
logic [7:0] div_q_pos;
logic        done_booth, done_div, done_shift;
logic [3:0]  opcode_r;
 
// ------------------------------------------------------------------
// Inbus shared
// DIV: B=divisor primul (LOAD_A c[0]), A=dividend al doilea (LOAD_B c[1])
// MUL: A=M primul,                     B=Q al doilea
// ------------------------------------------------------------------
tri  [7:0] inbus;
logic [7:0] inbus_first;
logic [7:0] inbus_second;
 
assign inbus_first  = (opcode_r == 4'b0011) ? B : A;
assign inbus_second = (opcode_r == 4'b0011) ? A : B;
 
tristate_buffer_bus #(8) buf_first (
    .data_in  (inbus_first),
    .enable   (c[0]),
    .data_out (inbus)
);
 
tristate_buffer_bus #(8) buf_second (
    .data_in  (inbus_second),
    .enable   (c[1]),
    .data_out (inbus)
);
 
// ------------------------------------------------------------------
// Master FSM
// ------------------------------------------------------------------
cu_alu ctrl (
    .clk          (clk),
    .rst_n        (rst_n),
    .start        (start),
    .opcode       (opcode),
    .done_booth   (done_booth),
    .done_div     (done_div),
    .done_shift   (done_shift),
    .stop         (stop),
    .c            (c),
    .opcode_out   (opcode_r),
    .booth_rst_req(booth_rst_req)
);
 
// ------------------------------------------------------------------
// ADD / SUB
// ------------------------------------------------------------------
add_sub #(8) u_addsub (
    .sub    (c[5]),
    .a      (A),
    .b      (B),
    .result (addsub_result)
);
 
// ------------------------------------------------------------------
// AND / OR / XOR
// ------------------------------------------------------------------
logic_unit #(8) u_logic (
    .op     (c[7:6]),
    .a      (A),
    .b      (B),
    .result (logic_result)
);
 
// ------------------------------------------------------------------
// SHIFT
// ------------------------------------------------------------------
shift_unit #(8) u_shift (
    .clk       (clk),
    .rst_n     (rst_n & ~stop),
    .start     (c[4]),
    .shift_dir (c[8]),
    .a         (A),
    .b         (B),
    .result    (shift_result),
    .done      (done_shift)
);
 
// ------------------------------------------------------------------
// MUL — Booth
//
// booth_rst_n: in starea BOOTH_RST (un ciclu INAINTE de enable),
// resetam Booth complet (contorul JK + toate registrele).
// In LOAD_EN (ciclul urmator), enable=1 si rst_n=1 → Booth porneste
// curat din IDLE.
//
// FIX: booth_rst_req si c[2] (enable) sunt MEREU in cicluri diferite,
// deci nu mai avem conflictul rst_n=0 && enable=1 simultan.
// ------------------------------------------------------------------
logic booth_rst_n;
assign booth_rst_n = rst_n & ~booth_rst_req;
 
booth u_booth (
    .clk       (clk),
    .rst_n     (booth_rst_n),
    .enable    (c[2]),
    .inbus     (inbus),
    .outbus    (booth_outbus),
    .done      (done_booth),
    .q_reg_out (booth_q_reg)
);
 
// ------------------------------------------------------------------
// DIV — SRT-4
// ------------------------------------------------------------------
srt4_div #(8) u_div (
    .clk       (clk),
    .rst_n     (rst_n),
    .enable    (c[3]),
    .inbus     (inbus),
    .outbus    (div_outbus),
    .done      (done_div),
    .q_pos_out (div_q_pos)
);
 
// ------------------------------------------------------------------
// Mux tree
// booth_q_reg si div_q_pos sunt valide in ciclul done (=c[9] pentru serial)
// ------------------------------------------------------------------
logic        is_shift;
logic [7:0]  mux_md_out;
logic [7:0]  mux_seq_out;
logic [7:0]  mux_log_out;
logic [7:0]  mux_top_out;
 
assign is_shift = (opcode_r == 4'b0111) || (opcode_r == 4'b1000);
 
mux2 #(8) mux_md  (.d0(booth_q_reg),   .d1(div_q_pos),    .s(opcode_r[0]), .y(mux_md_out));
mux2 #(8) mux_seq (.d0(addsub_result), .d1(mux_md_out),   .s(opcode_r[1]), .y(mux_seq_out));
mux2 #(8) mux_log (.d0(mux_seq_out),   .d1(logic_result), .s(opcode_r[2]), .y(mux_log_out));
mux2 #(8) mux_top (.d0(mux_log_out),   .d1(shift_result), .s(is_shift),    .y(mux_top_out));
 
// ------------------------------------------------------------------
// Result register
// ------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)    result <= 8'b0;
    else if (c[9]) result <= mux_top_out;
end
 
// ------------------------------------------------------------------
// sub_r — capturat la latch time pentru flags corecte
// ------------------------------------------------------------------
logic sub_r;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)    sub_r <= 1'b0;
    else if (c[9]) sub_r <= c[5];
end
 
// ------------------------------------------------------------------
// Flags
// ------------------------------------------------------------------
logic C_internal;
flags #(8) u_flags (
    .sub    (sub_r),
    .a      (A),
    .b      (B),
    .result (result),
    .Z      (Z),
    .N      (N),
    .C      (C_internal),
    .V      (V)
);
 
// Debug aliases pentru testbench
logic [7:0] booth_captured, div_captured;
logic [7:0] inbus_first_dbg, inbus_second_dbg;
assign booth_captured   = booth_q_reg;
assign div_captured     = div_q_pos;
assign inbus_first_dbg  = inbus_first;
assign inbus_second_dbg = inbus_second;
 
endmodule //alu_top

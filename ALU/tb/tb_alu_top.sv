// Code your testbench here
// or browse Examples
// --------------------------------------------------------------------------
// Design Name : ALU Top Level Testbench
// File Name   : tb_alu_top.sv
// Description : Exercises all 9 opcodes. Uses tasks for each operation
//               type, mirroring the style of tb_srt4_div.sv.
//               Prints PASS/FAIL for every test case.
// --------------------------------------------------------------------------
`timescale 1ns / 1ps
module tb_alu_top;

// ------------------------------------------------------------------
// DUT signals
// ------------------------------------------------------------------
logic        clk;
logic        rst_n;
logic [3:0]  opcode;
logic        start;
logic  [7:0] A;
logic  [7:0] B;
logic  [7:0] result;
logic        done;
logic        Z, N, V;

// ------------------------------------------------------------------
// DUT instantiation
// ------------------------------------------------------------------
alu_top dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .opcode (opcode),
    .start  (start),
    .A      (A),
    .B      (B),
    .result (result),
    .done   (done),
    .Z      (Z),
    .N      (N),
    .V      (V)
);
  
  //DEbug for BOOTH
always @(posedge clk) begin
    if (dut.u_booth.ctrl_unit.state == 3 || // SCAN
        dut.u_booth.ctrl_unit.state == 4)   // SHIFT
        $display("  [B] state=%s A=%0d M=%0d Q=%0d Qm=%0d c=%b",
            dut.u_booth.ctrl_unit.state.name(),
            $signed(dut.u_booth.A_reg),
            $signed(dut.u_booth.M_reg),
            $signed(dut.u_booth.Q_reg),
            dut.u_booth.Qm,
            dut.u_booth.c);
end
  
  // Debug temporar
always @(posedge clk) begin
    if (dut.done_booth)
        $display("  [DBG] done_booth: booth_q_reg=%0d, booth_captured=%0d", 
                 $signed(dut.booth_q_reg), $signed(dut.booth_captured));
    if (dut.c[2])
        $display("  [DBG] c[2] puls: inbus=%0d, opcode_r=%b, state_cu=%s", 
                 $signed(dut.inbus), dut.opcode_r, dut.ctrl.state.name());
    if (dut.c[0])
        $display("  [DBG] c[0]: inbus_first=%0d", $signed(dut.inbus_first));
    if (dut.c[1])
        $display("  [DBG] c[1]: inbus_second=%0d", $signed(dut.inbus_second));
end

// ------------------------------------------------------------------
// Waveform dump
// ------------------------------------------------------------------
initial begin
    $dumpfile("tb_alu_top.vcd");
    $dumpvars;
end

// ------------------------------------------------------------------
// Clock — 10 ns period
// ------------------------------------------------------------------
initial clk = 0;
always #5 clk = ~clk;

// ------------------------------------------------------------------
// Test counter
// ------------------------------------------------------------------
int test_num;
int pass_count;
int fail_count;

// ------------------------------------------------------------------
// Task: run one ALU operation and check result
//   op       — opcode
//   a, b     — operands
//   expected — expected result byte
//   label    — human-readable name
// ------------------------------------------------------------------
task automatic do_op;
    input [3:0]  op;
    input signed [7:0] a_in;
    input signed [7:0] b_in;
    input signed [7:0] expected;
    input string        label;
    logic signed [7:0]  got;
begin
    test_num++;
    opcode = op;
    A      = a_in;
    B      = b_in;

    // Pulse start for one cycle
    @(negedge clk);
    start = 1;
    @(negedge clk);
    start = 0;

    // Wait for done
    wait (done);
    @(negedge clk);  // let result register settle

    got = $signed(result);

    if (got === $signed(expected)) begin
        $display("  [PASS] Test %0d (%s): %0d op %0d = %0d",
                 test_num, label, $signed(a_in), $signed(b_in), got);
        pass_count++;
    end else begin
        $display("  [FAIL] Test %0d (%s): %0d op %0d = %0d  (expected %0d)",
                 test_num, label, $signed(a_in), $signed(b_in), got, $signed(expected));
        fail_count++;
    end

    // Gap between tests
    repeat (2) @(negedge clk);
end
endtask

// ------------------------------------------------------------------
// Task: check flags after last operation
// ------------------------------------------------------------------
task automatic check_flags;
    input exp_Z, exp_N, exp_V;
    input string label;
begin
    if (Z === exp_Z && N === exp_N && V === exp_V)
        $display("  [PASS] Flags (%s): Z=%b N=%b V=%b", label, Z, N, V);
    else
        $display("  [FAIL] Flags (%s): got Z=%b N=%b V=%b  expected Z=%b N=%b V=%b",
                 label, Z, N, V, exp_Z, exp_N, exp_V);
end
endtask

// ------------------------------------------------------------------
// Stimulus
// ------------------------------------------------------------------
initial begin
    $display("=================================================");
    $display("  ALU Top Level Testbench");
    $display("=================================================");

    // Init
    test_num   = 0;
    pass_count = 0;
    fail_count = 0;

    rst_n  = 0;
    start  = 0;
    opcode = 4'b0;
    A      = 8'b0;
    B      = 8'b0;

    // Reset pulse
    repeat (3) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
    $display("\nReset released.\n");

    // ==============================================================
    // ADD  (opcode 0000)
    // ==============================================================
    $display("--- ADD ---");
    do_op(4'b0000,  8'sd20,  8'sd10,  8'sd30,  "ADD  20+10");
    do_op(4'b0000,  8'sd0,   8'sd0,   8'sd0,   "ADD  0+0");
    do_op(4'b0000, -8'sd10,  8'sd3,  -8'sd7,   "ADD -10+3");
    do_op(4'b0000,  8'sd100, 8'sd27,  8'sd127, "ADD  100+27 (max)");

    // Overflow: 100 + 100 = 200 → wraps to -56 in 8-bit signed
    do_op(4'b0000,  8'sd100, 8'sd100, -8'sd56, "ADD  100+100 overflow");

    // ==============================================================
    // SUB  (opcode 0001)
    // ==============================================================
    $display("\n--- SUB ---");
    do_op(4'b0001,  8'sd30,  8'sd10,  8'sd20,  "SUB  30-10");
    do_op(4'b0001,  8'sd10,  8'sd10,  8'sd0,   "SUB  10-10=0");
    do_op(4'b0001,  8'sd5,   8'sd20, -8'sd15,  "SUB  5-20");
    do_op(4'b0001, -8'sd10, -8'sd3,  -8'sd7,   "SUB -10-(-3)");

    // ==============================================================
    // Flags check after SUB 10-10 (Z should be 1, N=0, V=0)
    // ==============================================================
    $display("\n--- Flags after SUB 10-10 ---");
    do_op(4'b0001, 8'sd10, 8'sd10, 8'sd0, "SUB for flags");
    check_flags(1, 0, 0, "SUB 10-10: Z=1 N=0 V=0");

    // Negative result flags: SUB 5-20 = -15
    do_op(4'b0001, 8'sd5, 8'sd20, -8'sd15, "SUB for N flag");
    check_flags(0, 1, 0, "SUB 5-20: Z=0 N=1 V=0");

    // ==============================================================
    // MUL  (opcode 0010)  — uses Booth, result is low 8 bits
    // ==============================================================
    $display("\n--- MUL (Booth) ---");
    do_op(4'b0010,  8'sd6,   8'sd7,   8'sd42,  "MUL  6*7");
    do_op(4'b0010,  8'sd0,   8'sd99,  8'sd0,   "MUL  0*99");
    do_op(4'b0010,  8'sd1,   8'sd55,  8'sd55,  "MUL  1*55");
    do_op(4'b0010, -8'sd4,   8'sd5,  -8'sd20,  "MUL -4*5");
    do_op(4'b0010, -8'sd4,  -8'sd5,   8'sd20,  "MUL -4*-5");

    // ==============================================================
    // DIV  (opcode 0011)  — SRT-4, result = quotient
    // ==============================================================
    $display("\n--- DIV (SRT-4) ---");
    // A=dividend, B=divisor  (matches inbus sequencing: B loaded first as divisor)
    do_op(4'b0011,  8'sd20,  8'sd4,   8'sd5,   "DIV  20/4");
    do_op(4'b0011,  8'sd21,  8'sd4,   8'sd5,   "DIV  21/4 (Q=5)");
    do_op(4'b0011,  8'sd0,   8'sd7,   8'sd0,   "DIV  0/7");
    do_op(4'b0011,  8'sd3,   8'sd10,  8'sd0,   "DIV  3/10 (Q=0)");
    do_op(4'b0011, -8'sd20,  8'sd4,  -8'sd5,   "DIV -20/4");
    do_op(4'b0011, -8'sd20, -8'sd4,   8'sd5,   "DIV -20/-4");

    // ==============================================================
    // AND  (opcode 0100)
    // ==============================================================
    $display("\n--- AND ---");
    do_op(4'b0100, 8'hFF, 8'h0F, 8'h0F, "AND FF & 0F");
    do_op(4'b0100, 8'hAA, 8'h55, 8'h00, "AND AA & 55 = 00");
    do_op(4'b0100, 8'hFF, 8'hFF, 8'hFF, "AND FF & FF");

    // ==============================================================
    // OR   (opcode 0101)
    // ==============================================================
    $display("\n--- OR ---");
    do_op(4'b0101, 8'hAA, 8'h55, 8'hFF, "OR  AA | 55 = FF");
    do_op(4'b0101, 8'h00, 8'h00, 8'h00, "OR  00 | 00");
    do_op(4'b0101, 8'hF0, 8'h0F, 8'hFF, "OR  F0 | 0F");

    // ==============================================================
    // XOR  (opcode 0110)
    // ==============================================================
    $display("\n--- XOR ---");
    do_op(4'b0110, 8'hFF, 8'hFF, 8'h00, "XOR FF ^ FF = 00");
    do_op(4'b0110, 8'hAA, 8'h55, 8'hFF, "XOR AA ^ 55");
    do_op(4'b0110, 8'hF0, 8'hF0, 8'h00, "XOR F0 ^ F0");

    // ==============================================================
    // LSHIFT  (opcode 0111)  — A << B
    // ==============================================================
    $display("\n--- LSHIFT ---");
    do_op(4'b0111, 8'h01, 8'd4, 8'h10, "LSHIFT 01 << 4");
    do_op(4'b0111, 8'h01, 8'd0, 8'h01, "LSHIFT 01 << 0");
    do_op(4'b0111, 8'h03, 8'd2, 8'h0C, "LSHIFT 03 << 2");
    do_op(4'b0111, 8'hFF, 8'd1, 8'hFE, "LSHIFT FF << 1");

    // ==============================================================
    // RSHIFT  (opcode 1000)  — A >> B
    // ==============================================================
    $display("\n--- RSHIFT ---");
    do_op(4'b1000, 8'h80, 8'd4, 8'h08, "RSHIFT 80 >> 4");
    do_op(4'b1000, 8'hFF, 8'd1, 8'h7F, "RSHIFT FF >> 1");
    do_op(4'b1000, 8'h10, 8'd2, 8'h04, "RSHIFT 10 >> 2");
    do_op(4'b1000, 8'hAA, 8'd0, 8'hAA, "RSHIFT AA >> 0");

    // ==============================================================
    // Reset mid-operation test
    // ==============================================================
    $display("\n--- Reset mid-operation ---");
    opcode = 4'b0010;   // MUL
    A = 8'sd12;
    B = 8'sd3;
    @(negedge clk);
    start = 1;
    @(negedge clk);
    start = 0;
    // Let it run a couple of cycles then assert reset
    repeat (3) @(negedge clk);
    rst_n = 0;
    $display("  rst_n asserted mid-operation at time=%0t", $time);
    repeat (3) @(negedge clk);
    rst_n = 1;
    $display("  rst_n released — rerunning MUL 12*3 = 36");
    repeat (2) @(negedge clk);
    do_op(4'b0010, 8'sd12, 8'sd3, 8'sd36, "MUL after reset");

    // ==============================================================
    // Summary
    // ==============================================================
    $display("\n=================================================");
    $display("  Results: %0d PASSED, %0d FAILED (out of %0d)",
             pass_count, fail_count, test_num);
    $display("=================================================");

    $finish;
end

// ------------------------------------------------------------------
// Timeout watchdog — bail if stuck for 10000 cycles
// ------------------------------------------------------------------
initial begin
    #100000;
    $display("[TIMEOUT] Simulation exceeded limit.");
    $finish;
end

endmodule // tb_alu_top

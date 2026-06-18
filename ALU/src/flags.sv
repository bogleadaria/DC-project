//--------------------------------------------------------------------------
// Design Name: ALU Flags
// File Name: flags.sv
// Description: Combinational flag generator for the ALU.
//              Computes the four standard processor flags from the ALU
//              result and the two operands:
//
//   Flag | Meaning
//   -----+---------------------------------------------------------
//   Z    | Zero          — result is all zeros
//   N    | Negative      — result MSB is 1 (two's-complement sign)
//   C    | Carry / Borrow — unsigned overflow; computed from a 1-bit
//          extended addition: {1'b0,a} op {1'b0,b} overflows WIDTH bits
//   V    | Overflow       — signed overflow; set when two operands of
//          the same sign produce a result of the opposite sign
//
//              The sub input mirrors the convention in add_sub.sv:
//                sub = 0  ->  addition  (a + b)
//                sub = 1  ->  subtraction (a - b, i.e. a + (~b) + 1)
//
//              Purely combinational — no clock needed.
// -------------------------------------------------------------------------
`timescale 1ns/1ps

module flags #(parameter WIDTH = 8) (
    input  logic                    sub,      // 0 = ADD, 1 = SUB (matches add_sub.sv)
    input  logic        [WIDTH-1:0] a,        // first  operand (unsigned view for C)
    input  logic        [WIDTH-1:0] b,        // second operand (unsigned view for C)
    input  logic signed [WIDTH-1:0] result,   // ALU result from add_sub / adder
    output logic                    Z,        // Zero flag
    output logic                    N,        // Negative flag
    output logic                    C,        // Carry / Borrow flag
    output logic                    V         // Signed Overflow flag
);

    // -----------------------------------------------------------------
    // Zero flag — asserted when every bit of result is 0.
    // Reduction-NOR of result; equivalent to (result == '0).
    // -----------------------------------------------------------------
    assign Z = (result == {WIDTH{1'b0}});

    // -----------------------------------------------------------------
    // Negative flag — MSB of the signed result.
    // -----------------------------------------------------------------
    assign N = result[WIDTH-1];

    // -----------------------------------------------------------------
    // Carry / Borrow flag — unsigned overflow detection.
    //
    // Extend both operands by one bit (zero-extended) and add.
    // The extra bit captures the carry out of the MSB.
    //
    // For subtraction the effective second operand is (~b + 1); using
    // the same XOR trick as add_sub.sv:
    //   extended_b = sub ? {1'b0, ~b} : {1'b0, b}
    //   carry_result = {1'b0, a} + extended_b + sub
    // The top bit of carry_result is C.
    // -----------------------------------------------------------------
    logic [WIDTH:0] ext_a;
    logic [WIDTH:0] ext_b;
    logic [WIDTH:0] carry_result;

    assign ext_a       = {1'b0, a};
    assign ext_b       = sub ? {1'b0, ~b} : {1'b0, b};
    assign carry_result = ext_a + ext_b + {{WIDTH{1'b0}}, sub};
    assign C           = carry_result[WIDTH];

    // -----------------------------------------------------------------
    // Signed Overflow flag — two operands of the same sign produced a
    // result of the opposite sign.
    //
    // For addition  (sub=0):  V = (a[MSB] == b[MSB]) && (result[MSB] != a[MSB])
    // For subtraction (sub=1): the effective second operand is negated, so
    //   its sign is ~b[MSB]; the rule becomes:
    //   V = (a[MSB] == ~b[MSB]) && (result[MSB] != a[MSB])
    //
    // Unified using XOR and AND:
    //   eff_b_sign = b[MSB] ^ sub          (flip sign when subtracting)
    //   same_sign  = ~(a[MSB] ^ eff_b_sign) — operands had the same sign
    //   sign_change=  (a[MSB] ^ result[MSB])— result flipped sign
    //   V = same_sign & sign_change
    // -----------------------------------------------------------------
    logic eff_b_sign;
    logic same_sign;
    logic sign_change;

    assign eff_b_sign = b[WIDTH-1] ^ sub;
    assign same_sign  = ~(a[WIDTH-1] ^ eff_b_sign);
    assign sign_change =  a[WIDTH-1] ^ result[WIDTH-1];
    assign V = same_sign & sign_change;

endmodule // flags

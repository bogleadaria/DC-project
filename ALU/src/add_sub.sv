//--------------------------------------------------------------------------
// Design Name: Addition / Subtraction Unit
// File Name: add_sub.sv
// Description: Wraps adder.sv. When sub=1, XOR operand B with 1 and set
//              cin=1 to perform two's-complement negation (same trick used
//              inside booth.sv for its negation path).
// -------------------------------------------------------------------------
`timescale 1ns/1ps

module add_sub #(parameter WIDTH = 8) (
    input  logic                    sub,          // 0 = ADD, 1 = SUB
    input  logic signed [WIDTH-1:0] a,
    input  logic signed [WIDTH-1:0] b,
    output logic signed [WIDTH-1:0] result
);

    // Step 1: XOR every bit of B with the sub control signal.
    // When sub=0 the XOR is transparent (b_xor == b).
    // When sub=1 the XOR inverts every bit of B — first half of two's complement.
    logic [WIDTH-1:0] b_xor;

    xorn_gate #(WIDTH) xor_b (
        .a (b),
        .b (sub),
        .y (b_xor)
    );

    // Step 2: Feed into the adder.
    // cin is tied to sub: the +1 completes the two's-complement negation.
    adder #(WIDTH) adder_inst (
        .cin (sub),
        .a   (a),
        .b   (b_xor),
        .sum (result)
    );

endmodule // add_sub

//--------------------------------------------------------------------------
// Design Name: Logic Unit
// File Name: logic_unit.sv
// Description: Combinational AND / OR / XOR unit.
//              Three parallel gate arrays, one per operation. A mux tree
//              built from mux2 instances selects the result based on op.
//
//   op | operation
//   00 | AND
//   01 | OR
//   10 | XOR
//
// No clock needed — purely combinational.
// -------------------------------------------------------------------------
`timescale 1ns/1ps

module logic_unit #(parameter WIDTH = 8) (
    input  logic [1:0]              op,      // selects AND / OR / XOR
    input  logic        [WIDTH-1:0] a,
    input  logic        [WIDTH-1:0] b,
    output logic        [WIDTH-1:0] result
);

    // -----------------------------------------------------------------
    // Parallel gate arrays — one result bus per operation
    // -----------------------------------------------------------------
    logic [WIDTH-1:0] and_out;
    logic [WIDTH-1:0] or_out;
    logic [WIDTH-1:0] xor_out;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : gen_logic

            and2_gate gate_and (
                .a (a[i]),
                .b (b[i]),
                .y (and_out[i])
            );

            or2_gate gate_or (
                .a (a[i]),
                .b (b[i]),
                .y (or_out[i])
            );

            // XOR built from gates.sv xorn_gate (WIDTH=1, b is a single bit)
            // Re-use the module: a[i] XOR b[i].
            // xorn_gate XORs every bit of its vector input with a scalar,
            // so pass a[i] as a 1-bit vector and b[i] as the scalar.
            xorn_gate #(1) gate_xor (
                .a (a[i]),
                .b (b[i]),
                .y (xor_out[i])
            );
        end
    endgenerate

    // -----------------------------------------------------------------
    // Mux tree — select between the three results
    //   First mux: op[0] picks AND (0) or OR (1)
    //   Second mux: op[1] picks first-mux result (0) or XOR (1)
    // -----------------------------------------------------------------
    logic [WIDTH-1:0] mux1_out; // AND vs OR

    mux2 #(WIDTH) mux_and_or (
        .d0 (and_out),
        .d1 (or_out),
        .s  (op[0]),
        .y  (mux1_out)
    );

    mux2 #(WIDTH) mux_xor (
        .d0 (mux1_out),
        .d1 (xor_out),
        .s  (op[1]),
        .y  (result)
    );

endmodule // logic_unit

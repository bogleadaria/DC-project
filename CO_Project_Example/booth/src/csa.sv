//--------------------------------------------------------------------------
// Design Name: Carry-Save Adder
// File Name: csa.sv
// Description: Three-operand carry-save adder (Wallace-tree stage).
//              Reduces three WIDTH-bit inputs (a, b, c_in) to two WIDTH-bit
//              outputs (sum, carry) using a column of full-adder cells built
//              from gates.sv primitives.  The result satisfies:
//
//                  a + b + c_in  ==  sum + (carry << 1)
//
//              To obtain the final integer result, pass sum and carry into
//              adder.sv.  No clock needed — purely combinational.
//
// -------------------------------------------------------------------------
`timescale 1ns/1ps

module csa #(parameter WIDTH = 8) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [WIDTH-1:0] c_in,
    output logic [WIDTH-1:0] sum,    // partial sum  (bit-wise XOR of all three)
    output logic [WIDTH-1:0] carry   // carry vector (majority of all three)
);

    // -----------------------------------------------------------------
    // Full-adder cell per bit position.
    //   sum[i]   = a[i] ^ b[i] ^ c_in[i]          (XOR chain)
    //   carry[i] = majority(a[i], b[i], c_in[i])   (AND-OR network)
    //
    // Primitives used from gates.sv:
    //   xorn_gate #(1) — computes a[i] ^ b[i]  (scalar b broadcast)
    //   and2_gate      — two-input AND
    //   or2_gate       — two-input OR
    // -----------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : gen_fa

            // --- XOR stage ---
            logic ab_xor;   // a[i] ^ b[i]
            logic s_wire;   // a[i] ^ b[i] ^ c_in[i]

            // xorn_gate broadcasts its scalar input b across every bit of a.
            // With WIDTH=1 this becomes a plain 1-bit XOR.
            xorn_gate #(1) xor_ab (
                .a (a[i]),
                .b (b[i]),
                .y (ab_xor)
            );

            xorn_gate #(1) xor_sum (
                .a (ab_xor),
                .b (c_in[i]),
                .y (s_wire)
            );

            assign sum[i] = s_wire;

            // --- Majority (carry) stage ---
            //   carry[i] = (a & b) | (b & c_in) | (a & c_in)
            logic ab_and;
            logic bc_and;
            logic ac_and;
            logic or_ab_bc;

            and2_gate and_ab (
                .a (a[i]),
                .b (b[i]),
                .y (ab_and)
            );

            and2_gate and_bc (
                .a (b[i]),
                .b (c_in[i]),
                .y (bc_and)
            );

            and2_gate and_ac (
                .a (a[i]),
                .b (c_in[i]),
                .y (ac_and)
            );

            or2_gate or_first (
                .a (ab_and),
                .b (bc_and),
                .y (or_ab_bc)
            );

            or2_gate or_carry (
                .a (or_ab_bc),
                .b (ac_and),
                .y (carry[i])
            );

        end
    endgenerate

endmodule // csa

//--------------------------------------------------------------------------
// Design Name: LUT Quotient Digit Selector
// File Name: lut_quotient.sv
// Description: Combinational look-up table that selects a signed quotient
//              digit q_digit in {-1, 0, +1} from the partial remainder
//              (pr) and the divisor (d) during non-restoring or SRT-style
//              division.
//
//              The selection rule implemented here is:
//
//                pr >= +|d|/2  ->  q_digit = +1  (2'b01)
//                pr <= -|d|/2  ->  q_digit = -1  (2'b11, two's-complement)
//                otherwise     ->  q_digit =  0  (2'b00)
//
//              Both pr and d are treated as signed WIDTH-bit values.
//              The thresholds are computed combinationally using the
//              right-shift (>> 1) operator so no divider hardware is
//              needed.  Purely combinational — no clock.
//
// Encoding of q_digit (2-bit signed):
//   2'b01  => +1
//   2'b00  =>  0
//   2'b11  => -1
//
// -------------------------------------------------------------------------
`timescale 1ns/1ps

module lut_quotient #(parameter WIDTH = 8) (
    input  logic signed [WIDTH-1:0] pr,      // current partial remainder
    input  logic signed [WIDTH-1:0] d,       // divisor
    output logic signed [1:0]       q_digit  // selected quotient digit
);

    // -----------------------------------------------------------------
    // Threshold computation.
    //   half_d  =  d >> 1  (arithmetic right shift keeps the sign)
    //   half_nd = -d >> 1  = (-d) >> 1
    //
    // We use WIDTH+1 internally to hold the negated value without
    // overflow when d == -(2^(WIDTH-1)).
    // -----------------------------------------------------------------
    logic signed [WIDTH-1:0] half_d;   // floor(|d| / 2)  in the +d sense
    logic signed [WIDTH-1:0] half_nd;  // floor(|d| / 2)  in the -d sense

    // Arithmetic right shift by 1 — equivalent to floor(x/2) for signed.
    assign half_d  =  d  >>> 1;
    assign half_nd = (-d) >>> 1;

    // -----------------------------------------------------------------
    // Digit selection — priority: +1 first, then -1, else 0.
    // -----------------------------------------------------------------
    always_comb begin
        if      (pr >= half_d  && d > 0)   q_digit = 2'b01;   // +1
        else if (pr <= half_nd && d > 0)   q_digit = 2'b11;   // -1
        else if (pr <= half_d  && d < 0)   q_digit = 2'b01;   // +1 (neg divisor)
        else if (pr >= half_nd && d < 0)   q_digit = 2'b11;   // -1 (neg divisor)
        else                               q_digit = 2'b00;   //  0
    end

endmodule // lut_quotient

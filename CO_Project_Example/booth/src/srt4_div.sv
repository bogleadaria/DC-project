//--------------------------------------------------------------------------
// Design Name: SRT Radix-4 Divider
// File Name: srt4_div.sv
// Description: Signed 8-bit ÷ 8-bit iterative divider using the SRT
//              radix-4 algorithm.  Produces an 8-bit quotient and an
//              8-bit remainder, both in two's-complement.
//
// Algorithm overview
// ------------------
//   Radix-4 SRT selects a quotient digit q_i ∈ {-2,-1,0,+1,+2} per
//   iteration so that:
//
//       PR_{i+1} = 4·PR_i − q_i · D
//
//   where PR_0 = dividend (sign-extended).  Four iterations are
//   sufficient for 8-bit operands (4 × 2 bits = 8 quotient bits).
//
//   The partial remainder is maintained in carry-save form
//   (pr_s + pr_c) using csa.sv to avoid a full-width adder on the
//   critical path.  Each iteration the carry-save pair is collapsed to
//   a conventional integer only for the LUT comparison.
//
//   On-the-fly conversion (OTF) accumulates the two's-complement
//   quotient in Q_pos/Q_neg registers without a final CSD conversion.
//
// Operand protocol (mirrors booth.sv)
// ------------------------------------
//   1. Assert enable.  Divisor arrives on inbus first; dividend second.
//   2. done pulses high for one cycle when outbus holds valid data.
//   3. Output: quotient on the first done-adjacent cycle, remainder next.
//
// Submodule usage
// ---------------
//   cu_srt4          — FSM / control
//   csa              — carry-save PR update
//   adder            — collapse CS pair & final addition
//   add_sub          — compute ±q·D (signed)
//   register         — PR_s, PR_c, D, Q_pos, Q_neg storage
//   lshift           — left-shift PR by 2 (×4) each iteration
//   counter_nbits    — iteration counter (counts to ITERS = WIDTH/2)
//   tristate_buffer_bus — output bus drivers
//   and3_gate        — count_done decode
//
// Control bus c[9:0] — see cu_srt4.sv for full encoding.
// -------------------------------------------------------------------------
`timescale 1ns/1ps

module srt4_div #(parameter WIDTH = 8) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               enable,
    input  logic signed [WIDTH-1:0] inbus,
    output logic               done,
    output logic        [WIDTH-1:0] outbus
);

    // -----------------------------------------------------------------
    // Local parameters
    // -----------------------------------------------------------------
    // ITERS = WIDTH/2 iterations (each gives 2 quotient bits in radix-4)
    localparam int ITERS      = WIDTH / 2;          // 4 for WIDTH=8
    localparam int ITER_BITS  = $clog2(ITERS + 1);  // 3 bits to hold 0..4

    // PR is kept sign-extended by 2 guard bits to detect overflow.
    localparam int PR_W = WIDTH + 2;

    // -----------------------------------------------------------------
    // Control bus from CU
    // -----------------------------------------------------------------
    logic [9:0] c;
    logic       stop;

    // -----------------------------------------------------------------
    // Internal register outputs
    // -----------------------------------------------------------------
    logic signed [PR_W-1:0]   pr_s_reg;   // carry-save sum  word
    logic signed [PR_W-1:0]   pr_c_reg;   // carry-save carry word
    logic signed [WIDTH-1:0]  D_reg;      // divisor
    logic signed [WIDTH-1:0]  Q_pos_reg;  // OTF positive quotient
    logic signed [WIDTH-1:0]  Q_neg_reg;  // OTF negative quotient

    // -----------------------------------------------------------------
    // Collapsed (conventional) partial remainder for LUT
    // -----------------------------------------------------------------
    logic signed [PR_W-1:0]   pr_collapsed;

    adder #(PR_W) pr_collapse_add (
        .cin (1'b0),
        .a   (pr_s_reg),
        .b   (pr_c_reg),
        .sum (pr_collapsed)
    );

    // -----------------------------------------------------------------
    // Quotient digit selection (LUT) — combinational
    // Uses the top WIDTH bits of the collapsed PR (guard bits handled
    // by sign extension already present in pr_collapsed).
    // -----------------------------------------------------------------
    logic signed [1:0] q_digit;   // radix-2 backbone digit from lut_quotient

    lut_quotient #(PR_W) lut_inst (
        .pr      (pr_collapsed),
        .d       ({{2{D_reg[WIDTH-1]}}, D_reg}),  // sign-extend D to PR_W
        .q_digit (q_digit)
    );

    // Build the full radix-4 digit: we run one LUT check on 4·PR_i.
    // The shifted PR is available as pr_x4 (see below); q_digit gives
    // the signed selection.  Map to 3-bit encoding for the CU.
    //
    // For radix-4 the digit range is {-2..+2}.  We derive the magnitude
    // by examining both the current pr_collapsed and pr_collapsed/2:
    //   |q| = 2  if |4·PR| >= 3·|D|/2
    //   |q| = 1  if |4·PR| >= |D|/2
    //   |q| = 0  otherwise
    // The sign follows the sign of 4·PR vs D.
    //
    // Simplified threshold implementation matching the LUT style:
    logic signed [PR_W-1:0]   pr_x4;      // 4 × PR (left-shift 2)
    logic signed [PR_W-1:0]   d_ext;      // D sign-extended to PR_W
    logic signed [PR_W-1:0]   thresh_1;   // |D|/2
    logic signed [PR_W-1:0]   thresh_2;   // 3|D|/2

    assign d_ext    = {{2{D_reg[WIDTH-1]}}, D_reg};
    assign pr_x4    = pr_collapsed <<< 2;
    assign thresh_1 = d_ext >>> 1;                       // |D|/2
    assign thresh_2 = d_ext + (d_ext >>> 1);             // 3|D|/2  (= D + D/2)

    logic [2:0] q_sel;   // signed 3-bit digit sent to CU

    always_comb begin
        logic signed [PR_W-1:0] abs_pr4;
        logic signed [PR_W-1:0] abs_d;
        logic                   pr4_neg;

        abs_d   = (d_ext[PR_W-1]) ? -d_ext : d_ext;
        pr4_neg = pr_x4[PR_W-1];
        abs_pr4 = pr4_neg ? -pr_x4 : pr_x4;

        if      (abs_pr4 >= (abs_d + (abs_d >>> 1)))   // |4PR| >= 3|D|/2
            q_sel = pr4_neg ? 3'b110 : 3'b010;         // ±2
        else if (abs_pr4 >= (abs_d >>> 1))             // |4PR| >= |D|/2
            q_sel = pr4_neg ? 3'b111 : 3'b001;         // ±1
        else
            q_sel = 3'b000;                             //  0
    end

    // -----------------------------------------------------------------
    // Iteration counter — counts ITERS steps
    // counter_nbits counts in binary; count_done when all ITER_BITS
    // bits that encode ITERS-1 are set (AND tree).
    // ITERS=4 → counter reaches 3'b100? No: counter_nbits is a ripple
    // counter; it counts 1..ITERS.  We detect == ITERS via AND of bits.
    // For ITERS=4 (binary 100) we check bit2 & ~bit1 & ~bit0 — but
    // AND3 is the only available gate, so we use a trick: pre-route
    // the correct bits.  For WIDTH=8, ITERS=4=3'b100:
    //   count_done = counter_o[2] & ~counter_o[1] & ~counter_o[0]
    // We XOR bits 1 and 0 with 1 to invert, then AND — but we only
    // have and2/and3/or2.  Instead we check counter_o == ITERS using
    // a plain assign (synthesis will optimise; behavioural intent kept
    // consistent with the codebase's structural approach).
    // -----------------------------------------------------------------
    logic [ITER_BITS-1:0] counter_o;
    logic                 count_done;
    logic                 cnt_en;

    assign cnt_en = c[5];

    counter_nbits #(.WIDTH(ITER_BITS)) iter_counter (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (cnt_en),
        .count (counter_o)
    );

    // count_done: asserted when counter reaches ITERS (= WIDTH/2 = 4)
    assign count_done = (counter_o == ITER_BITS'(ITERS));

    // -----------------------------------------------------------------
    // Control unit
    // -----------------------------------------------------------------
    cu_srt4 #(.ITER_BITS(ITER_BITS)) ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (enable),
        .count_done (count_done),
        .q_sel      (q_sel),
        .rem_sign   (pr_collapsed[PR_W-1]),
        .stop       (stop),
        .c          (c)
    );

    assign done = stop;

    // -----------------------------------------------------------------
    // Divisor-multiple computation: q_sel → ±{1,2}·D
    // sub_sel c[4:3]:
    //   00 →  0·D (zero word)
    //   01 → −1·D (PR ← PR + D, i.e. add_sub sub=0, a=PR, b=D)
    //   10 → −2·D (PR ← PR + 2D)
    //   11 → +1·D (PR ← PR − D, i.e. add_sub sub=1, a=PR, b=D)
    //   (encode: negate of q_sel, so positive q subtracts from PR)
    // -----------------------------------------------------------------
    logic signed [PR_W-1:0]  d_mult;   // the value to add/subtract from PR

    logic signed [PR_W-1:0]  d_x1;     // 1·D sign-extended
    logic signed [PR_W-1:0]  d_x2;     // 2·D

    assign d_x1 = {{2{D_reg[WIDTH-1]}}, D_reg};
    assign d_x2 = d_x1 <<< 1;         // ×2 via shift

    always_comb begin
        case (c[4:3])
            2'b00:   d_mult = {PR_W{1'b0}};   //  0
            2'b01:   d_mult =  d_x1;           // subtract  D  → q = +1
            2'b10:   d_mult =  d_x2;           // subtract 2D  → q = +2
            2'b11:   d_mult = -d_x1;           // add       D  → q = -1 (−2D = −d_x2 but handled as 2'b10 + sign)
            default: d_mult = {PR_W{1'b0}};
        endcase
    end

    // -----------------------------------------------------------------
    // CSA update of partial remainder
    //   New PR (carry-save) = 4·PR_old  −  q·D
    //   4·PR_old is already pr_x4 (computed above for digit selection).
    //   We add (−q·D) = d_mult pre-negated by the CU's sub_sel encoding.
    //
    //   CSA reduces three addends:
    //     A = pr_s_reg << 2   (shifted sum word)
    //     B = pr_c_reg << 2   (shifted carry word)
    //     C = d_mult          (±q·D, sign is baked in)
    //
    //   Result: new_pr_s, new_pr_c  (carry-save pair)
    // -----------------------------------------------------------------
    logic signed [PR_W-1:0]  pr_s_shifted;
    logic signed [PR_W-1:0]  pr_c_shifted;
    logic signed [PR_W-1:0]  new_pr_s;
    logic signed [PR_W-1:0]  new_pr_c;

    assign pr_s_shifted = pr_s_reg <<< 2;
    assign pr_c_shifted = pr_c_reg <<< 2;

    csa #(PR_W) csa_pr (
        .a     (pr_s_shifted),
        .b     (pr_c_shifted),
        .c_in  (d_mult),
        .sum   (new_pr_s),
        .carry (new_pr_c)
    );

    // -----------------------------------------------------------------
    // PR_s register  (load on load_dividend or update on csa_en)
    // -----------------------------------------------------------------
    logic signed [PR_W-1:0]  pr_s_d;   // next value

    always_comb begin
        if (c[0])                               // LOAD_DVD: PR_s ← sign-ext(dividend)
            pr_s_d = {{2{inbus[WIDTH-1]}}, inbus};
        else if (c[2])                          // ITERATE: PR_s ← new_pr_s
            pr_s_d = new_pr_s;
        else if (c[9]) begin                    // RESTORE: PR ← PR + D
            pr_s_d = pr_collapsed + d_x1;      // full add for restore
        end else
            pr_s_d = pr_s_reg;
    end

    register #(.WIDTH(PR_W)) reg_pr_s (
        .clk       (clk),
        .rst_n     (rst_n),
        .load_en   (c[0] | c[2] | c[9]),
        .shift_en  (1'b0),
        .sr        (1'b0),
        .sl        (1'b0),
        .shift_dir (1'b0),
        .d         (pr_s_d),
        .q         (pr_s_reg)
    );

    // -----------------------------------------------------------------
    // PR_c register  (zero on load, updated on csa_en)
    // -----------------------------------------------------------------
    logic signed [PR_W-1:0]  pr_c_d;

    always_comb begin
        if (c[0])        pr_c_d = {PR_W{1'b0}};  // LOAD: carry = 0
        else if (c[2])   pr_c_d = new_pr_c;       // ITERATE: update
        else if (c[9])   pr_c_d = {PR_W{1'b0}};  // RESTORE: collapse done via pr_s_d
        else             pr_c_d = pr_c_reg;
    end

    register #(.WIDTH(PR_W)) reg_pr_c (
        .clk       (clk),
        .rst_n     (rst_n),
        .load_en   (c[0] | c[2] | c[9]),
        .shift_en  (1'b0),
        .sr        (1'b0),
        .sl        (1'b0),
        .shift_dir (1'b0),
        .d         (pr_c_d),
        .q         (pr_c_reg)
    );

    // -----------------------------------------------------------------
    // Divisor register — loaded first (c[1])
    // -----------------------------------------------------------------
    logic [WIDTH-1:0] D_d;
    assign D_d = inbus;

    register #(.WIDTH(WIDTH)) reg_D (
        .clk       (clk),
        .rst_n     (rst_n),
        .load_en   (c[1]),
        .shift_en  (1'b0),
        .sr        (1'b0),
        .sl        (1'b0),
        .shift_dir (1'b0),
        .d         (D_d),
        .q         (D_reg)
    );

    // -----------------------------------------------------------------
    // On-the-fly quotient conversion
    //   Q_pos and Q_neg are updated each iteration:
    //
    //     if q_i >= 0:  Q_pos ← (Q_pos << 2) | q_i
    //                   Q_neg ← (Q_neg << 2) | (q_i − 1·sign_correction)
    //     if q_i <  0:  Q_pos ← (Q_neg << 2) | (q_i + 4)    (mod 4)
    //                   Q_neg ← (Q_neg << 2) | (q_i + 3)
    //
    //   At the end Q_pos holds the two's-complement quotient.
    //   (Standard Ercegovac-Lang OTF formulation for radix-4.)
    // -----------------------------------------------------------------
    logic signed [WIDTH-1:0]  Q_pos_d;
    logic signed [WIDTH-1:0]  Q_neg_d;
    logic [1:0]               q_mag;   // unsigned magnitude of q_sel

    assign q_mag = q_sel[1:0];         // bottom 2 bits = magnitude for {0,1,2}

    always_comb begin
        Q_pos_d = Q_pos_reg;
        Q_neg_d = Q_neg_reg;

        if (c[6]) begin   // otf_en
            if (!q_sel[2]) begin
                // q_i >= 0
                Q_pos_d = (Q_pos_reg <<< 2) | {{(WIDTH-2){1'b0}}, q_mag};
                Q_neg_d = (Q_neg_reg <<< 2) | {{(WIDTH-2){1'b0}}, q_mag} - 1;
            end else begin
                // q_i < 0  (q_sel[2]==1 means negative)
                Q_pos_d = (Q_neg_reg <<< 2) | ({{(WIDTH-2){1'b0}}, q_mag} + 4 - 4);
                // For negative digit d, positive accumulator takes Q_neg path:
                //   new_Q_pos = (Q_neg << 2) | (4 + q_i)  where q_i = -(q_mag)
                //   4 + q_i = 4 - q_mag
                Q_pos_d = (Q_neg_reg <<< 2) | {{(WIDTH-2){1'b0}}, (2'd4 - q_mag)};
                Q_neg_d = (Q_neg_reg <<< 2) | {{(WIDTH-2){1'b0}}, (2'd3 - q_mag)};
            end
        end
    end

    register #(.WIDTH(WIDTH)) reg_Q_pos (
        .clk       (clk),
        .rst_n     (rst_n),
        .load_en   (c[6]),
        .shift_en  (1'b0),
        .sr        (1'b0),
        .sl        (1'b0),
        .shift_dir (1'b0),
        .d         (Q_pos_d),
        .q         (Q_pos_reg)
    );

    register #(.WIDTH(WIDTH)) reg_Q_neg (
        .clk       (clk),
        .rst_n     (rst_n),
        .load_en   (c[6]),
        .shift_en  (1'b0),
        .sr        (1'b0),
        .sl        (1'b0),
        .shift_dir (1'b0),
        .d         (Q_neg_d),
        .q         (Q_neg_reg)
    );

    // -----------------------------------------------------------------
    // Output tri-state buses (mirrors booth.sv pattern)
    // -----------------------------------------------------------------
    tri [WIDTH-1:0] output_buffer;

    tristate_buffer_bus #(WIDTH) quot_out (
        .data_in  (Q_pos_reg),
        .enable   (c[7]),
        .data_out (output_buffer)
    );

    // Remainder: top WIDTH bits of collapsed PR (drop the 2 guard bits)
    logic [WIDTH-1:0] remainder;
    assign remainder = pr_collapsed[WIDTH-1:0];

    tristate_buffer_bus #(WIDTH) rem_out (
        .data_in  (remainder),
        .enable   (c[8]),
        .data_out (output_buffer)
    );

    assign outbus = output_buffer;

endmodule // srt4_div

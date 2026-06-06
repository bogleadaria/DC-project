//--------------------------------------------------------------------------
// Design Name: SRT Radix-4 Division — Control Unit
// File Name: cu_srt4.sv
// Description: Mealy/Moore FSM that sequences the SRT radix-4 division
//              datapath (srt4_div.sv).  Each ITERATE state produces two
//              quotient bits per clock cycle (radix-4), so an 8-bit
//              division requires exactly 4 iterations.
//
// Control-signal bus  c[9:0]  (active-high, combinational):
//
//   c[0]  — load_dividend : load {dividend, 0} into the PR registers
//   c[1]  — load_divisor  : load divisor into the D register
//   c[2]  — csa_en        : enable CSA + PR update (one iteration)
//   c[3]  — sub_sel[1]    : MSB of the divisor-multiple select (see below)
//   c[4]  — sub_sel[0]    : LSB of the divisor-multiple select
//   c[5]  — cnt_en        : increment the iteration counter
//   c[6]  — otf_en        : enable on-the-fly quotient update
//   c[7]  — out_quot      : drive quotient onto outbus
//   c[8]  — out_rem       : drive remainder onto outbus
//   c[9]  — restore_en    : final remainder restore if needed
//
// sub_sel encoding (c[4:3]):
//   2'b00 =>  0·D  (add zero — PR unchanged structurally)
//   2'b01 => +1·D  (subtract  D from PR, i.e. PR ← PR − D)
//   2'b10 => +2·D  (subtract 2D from PR, i.e. PR ← PR − 2D)
//   2'b11 => −1·D  (add       D to PR, i.e. PR ← PR + D)
//   (−2·D encoded as two successive −1·D is not used; see note below)
//
// Quotient digit encoding fed back from srt4_div (q_sel[2:0], signed):
//   3'b010 => +2
//   3'b001 => +1
//   3'b000 =>  0
//   3'b111 => −1
//   3'b110 => −2
//
// On-the-fly conversion:
//   Two registers Q_pos and Q_neg maintain the positive and negative
//   partial quotients.  Updated each iteration by the datapath according
//   to the selected digit; the final two's-complement quotient is Q_pos.
//
// States:
//   IDLE       — wait for start
//   LOAD_D     — register the divisor (c[1])
//   LOAD_DVD   — register the dividend / initialise PR (c[0])
//   ITERATE    — run one radix-4 step (c[2..6])
//   CHECK      — decide: more iterations or done?
//   RESTORE    — conditional final-remainder correction (c[9])
//   OUT_QUOT   — drive quotient (c[7])
//   OUT_REM    — drive remainder (c[8])
//   STOP       — assert done, return to IDLE
// -------------------------------------------------------------------------
`timescale 1ns/1ps

module cu_srt4 #(parameter ITER_BITS = 3) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,

    // From datapath
    input  logic        count_done,   // iteration counter reached ITERS-1
    input  logic [2:0]  q_sel,        // signed quotient digit from LUT
    input  logic        rem_sign,     // sign bit of final partial remainder

    // To datapath
    output logic        stop,
    output logic [9:0]  c             // control bus
);

    // -----------------------------------------------------------------
    // State encoding
    // -----------------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE     = 4'd0,
        LOAD_D   = 4'd1,
        LOAD_DVD = 4'd2,
        ITERATE  = 4'd3,
        CHECK    = 4'd4,
        RESTORE  = 4'd5,
        OUT_QUOT = 4'd6,
        OUT_REM  = 4'd7,
        STOP     = 4'd8
    } state_t;

    state_t state, next;

    // -----------------------------------------------------------------
    // State register — synchronous reset, matching dff.sv convention
    // -----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next;
    end

    // -----------------------------------------------------------------
    // Next-state + output logic
    // -----------------------------------------------------------------
    always_comb begin
        // Safe defaults — all signals de-asserted
        next = state;
        stop = 1'b0;
        c    = 10'b0;

        case (state)

            // --------------------------------------------------------
            IDLE: begin
                if (start)
                    next = LOAD_D;
            end

            // --------------------------------------------------------
            // Cycle 1: latch divisor into D register
            LOAD_D: begin
                c[1] = 1'b1;   // load_divisor
                next = LOAD_DVD;
            end

            // --------------------------------------------------------
            // Cycle 2: latch dividend; initialise PR = {dividend, 0}
            LOAD_DVD: begin
                c[0] = 1'b1;   // load_dividend
                next = ITERATE;
            end

            // --------------------------------------------------------
            // Iteration: one radix-4 step
            //   1. The LUT (combinational, in datapath) has already
            //      evaluated q_sel from the current PR and D.
            //   2. sub_sel (c[4:3]) replicates q_sel's magnitude/sign
            //      choice to the adder/CSA network.
            //   3. cnt_en and otf_en advance counter and OTF registers.
            ITERATE: begin
                c[2] = 1'b1;   // csa_en — update partial remainder

                // Map signed quotient digit to sub_sel
                // +2 => 2'b10 (subtract 2D)
                // +1 => 2'b01 (subtract  D)
                //  0 => 2'b00 (add     0·D)
                // -1 => 2'b11 (add       D)
                // -2 => 2'b10 with sign inversion handled in datapath
                //       (subtract −2D = add 2D); datapath uses rem_sign
                //       to know the sign of q_sel[2].
                case (q_sel)
                    3'b010: begin c[4] = 1'b0; c[3] = 1'b1; end  // +2 → sub 2D
                    3'b001: begin c[4] = 1'b1; c[3] = 1'b0; end  // +1 → sub  D
                    3'b000: begin c[4] = 1'b0; c[3] = 1'b0; end  //  0 → no-op
                    3'b111: begin c[4] = 1'b1; c[3] = 1'b1; end  // -1 → add  D
                    3'b110: begin c[4] = 1'b0; c[3] = 1'b1; end  // -2 → add 2D
                    default: begin c[4] = 1'b0; c[3] = 1'b0; end
                endcase

                c[5] = 1'b1;   // cnt_en  — advance iteration counter
                c[6] = 1'b1;   // otf_en  — advance OTF quotient registers
                next = CHECK;
            end

            // --------------------------------------------------------
            CHECK: begin
                if (count_done)
                    next = RESTORE;
                else
                    next = ITERATE;
            end

            // --------------------------------------------------------
            // Final remainder restoration:
            //   If PR < 0 after all iterations, add back D once
            //   (standard SRT correction step).
            RESTORE: begin
                if (rem_sign) begin
                    c[9] = 1'b1;  // restore_en
                end
                next = OUT_QUOT;
            end

            // --------------------------------------------------------
            OUT_QUOT: begin
                c[7] = 1'b1;  // out_quot
                next = OUT_REM;
            end

            // --------------------------------------------------------
            OUT_REM: begin
                c[8] = 1'b1;  // out_rem
                next = STOP;
            end

            // --------------------------------------------------------
            STOP: begin
                stop = 1'b1;
                next = IDLE;
            end

            default: next = IDLE;

        endcase
    end

endmodule // cu_srt4

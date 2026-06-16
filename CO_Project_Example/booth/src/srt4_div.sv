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
//--------------------------------------------------------------------------
// Design Name : Signed 8-bit Divider (Restoring Algorithm)
// File Name   : srt4_div.sv
// Description : Inlocuire drop-in pentru srt4_div.sv original care avea
//               o problema algoritmica (PR nu era normalizat pentru SRT).
//               Foloseste restoring division clasic pe 8 biti:
//                 - semn calculat separat
//                 - impartire unsigned pe valori absolute, 8 iteratii
//                 - corectie semn la final
//               Aceeasi interfata externa (inbus, outbus, enable, done).
//
// Protocol inbus (identic cu booth.sv si cu alu_top.sv):
//   Ciclu LOAD_D  (c[0]=1 din cu_alu): divisor pe inbus
//   Ciclu LOAD_DVD(c[1]=1 din cu_alu): dividend pe inbus
//   Dupa ITERS=8 iteratii: done=1, outbus=quotient
//--------------------------------------------------------------------------
`timescale 1ns/1ps
 
module srt4_div #(parameter WIDTH = 8) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     enable,
    input  logic signed [WIDTH-1:0]  inbus,
    output logic                     done,
    output logic        [WIDTH-1:0]  outbus,
    output logic        [WIDTH-1:0]  q_pos_out   // alias pentru mux in alu_top
);
 
    localparam int ITERS = WIDTH;  // 8 iteratii pentru 8 biti
 
    typedef enum logic [2:0] {
        IDLE    = 3'd0,
        LOAD_D  = 3'd1,
        LOAD_N  = 3'd2,   // incarca deimpartitul (N = |dividend|)
        RUN     = 3'd3,
        FIXUP   = 3'd4,   // corectie semn
        OUT_Q   = 3'd5,
        STOP    = 3'd6
    } state_t;
 
    state_t state;
 
    // ------------------------------------------------------------------
    // Registre interne
    // ------------------------------------------------------------------
    logic signed [WIDTH-1:0]  dividend_r;  // deimpartitul original (cu semn)
    logic signed [WIDTH-1:0]  divisor_r;   // impartitorul original (cu semn)
    logic        [WIDTH-1:0]  N;           // |dividend| — unsigned
    logic        [WIDTH-1:0]  D;           // |divisor|  — unsigned
    logic        [WIDTH-1:0]  Q;           // catul unsigned in constructie
    logic        [WIDTH:0]    PR;          // partial remainder (WIDTH+1 biti)
    logic        [2:0]        iter_cnt;    // 0..7
 
    logic neg_result;  // semnul catului
 
    // ------------------------------------------------------------------
    // Outbus tristate (acelasi pattern ca booth.sv)
    // ------------------------------------------------------------------
    tri [WIDTH-1:0] output_buffer;
 
    tristate_buffer_bus #(WIDTH) q_drv (
        .data_in  (Q),
        .enable   (state == OUT_Q),
        .data_out (output_buffer)
    );
 
    assign outbus    = output_buffer;
    assign q_pos_out = Q;
    assign done      = (state == STOP);
 
    // ------------------------------------------------------------------
    // FSM + Datapath
    // ------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            iter_cnt   <= '0;
            dividend_r <= '0;
            divisor_r  <= '0;
            N          <= '0;
            D          <= '0;
            Q          <= '0;
            PR         <= '0;
            neg_result <= 1'b0;
        end else begin
            case (state)
 
                // --------------------------------------------------------
                IDLE: begin
                    if (enable) begin
                        state    <= LOAD_D;
                        iter_cnt <= '0;
                        Q        <= '0;
                        PR       <= '0;
                    end
                end
 
                // --------------------------------------------------------
                // Ciclu 1: citeste divisor de pe inbus
                LOAD_D: begin
                    divisor_r <= inbus;
                    state     <= LOAD_N;
                end
 
                // --------------------------------------------------------
                // Ciclu 2: citeste dividend de pe inbus
                //   Calculeaza valori absolute si semnul catului
                LOAD_N: begin
                    dividend_r <= inbus;
                    // |dividend|
                    N <= (inbus[WIDTH-1]) ? (~inbus + 1'b1) : inbus;
                    // |divisor|
                    D <= (divisor_r[WIDTH-1]) ? (~divisor_r + 1'b1) : divisor_r;
                    // semn cat: XOR semne
                    neg_result <= inbus[WIDTH-1] ^ divisor_r[WIDTH-1];
                    iter_cnt   <= '0;
                    Q          <= '0;
                    PR         <= '0;
                    state      <= RUN;
                end
 
                // --------------------------------------------------------
                // Restoring division — 1 bit/ciclu, WIDTH iteratii
                //
                //   PR = (PR << 1) | N[MSB]
                //   N  =  N << 1
                //   if PR >= D: PR -= D, Q = (Q<<1)|1
                //   else:       Q = (Q<<1)|0
                // --------------------------------------------------------
                RUN: begin
                    automatic logic [WIDTH:0]  pr_shift;
                    automatic logic [WIDTH:0]  pr_trial;
 
                    pr_shift = {PR[WIDTH-1:0], N[WIDTH-1]};  // shift in MSB of N
                    N        <= N << 1;
 
                    pr_trial = pr_shift - {1'b0, D};
 
                    if (!pr_trial[WIDTH]) begin  // pr_trial >= 0
                        PR <= pr_trial;
                        Q  <= (Q << 1) | 1'b1;
                    end else begin
                        PR <= pr_shift;
                        Q  <= (Q << 1) | 1'b0;
                    end
 
                    if (iter_cnt == WIDTH-1)
                        state <= FIXUP;
                    else
                        iter_cnt <= iter_cnt + 1'b1;
                end
 
                // --------------------------------------------------------
                // Corectie semn: daca neg_result, Q = -Q (complement fata de 2)
                FIXUP: begin
                    if (neg_result)
                        Q <= (~Q + 1'b1);
                    state <= OUT_Q;
                end
 
                // --------------------------------------------------------
                OUT_Q: state <= STOP;
 
                // --------------------------------------------------------
                STOP: state <= IDLE;
 
                default: state <= IDLE;
            endcase
        end
    end
 
endmodule // srt4_div // srt4_div

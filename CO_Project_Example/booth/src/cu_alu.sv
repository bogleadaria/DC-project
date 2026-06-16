//--------------------------------------------------------------------------
// Design Name : ALU Control Unit
//--------------------------------------------------------------------------
// Design Name : ALU Control Unit
// File Name   : cu_alu.sv
// Description : Master FSM for alu_top. Sequences LOAD_A/LOAD_B for
//               serial units (Booth, SRT-4), dispatches all ops, waits
//               for done, then latches result via c[9].
//
// FIX — WAIT state: serial units now go through LATCH (one extra cycle)
//        instead of jumping directly to DONE. This gives booth_captured /
//        div_captured one clock cycle to register the done_booth/done_div
//        output before c[9] latches the mux result into `result`.
//--------------------------------------------------------------------------
`timescale 1ns / 1ps
//--------------------------------------------------------------------------
// cu_alu.sv
//
// Secventa Booth/DIV:
//   IDLE -> BOOTH_RST (reset booth/div, fara enable)
//        -> LOAD_EN   (enable=1, inbus=Z inca)
//        -> LOAD_A    (c[0]: primul operand pe inbus)
//        -> LOAD_B    (c[1]: al doilea operand pe inbus)
//        -> DISPATCH  -> WAIT -> LATCH -> DONE
//
// Separarea BOOTH_RST de LOAD_EN rezolva conflictul
// rst_n=0 si enable=1 in acelasi ciclu.
//--------------------------------------------------------------------------
 
module cu_alu (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [3:0]  opcode,
    input  logic        done_booth,
    input  logic        done_div,
    input  logic        done_shift,
    output logic        stop,
    output logic [9:0]  c,
    output logic [3:0]  opcode_out,
    output logic        booth_rst_req  // cerere reset booth (ciclu inainte de enable)
);
 
typedef enum logic [3:0] {
    IDLE      = 4'd0,
    BOOTH_RST = 4'd1,   // reset booth/div — fara enable
    LOAD_EN   = 4'd2,   // enable=1, booth iese din reset si porneste
    LOAD_A    = 4'd3,   // c[0]: primul operand pe inbus
    LOAD_B    = 4'd4,   // c[1]: al doilea operand pe inbus
    DISPATCH  = 4'd5,
    WAIT      = 4'd6,
    LATCH     = 4'd7,
    DONE      = 4'd8
} state_t;
 
state_t state, next;
 
logic [3:0] opcode_r;
 
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        opcode_r <= 4'b0;
    else if (state == IDLE && start)
        opcode_r <= opcode;
end
 
assign opcode_out = opcode_r;
 
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else        state <= next;
end
 
logic needs_inbus;
always_comb begin
    case (opcode)
        4'b0010, 4'b0011: needs_inbus = 1'b1;
        default:          needs_inbus = 1'b0;
    endcase
end
 
logic active_done;
always_comb begin
    case (opcode_r)
        4'b0010:          active_done = done_booth;
        4'b0011:          active_done = done_div;
        4'b0111, 4'b1000: active_done = done_shift;
        default:          active_done = 1'b1;
    endcase
end
 
logic is_serial;
always_comb begin
    case (opcode_r)
        4'b0010, 4'b0011: is_serial = 1'b1;
        default:          is_serial = 1'b0;
    endcase
end
 
always_comb begin
    next = state;
    case (state)
        IDLE:      if (start) next = needs_inbus ? BOOTH_RST : DISPATCH;
        BOOTH_RST:            next = LOAD_EN;   // un ciclu de reset, apoi enable
        LOAD_EN:              next = LOAD_A;
        LOAD_A:               next = LOAD_B;
        LOAD_B:               next = DISPATCH;
        DISPATCH:             next = WAIT;
        WAIT:      if (active_done) next = LATCH;
        LATCH:                next = DONE;
        DONE:                 next = IDLE;
        default:              next = IDLE;
    endcase
end
 
always_comb begin
    stop          = 1'b0;
    c             = 10'b0;
    booth_rst_req = 1'b0;
 
    // Semnale stabile in faza activa
    if (state == DISPATCH || state == WAIT || state == LATCH) begin
        case (opcode_r)
            4'b0000: c[5] = 1'b0;
            4'b0001: c[5] = 1'b1;
            4'b0100: begin c[7]=1'b0; c[6]=1'b0; end
            4'b0101: begin c[7]=1'b0; c[6]=1'b1; end
            4'b0110: begin c[7]=1'b1; c[6]=1'b0; end
            4'b0111: c[8] = 1'b0;
            4'b1000: c[8] = 1'b1;
            default: ;
        endcase
    end
 
    case (state)
        // Ciclu de reset pentru booth/div — fara enable inca
        BOOTH_RST: begin
            booth_rst_req = 1'b1;  // semnalul de reset catre alu_top
        end
 
        // Enable booth/div — booth e deja in IDLE curat dupa reset
        LOAD_EN: begin
            case (opcode_r)
                4'b0010: c[2] = 1'b1;  // enable_booth
                4'b0011: c[3] = 1'b1;  // enable_div
                default: ;
            endcase
        end
 
        LOAD_A: c[0] = 1'b1;
 
        LOAD_B: c[1] = 1'b1;
 
        DISPATCH: begin
            if (opcode_r == 4'b0111 || opcode_r == 4'b1000)
                c[4] = 1'b1;
        end
 
        WAIT: begin
            // Serial: c[9]=1 exact pe done (booth_q_reg/div_q_pos valide acum)
            if (active_done && is_serial)
                c[9] = 1'b1;
        end
 
        LATCH: begin
            // Combinational si shift: c[9]=1 un ciclu dupa done
            if (!is_serial)
                c[9] = 1'b1;
        end
 
        DONE: stop = 1'b1;
 
        default: ;
    endcase
end
 
endmodule// cu_alu

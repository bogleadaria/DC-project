//--------------------------------------------------------------------------
// Design Name: Shift Unit
// File Name: shift_unit.sv
// Description: Performs logical left shift (A << B) or right shift (A >> B).
//              Uses register.sv in shift mode (shift_dir=0 for left,
//              shift_dir=1 for right) driven by counter_nbits for B cycles.
//              Asserts done one cycle after the counter reaches B.
//
//   shift_dir | operation
//      0       | LEFT  SHIFT  (A << B)
//      1       | RIGHT SHIFT  (A >> B)
//
// Interface:
//   clk, rst_n  — standard clock / active-low reset
//   start       — pulse high for one cycle to begin a shift
//   shift_dir   — direction: 0=left, 1=right
//   a           — value to shift
//   b           — number of positions (unsigned)
//   result      — shifted output (held after done)
//   done        — high for one cycle when shift is complete
//
// -------------------------------------------------------------------------
`timescale 1ns/1ps

module shift_unit #(parameter WIDTH = 8) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic               shift_dir,   // 0=left, 1=right
    input  logic [WIDTH-1:0]   a,
    input  logic [WIDTH-1:0]   b,           // shift amount (0..WIDTH)
    output logic [WIDTH-1:0]   result,
    output logic               done
);

    // -----------------------------------------------------------------
    // Counter — counts how many shifts have been performed.
    // WIDTH bits wide so it can reach any shift amount 0..WIDTH-1.
    // -----------------------------------------------------------------
    logic               cnt_en;
    logic [WIDTH-1:0]   cnt_out;

    counter_nbits #(.WIDTH(WIDTH)) shift_cnt (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (cnt_en),
        .count (cnt_out)
    );

    // -----------------------------------------------------------------
    // Register — holds the data being shifted.
    // load_en loads A on start; shift_en advances one position per cycle.
    // sr (shift-right serial input) = 0 → logical shift (fill with zero).
    // sl (shift-left  serial input) = 0 → logical shift (fill with zero).
    // -----------------------------------------------------------------
    logic load_en;
    logic shift_en;

    register #(.WIDTH(WIDTH)) shift_reg (
        .clk       (clk),
        .rst_n     (rst_n),
        .load_en   (load_en),
        .shift_en  (shift_en),
        .sr        (1'b0),          // logical shift: fill with 0
        .sl        (1'b0),          // logical shift: fill with 0
        .shift_dir (shift_dir),
        .d         (a),
        .q         (result)
    );

    // -----------------------------------------------------------------
    // FSM — three states: IDLE, LOAD, SHIFTING
    // -----------------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE     = 2'b00,
        LOAD     = 2'b01,
        SHIFTING = 2'b10
    } state_t;

    state_t state, next_state;

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-state logic
    // cnt_out is compared against b.  We start counting from 1 on the
    // first shift cycle, so the shift is complete when cnt_out == b.
    // When b==0, skip straight back to IDLE from LOAD without shifting.
    always_comb begin
        next_state = state;
        case (state)
            IDLE:     if (start)              next_state = LOAD;
            LOAD:     if (b == '0)            next_state = IDLE;   // shift by 0
                      else                    next_state = SHIFTING;
            SHIFTING: if (cnt_out == b)       next_state = IDLE;
            default:                          next_state = IDLE;
        endcase
    end

    // Output / datapath control
    always_comb begin
        load_en  = 1'b0;
        shift_en = 1'b0;
        cnt_en   = 1'b0;
        done     = 1'b0;

        case (state)
            IDLE: begin
                // nothing — register holds previous result
            end

            LOAD: begin
                load_en = 1'b1;   // latch A into the register
                // When b==0 the result is just A; assert done immediately
                if (b == '0)
                    done = 1'b1;
            end

            SHIFTING: begin
                shift_en = 1'b1;  // advance register one step
                cnt_en   = 1'b1;  // advance counter
                // done on the last shift (cnt_out reaches b after this edge)
                if (cnt_out == b - 1)
                    done = 1'b1;
            end

            default: ;
        endcase
    end

endmodule // shift_unit

//--------------------------------------------------------------------------
// Design Name: Booth Multiplication Algorithm 
// File Name: booth_parts.sv
// Description: Implementation of the Booth Multiplication Algorithm
// Version History
// * June 9, 2025 (sebastian ardelean): Finished the implementation 

//Modificari: - Am inlocuit instantele register reg_A, q_Q, reg_Qm cu blocuri 
// always_ff explicite pentru control mai bun al reset-ului
// - A_reg se reseteaza acum la 0 in LOAD_M (c[0]) intre operatii
// - Adaugat port output q_reg_out (Q_reg direct) necesar in alu_top.sv
// pentru a citi rezultatul Booth fara tristate bus
// -------------------------------------------------------------------------
`timescale 1ns/1ps

module booth (
    input  logic        clk,
    input  logic        enable,
    input  logic        rst_n,
    input  logic signed [7:0] inbus,
    output logic        done,
    output logic [7:0]  outbus,
    output logic [7:0]  q_reg_out    // ← NOU: Q_reg direct
);
   //control signals
   logic [7:0] c;
   logic       stop;
   
   tri [7:0]  output_buffer;
   
   // Register Outputs
   logic signed [7:0] A_reg, M_reg, Q_reg;
   logic	      Qm;
   logic signed [7:0] M_input;
   logic signed [7:0] Q_input;
   // Count
   logic [2:0] counter_o;
   logic       count_and_o;

   // Other intermediate signals
   logic signed [7:0] adder_o;
   logic [7:0]	      xor_o;

   logic signed [7:0] A_outbus;
   logic signed [7:0] Q_outbus;
   
   
   cu_booth ctrl_unit (
		 .clk(clk),
		 .start(enable),
		 .rst_n(rst_n),
		 .count(count_and_o),
		 .q0(Q_reg[0]),
		 .qm(Qm),
		 .stop(stop),
		 .c(c)
		 );
   
   assign done = stop;
  
   counter_nbits #(.WIDTH(3)) counter (
			  .clk(clk),
			  .rst_n(rst_n),
			  .en(c[5]),
			  .count(counter_o)
			  );

   and3_gate and_counter (
		       .a(counter_o[0]),
		       .b(counter_o[1]),
		       .c(counter_o[2]),
		       .y(count_and_o)
		       );
   
      
// Înlocuire reg_A instanțiat cu acest bloc direct în booth.sv:
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        A_reg <= 8'b0;
    end else begin
        if (c[0]) begin
            // LOAD_M: resetează A_reg la 0 pentru calcul proaspăt
            A_reg <= 8'b0;
        end else if (c[2]) begin
            // SCAN: încarcă rezultatul adunării
            A_reg <= adder_o;
        end else if (c[4]) begin
            // SHIFT: shift aritmetic dreapta
            A_reg <= {A_reg[7], A_reg[7:1]};
        end
    end
end
   
  // Înlocuire instanțele q_Q și reg_Qm cu blocuri always_ff:

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        Q_reg <= 8'b0;
        Qm    <= 1'b0;
    end else begin
        if (c[0]) begin
            // LOAD_M: resetează Q și Qm pentru operație nouă
            Q_reg <= 8'b0;
            Qm    <= 1'b0;
        end else if (c[1]) begin
            // LOAD_Q: încarcă multiplicatorul de pe inbus
            Q_reg <= Q_input;
            Qm    <= 1'b0;
        end else if (c[4]) begin
            // SHIFT: shift aritmetic dreapta
            Q_reg <= {A_reg[0], Q_reg[7:1]};
            Qm    <= Q_reg[0];
        end
    end
end
	      

   register #(.WIDTH(8)) reg_M (
				.clk(clk),
				.rst_n(rst_n),
				.load_en(c[0]),
				.shift_en(1'b0),
				.sr(1'b0),
                                .sl(1'b0),
                                .shift_dir(1'b0),
				.d(M_input),
				.q(M_reg)
				);
   xorn_gate #(8) xor_instance (
			   .a(M_reg),
			   .b(c[3]),
			   .y(xor_o)
			   );

   adder #(8) adder_instance (
			      .cin(c[3]),
			      .a(A_reg),
			      .b(xor_o),
			      .sum(adder_o)
			      );
//     // detect rising edge of enable (start pulse)
//    logic enable_d;
//    always_ff @(posedge clk or negedge rst_n)
//        if (!rst_n) enable_d <= 1'b0;
//        else        enable_d <= enable;
//    logic enable_rise;
//    assign enable_rise = enable & ~enable_d;
  
  
  

   // Tri-state buffers

   tristate_buffer_bus #(8) M_in (
				   .data_in(inbus),
				   .enable(c[0]),
				   .data_out(M_input)
				   );

   tristate_buffer_bus #(8) Q_in (
				   .data_in(inbus),
				   .enable(c[1]),
				   .data_out(Q_input)
				   );
   tristate_buffer_bus #(8) A_out (
				   .data_in(A_reg),
				   .enable(c[6]),
				   .data_out(output_buffer)
				   );

   tristate_buffer_bus #(8) Q_out (
				   .data_in(Q_reg),
				   .enable(c[7]),
				   .data_out(output_buffer)
				   );

   assign outbus = output_buffer;
   assign q_reg_out = Q_reg;           // ← adaugă la final, înainte de endmodule
   
   

  
endmodule // booth

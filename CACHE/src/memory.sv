`include "defs.svh"
`timescale 1ns/1ps

module memory
  #(parameter ADDRESS_WIDTH = 18,
    parameter BLOCK_SIZE = 256,
    parameter WORD_SIZE = 32,
    parameter FILE = ""
    )
   (
    input logic clock,
    input logic [BLOCK_SIZE - 1:0] din,
    input logic [ADDRESS_WIDTH - 1:0] address,
    input logic rden,
    input logic wren,
    input logic [(BLOCK_SIZE/WORD_SIZE) - 1:0] wmask,
    output logic [BLOCK_SIZE -1:0] dout
    );

   localparam DEPTH = 2 ** 18;
   
   reg [BLOCK_SIZE-1:0] mem [0:DEPTH-1];
   integer              i;

   initial begin
        //read file content
        if (FILE != "")
          $readmemh(FILE, mem);
        else
          for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {BLOCK_SIZE{1'b0}};
   end

   always_ff @(posedge clock) begin
        if (wren) begin
           // Write only the words enabled by the mask
           for (int j = 0; j < (BLOCK_SIZE/WORD_SIZE); j++) begin
              if (wmask[j]) begin
                 mem[address][j*WORD_SIZE +: WORD_SIZE] <= din[j*WORD_SIZE +: WORD_SIZE];
              end
           end
        end
   end

   always_ff @(posedge clock) begin
        if (rden)
          dout <= mem[address];
   end

endmodule // memory

`timescale 1ns/1ps
// Testbench for srt4_div
module srt4_div_tb;
   logic        clk;
   logic        rst_n;
   logic        start;
   logic signed [7:0] inbus;
   logic [7:0]  outbus;
   logic        done;

   // Instantiate the DUT
   srt4_div dut (
		  .clk(clk),
		  .rst_n(rst_n),
		  .enable(start),
		  .inbus(inbus),
		  .done(done),
		  .outbus(outbus)
		  );

   initial
     begin
	$dumpfile("srt4_div_tb.vcd");
	$dumpvars;
     end

   // Clock generation
   always #5 clk = ~clk;
   initial forever begin
      #1;
      $display("time=%0t  state=%0d  c=%010b  q_sel=%03b  pr_s=%0d  pr_c=%0d  Q_pos=%0d  done=%b",
	       $time,
	       dut.ctrl.state,
	       dut.c,
	       dut.q_sel,
	       $signed(dut.pr_s_reg),
	       $signed(dut.pr_c_reg),
	       $signed(dut.Q_pos_reg),
	       done);
   end

   // Helper task: drive one division and print the result.
   // Protocol (mirrors booth_tb):
   //   - put divisor on inbus, pulse start for one cycle
   //   - put dividend on inbus one cycle later
   //   - wait for done
   //   - read quotient (outbus while OUT_QUOT), remainder one cycle later
   task do_div;
      input signed [7:0] dividend;
      input signed [7:0] divisor;
      input [63:0]       test_num;

      logic signed [7:0] got_quot;
      logic signed [7:0] got_rem;
      begin
	 $display("--- Test %0d:  %0d / %0d ---", test_num, dividend, divisor);

	 // Cycle: assert start, put divisor on inbus (LOAD_D will latch it)
	 start = 1;
	 inbus = divisor;
	 #10;

	 // Cycle: de-assert start, put dividend on inbus (LOAD_DVD will latch it)
	 start = 0;
	 inbus = dividend;
	 #10;

	 // Operands are loaded; inbus no longer matters
	 inbus = 8'd0;

	 // Wait for the FSM to finish
	 wait (done);

	 // Capture quotient -- outbus is valid on the done (OUT_QUOT) cycle
	 got_quot = $signed(outbus);
	 $display("  Quotient  = %0d  (outbus=%0d)", got_quot, $signed(outbus));

	 // One clock later: OUT_REM drives the remainder
	 #10;
	 got_rem = $signed(outbus);
	 $display("  Remainder = %0d  (outbus=%0d)", got_rem, $signed(outbus));

	 // Brief gap before next test
	 #20;
      end
   endtask

   // Stimulus
   initial begin
      $display("Starting SRT Radix-4 Divider Testbench...");

      clk   = 0;
      rst_n = 0;
      start = 0;
      inbus = 8'd0;

      // Reset pulse
      #10;
      rst_n = 1;
      $display("Reset released.");

      // ------------------------------------------------------------------
      // Test 1: simple positive / positive, no remainder
      // Expected: 20 / 4 = Q=5, R=0
      // ------------------------------------------------------------------
      do_div(8'sd20, 8'sd4, 1);

      // ------------------------------------------------------------------
      // Test 2: positive / positive with remainder
      // Expected: 21 / 4 = Q=5, R=1
      // ------------------------------------------------------------------
      do_div(8'sd21, 8'sd4, 2);

      // ------------------------------------------------------------------
      // Test 3: positive dividend / negative divisor
      // Expected: 20 / -4 = Q=-5, R=0
      // ------------------------------------------------------------------
      do_div(8'sd20, -8'sd4, 3);

      // ------------------------------------------------------------------
      // Test 4: negative dividend / positive divisor
      // Expected: -21 / 4 = Q=-5, R=-1
      // ------------------------------------------------------------------
      do_div(-8'sd21, 8'sd4, 4);

      // ------------------------------------------------------------------
      // Test 5: negative / negative
      // Expected: -20 / -4 = Q=5, R=0
      // ------------------------------------------------------------------
      do_div(-8'sd20, -8'sd4, 5);

      // ------------------------------------------------------------------
      // Test 6: dividend = 0
      // Expected: 0 / 5 = Q=0, R=0
      // ------------------------------------------------------------------
      do_div(8'sd0, 8'sd5, 6);

      // ------------------------------------------------------------------
      // Test 7: dividend < divisor  (quotient = 0)
      // Expected: 3 / 10 = Q=0, R=3
      // ------------------------------------------------------------------
      do_div(8'sd3, 8'sd10, 7);

      // ------------------------------------------------------------------
      // Test 8: dividend = divisor  (quotient = 1)
      // Expected: 13 / 13 = Q=1, R=0
      // ------------------------------------------------------------------
      do_div(8'sd13, 8'sd13, 8);

      // ------------------------------------------------------------------
      // Test 9: large magnitude  (max positive / small divisor)
      // Expected: 127 / 3 = Q=42, R=1
      // ------------------------------------------------------------------
      do_div(8'sd127, 8'sd3, 9);

      // ------------------------------------------------------------------
      // Test 10: min negative / positive
      // Expected: -128 / 3 = Q=-42, R=-2
      // ------------------------------------------------------------------
      do_div(-8'sd128, 8'sd3, 10);

      // ------------------------------------------------------------------
      // Test 11: reset mid-operation
      //   Start a division, cut it short with rst_n=0, then reissue.
      //   Expected after re-start: 36 / 6 = Q=6, R=0
      // ------------------------------------------------------------------
      $display("--- Test 11: reset mid-operation ---");
      start = 1;
      inbus = 8'sd6;   // divisor for the aborted run
      #10;
      start = 0;
      inbus = 8'sd99;  // dividend -- we will abort before done
      #10;
      inbus = 8'd0;
      // Let it run a couple of cycles then slam reset
      #20;
      rst_n = 0;
      $display("  rst_n asserted mid-flight at time=%0t", $time);
      #20;
      rst_n = 1;
      $display("  rst_n released, restarting clean division...");
      #10;
      do_div(8'sd36, 8'sd6, 11);

      $display("Test complete.");
      $finish;
   end
endmodule

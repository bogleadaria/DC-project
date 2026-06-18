`timescale 1ns/1ps

module tb_cache;

    // Parameters
    parameter BLOCK_SIZE = 256;
    parameter ADDRESS_WIDTH = 21;
    parameter WORD_SIZE = 32;

    // Clock and Reset
    logic clock;
    logic rst_n;

    // CPU to Cache Signals
    logic [ADDRESS_WIDTH - 1:0] caddress;
    logic [WORD_SIZE - 1:0]     cdin;
    logic                       rden;
    logic                       wren;
    logic                       hit;
    logic [WORD_SIZE - 1:0]     cdout;

    // Cache to Memory Signals
    logic [BLOCK_SIZE - 1:0]    mdin;
    logic [BLOCK_SIZE - 1:0]    mdout;
    logic [17:0]                maddress; // TAG + INDEX = 8 + 10 = 18 bits
    logic                       mrden;
    logic                       mwren;
    logic [(BLOCK_SIZE/WORD_SIZE)-1:0] mwmask;

    // Instantiate the Cache Controller
    cache_controller #(
        .BLOCK_SIZE(BLOCK_SIZE),
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .WORD_SIZE(WORD_SIZE)
    ) uut_cache (
        .clock(clock),
        .rst_n(rst_n),
        .caddress(caddress),
        .cdin(cdin),
        .mdin(mdin),
        .rden(rden),
        .wren(wren),
        .hit(hit),
        .cdout(cdout),
        .mdout(mdout),
        .maddress(maddress),
        .mrden(mrden),
        .mwren(mwren),
        .mwmask(mwmask)
    );

    // Instantiate the Memory
    memory #(
        .BLOCK_SIZE(BLOCK_SIZE),
        .ADDRESS_WIDTH(18),
        .WORD_SIZE(WORD_SIZE)
    ) uut_mem (
        .clock(clock),
        .din(mdout),
        .address(maddress),
        .rden(mrden),
        .wren(mwren),
        .wmask(mwmask),
        .dout(mdin)
    );

    // Clock Generation
    initial begin
        clock = 0;
        forever #5 clock = ~clock; // 10ns period (100 MHz)
    end

    // CPU Tasks for cleaner code
    task cpu_write(input logic [ADDRESS_WIDTH-1:0] addr, input logic [WORD_SIZE-1:0] data);
        @(posedge clock);
        caddress = addr;
        cdin = data;
        wren = 1;
        @(posedge clock);
        wren = 0; // Pulse write enable
        wait(hit == 1); // Wait for cache to signal completion
        $display("[%0t] WRITE SUCCESS: Addr=0x%0h, Data=0x%0h", $time, addr, data);
    endtask

    task cpu_read(input logic [ADDRESS_WIDTH-1:0] addr);
        @(posedge clock);
        caddress = addr;
        rden = 1;
        @(posedge clock);
        rden = 0; // Pulse read enable
        wait(hit == 1); // Wait for cache to signal completion
        $display("[%0t] READ SUCCESS:  Addr=0x%0h, Data=0x%0h", $time, addr, cdout);
    endtask

    // Test Sequence
    initial begin
        // 1. Initialize and Reset
        rst_n = 0;
        caddress = 0;
        cdin = 0;
        rden = 0;
        wren = 0;
        
        #20 rst_n = 1;
        $display("\n--- Starting Cache Tests ---");

        // 2. WRITE MISS (Write-No-Allocate)
        // We write to an empty cache. It should bypass the cache and go to memory.
        #10;
        $display("\n1. Testing Write Miss (Write-No-Allocate)...");
        cpu_write(21'h001000, 32'hDEADBEEF); // Tag=0, Index=200, Offset=0

        // 3. READ MISS
        // We read from the same address. Cache must fetch the block from memory.
        // We should get our DEADBEEF data back.
        #10;
        $display("\n2. Testing Read Miss (Fetching block)...");
        cpu_read(21'h001000);
        if (cdout !== 32'hDEADBEEF) $error("FAILED: Expected DEADBEEF");

        // 4. WRITE HIT (Write-Through)
        // Now that the block is in the cache, let's write to the next word in the block.
        // It should update the cache AND write to memory.
        #10;
        $display("\n3. Testing Write Hit (Write-Through)...");
        cpu_write(21'h001001, 32'hCAFEBABE); // Tag=0, Index=200, Offset=1

        // 5. READ HIT
        // Read back the word we just wrote. It should be an instant hit.
        #10;
        $display("\n4. Testing Read Hit...");
        cpu_read(21'h001001);
        if (cdout !== 32'hCAFEBABE) $error("FAILED: Expected CAFEBABE");

        // 6. Verify Memory Consistency
        // We read the original word again. It should still be a hit.
        #10;
        $display("\n5. Verifying original word in block...");
        cpu_read(21'h001000);
        if (cdout !== 32'hDEADBEEF) $error("FAILED: Expected DEADBEEF");

        #50;
        $display("\n--- All Tests Passed Successfully! ---\n");
        $finish;
    end

endmodule

`timescale 1ns/1ps
module tb_llm_bench;
    parameter BYPASS_MODE = 1;
    parameter MEMORY_LATENCY = 5;
    parameter DMEM_WORDS = 2048;
    reg clk = 0, rst = 1;
    wire done;

    llm_bench_top #(
        .BYPASS_MODE(BYPASS_MODE),
        .MEMORY_LATENCY(MEMORY_LATENCY),
        .DMEM_WORDS(DMEM_WORDS)
    ) bench (
        .clk(clk),
        .rst(rst),
        .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (3) @(negedge clk);
        // Avoid racing the memory loader on the reset-release edge.
        #1 rst = 0;
        wait (done);
        $display("PASS llm benchmark");
        $finish;
    end
endmodule

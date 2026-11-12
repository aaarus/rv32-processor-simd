`include "rtl/core/rv32_defs.vh"
module llm_bench_top #(
    parameter BYPASS_MODE = 1,
    parameter MEMORY_LATENCY = 5,
    parameter DMEM_WORDS = 2048
) (
    input clk,
    input rst,
    output reg done = 0
);
    top #(
        .BYPASS_MODE(BYPASS_MODE),
        .MEMORY_LATENCY(MEMORY_LATENCY),
        .DMEM_WORDS(DMEM_WORDS),
        .IMEM_INIT_FILE("build/llm_bench/program.hex")
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    string data_path;
    integer expected;
    integer total_cycles = 0, start_cycle = 0, completed = 0;
    integer instructions = 0, muls = 0, dots = 0, holds = 0, bubbles = 0;
    integer result_writes = 0;
    reg active = 0;
    reg [31:0] stored_result = 32'hdeadbeef;

    initial begin
        if (!$value$plusargs("DATA=%s", data_path)) $fatal(1, "Missing DATA");
        if (!$value$plusargs("EXPECTED=%d", expected)) $fatal(1, "Missing EXPECTED");
    end
    // Load on a reset clock edge, after the memory's own initialization.
    always @(negedge clk) if (rst) $readmemh(data_path, dut.data_mem_inst.memory);
    always @(posedge clk) begin
        if (rst) begin
            done = 0;
            active = 0;
            total_cycles = 0;
            completed = 0;
        end else if (!done) begin
            total_cycles = total_cycles + 1;
            if (total_cycles > 200000) $fatal(1, "Benchmark timeout");
            if (!dut.cache_stall && dut.ex_mem_mem_write &&
                dut.ex_mem_alu_result == 0) begin
                stored_result = dut.ex_mem_rs2_data;
                if (active) result_writes = result_writes + 1;
            end
            if (!dut.cache_stall && dut.id_ex_reg_write && dut.id_ex_rd == 31) begin
                if (dut.id_ex_imm == 1) begin
                    active = 1;
                    start_cycle = total_cycles;
                    instructions = 0;
                    muls = 0;
                    dots = 0;
                    holds = 0;
                    bubbles = 0;
                    result_writes = 0;
                end else if (dut.id_ex_imm == 2) begin
                    if (!active || result_writes != 1 || stored_result !== expected)
                        $fatal(1, "Wrong result expected=%0d actual=%0d", expected, $signed(stored_result));
                    $display("MEASURE,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                        completed, total_cycles - start_cycle, instructions, muls, dots,
                        holds, bubbles, total_cycles, expected);
                    active = 0;
                    completed = completed + 1;
                    if (completed == 2) done = 1;
                end else $fatal(1, "Unexpected marker");
            end else if (active) begin
                if (dut.cache_stall) holds = holds + 1;
                else begin
                    if (dut.stall) bubbles = bubbles + 1;
                    if (dut.id_ex_reg_write || dut.id_ex_mem_write || dut.id_ex_branch) begin
                        instructions = instructions + 1;
                        if (dut.id_ex_reg_write && dut.id_ex_alu_op == `ALU_MUL) muls = muls + 1;
                        if (dut.id_ex_reg_write && dut.id_ex_alu_op == `ALU_DOT8) dots = dots + 1;
                    end
                end
            end
        end
    end
endmodule

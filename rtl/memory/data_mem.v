// Simulation memory. BYPASS provides combinational reads and clocked masked writes.
// Otherwise, hold a request through ready; the response cannot start a duplicate.
module data_mem #(
    parameter LATENCY = 5,
    parameter BYPASS = 0,
    parameter INIT_FILE = "",
    parameter WORDS = 256
) (
    input clk, rst,
    input mem_write, mem_read,
    input [31:0] addr, wr_data,
    input [3:0] wr_mask,
    output reg [31:0] rd_data,
    output reg ready
);
    localparam INDEX_BITS = $clog2(WORDS);

    reg [31:0] memory [0:WORDS-1];
    reg [31:0] saved_addr, saved_wr_data;
    reg [3:0] saved_mask;
    reg saved_write, busy;
    integer counter;
    integer i, lane;
    initial begin
        if (WORDS < 2 || (WORDS & (WORDS - 1)) != 0)
            $fatal(1, "data_mem WORDS must be a power of two >= 2");
        for (i = 0; i < WORDS; i = i + 1)
            memory[i] = i;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end
    generate
        if (BYPASS) begin : direct
            always @(*) begin
                rd_data = memory[addr[INDEX_BITS+1:2]];
                ready = 1'b0;
            end
            always @(posedge clk) begin
                if (!rst && mem_write)
                    for (lane = 0; lane < 4; lane = lane + 1)
                        if (wr_mask[lane])
                            memory[addr[INDEX_BITS+1:2]][lane*8 +: 8] <= wr_data[lane*8 +: 8];
            end
        end else begin : delayed
            // Reset aborts transactions but preserves the memory contents.
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    ready <= 0;
                    busy <= 0;
                    counter <= 0;
                    saved_addr <= 0;
                    saved_wr_data <= 0;
                    saved_mask <= 0;
                    saved_write <= 0;
                    rd_data <= 0;
                end else begin
                    ready <= 0;
                    if ((mem_read || mem_write) && !busy && !ready) begin
                        saved_addr <= addr;
                        saved_wr_data <= wr_data;
                        saved_mask <= wr_mask;
                        saved_write <= mem_write;
                        counter <= LATENCY;
                        busy <= 1;
                    end
                    if (busy) begin
                        counter <= counter - 1;
                        if (counter == 1) begin
                            ready <= 1;
                            busy <= 0;
                            if (saved_write) begin
                                for (lane = 0; lane < 4; lane = lane + 1)
                                    if (saved_mask[lane])
                                        memory[saved_addr[INDEX_BITS+1:2]][lane*8 +: 8] <= saved_wr_data[lane*8 +: 8];
                            end else
                                rd_data <= memory[saved_addr[INDEX_BITS+1:2]];
                        end
                    end
                end
            end
        end
    endgenerate
endmodule

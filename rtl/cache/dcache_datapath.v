// Direct-mapped, one-word lines with write-back and write-allocate.
module dcache_datapath #(
    parameter LINES = 16
) (
    input clk, rst,
    input cache_write_en, data_src, addr_src, dirty_value,
    input [31:0] cpu_addr_in, cpu_wdata_in, mem_data_in,
    input [3:0] cpu_wmask,
    output hit, miss, dirty,
    output [31:0] cache_data_out, mem_wdata_out, addr_out
);
    localparam INDEX_BITS = $clog2(LINES);
    localparam TAG_BITS = 32 - INDEX_BITS - 2;

    reg [31:0] data [0:LINES-1];
    reg [TAG_BITS-1:0] tags [0:LINES-1];
    reg valid [0:LINES-1];
    reg dirty_reg [0:LINES-1];
    wire [INDEX_BITS-1:0] index = cpu_addr_in[INDEX_BITS+1:2];
    wire [31:0] victim_addr = {tags[index], index, 2'b00};
    integer i, lane;

    assign hit = valid[index] && tags[index] == cpu_addr_in[31:INDEX_BITS+2];
    assign miss = !hit;
    assign dirty = valid[index] && dirty_reg[index];
    assign cache_data_out = hit ? data[index] : mem_data_in;
    assign mem_wdata_out = data[index];
    assign addr_out = addr_src ? victim_addr : cpu_addr_in;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < LINES; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty_reg[i] <= 1'b0;
            end
        end else if (cache_write_en) begin
            valid[index] <= 1'b1;
            tags[index] <= cpu_addr_in[31:INDEX_BITS+2];
            if (data_src)
                data[index] <= mem_data_in;
            else begin
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (cpu_wmask[lane])
                        data[index][lane*8 +: 8] <= cpu_wdata_in[lane*8 +: 8];
            end
            dirty_reg[index] <= dirty_value;
        end
    end
endmodule

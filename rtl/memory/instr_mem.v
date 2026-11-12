// Simulation memory: pulse req, then wait for the one-cycle ready response.
module instr_mem #(
    parameter LATENCY = 5,
    parameter BYPASS = 0,
    parameter INIT_FILE = ""
) (
    input clk,
    input rst,
    input [31:0] addr,
    input req,
    output [31:0] instr,
    output reg ready
);
    localparam WORDS = 256;
    localparam INDEX_BITS = $clog2(WORDS);
    localparam [31:0] NOP = 32'h00000013;

    reg [31:0] memory [0:WORDS-1];
    reg [31:0] saved_addr;
    integer counter;
    reg busy;
    integer i;

    wire [INDEX_BITS-1:0] request_index = addr[INDEX_BITS+1:2];
    wire [INDEX_BITS-1:0] saved_index = saved_addr[INDEX_BITS+1:2];

    assign instr = BYPASS ? memory[request_index] : memory[saved_index];

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            memory[i] = NOP;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ready <= 1'b0;
            busy <= 1'b0;
            counter <= 0;
            saved_addr <= 32'd0;
        end else begin
            ready <= 1'b0;
            if (req && !busy && !ready) begin
                saved_addr <= addr;
                counter <= LATENCY;
                busy <= 1'b1;
            end
            if (busy) begin
                counter <= counter - 1;
                if (counter == 1) begin
                    ready <= 1'b1;
                    busy <= 1'b0;
                end
            end
        end
    end
endmodule

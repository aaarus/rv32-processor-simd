// Direct-mapped, one-word lines. A miss issues one pulse to instruction memory.
module icache #(
    parameter LINES = 16
) (
    input clk, rst,
    input [31:0] address, data_in,
    input data_ready,
    output [31:0] instruction_out,
    output reg req_data,
    output cache_stall,
    output reg [31:0] miss_addr
);
    localparam INDEX_BITS = $clog2(LINES);
    localparam TAG_BITS = 32 - INDEX_BITS - 2;
    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] REQUEST = 2'd1;
    localparam [1:0] WAIT_MEMORY = 2'd2;
    localparam [1:0] FILL = 2'd3;

    reg [31:0] data [0:LINES-1];
    reg [TAG_BITS-1:0] tags [0:LINES-1];
    reg valid [0:LINES-1];
    reg [1:0] state, next_state;
    wire [INDEX_BITS-1:0] index = address[INDEX_BITS+1:2];
    wire [INDEX_BITS-1:0] fill_index = miss_addr[INDEX_BITS+1:2];
    wire hit = valid[index] && tags[index] == address[31:INDEX_BITS+2];
    integer i;

    assign instruction_out = hit ? data[index] : 32'h00000013;
    // A response belongs to miss_addr. Release fetch after a matching fill.
    assign cache_stall = !hit;

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (!hit) next_state = REQUEST;
            REQUEST: next_state = WAIT_MEMORY;
            WAIT_MEMORY: if (data_ready) next_state = FILL;
            FILL: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            req_data <= 1'b0;
            miss_addr <= 32'd0;
            for (i = 0; i < LINES; i = i + 1)
                valid[i] <= 1'b0;
        end else begin
            state <= next_state;
            req_data <= 1'b0;
            if (state == REQUEST) begin
                miss_addr <= address;
                req_data <= 1'b1;
            end
            if (state == FILL) begin
                valid[fill_index] <= 1'b1;
                tags[fill_index] <= miss_addr[31:INDEX_BITS+2];
                data[fill_index] <= data_in;
            end
        end
    end
endmodule

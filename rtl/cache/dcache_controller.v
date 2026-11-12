module dcache_controller (
    input clk, rst,
    input hit, miss, dirty,
    input cpu_read, cpu_write,
    input mem_ready,
    output reg cache_stall, cache_write_en,
    output reg mem_read, mem_write,
    output reg data_src, addr_src, dirty_value
);
    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] WRITEBACK = 3'd1;
    localparam [2:0] FETCH = 3'd2;
    localparam [2:0] REFILL = 3'd3;
    localparam [2:0] STORE = 3'd4;

    reg [2:0] state, next_state;

    always @(*) begin
        cache_stall = 1'b0;
        cache_write_en = 1'b0;
        mem_read = 1'b0;
        mem_write = 1'b0;
        data_src = 1'b0;
        addr_src = 1'b0;
        dirty_value = 1'b0;
        next_state = state;
        case (state)
            IDLE: begin
                if (hit && cpu_write) begin
                    cache_write_en = 1'b1;
                    dirty_value = 1'b1;
                end
                if (miss && (cpu_read || cpu_write)) begin
                    cache_stall = 1'b1;
                    next_state = dirty ? WRITEBACK : FETCH;
                end
            end
            WRITEBACK: begin
                cache_stall = 1'b1;
                addr_src = 1'b1; // Victim address
                mem_write = 1'b1;
                if (mem_ready)
                    next_state = FETCH;
            end
            FETCH: begin
                cache_stall = 1'b1;
                mem_read = 1'b1;
                if (mem_ready)
                    next_state = REFILL;
            end
            REFILL: begin
                cache_stall = 1'b1;
                cache_write_en = 1'b1;
                data_src = 1'b1; // Memory response
                next_state = cpu_write ? STORE : IDLE;
            end
            STORE: begin
                cache_stall = 1'b1;
                cache_write_en = 1'b1;
                dirty_value = 1'b1;
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end
endmodule

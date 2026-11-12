module pc (
    input clk,
    input rst,
    input cache_stall,

    input branch_taken,
    input [31:0] branch_target,

    output reg [31:0] pc_out
);

    always @(posedge clk or posedge rst) begin
        if (rst)
            pc_out <= 32'd0;
        else if (branch_taken)
            pc_out <= branch_target;
        else if (!cache_stall)
            pc_out <= pc_out + 32'd4;
    end
endmodule

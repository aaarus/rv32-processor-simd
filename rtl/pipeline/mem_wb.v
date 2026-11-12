module mem_wb (
    input clk,
    input rst,
    input stall,

    // Control signals
    input reg_write,
    input mem_to_reg,

    // Datapath signals
    input [31:0] alu_result,
    input [31:0] mem_data,

    // Destination register
    input [4:0] rd,

    // Registered control outputs
    output reg reg_write_out,
    output reg mem_to_reg_out,

    // Registered datapath outputs
    output reg [31:0] alu_result_out,
    output reg [31:0] mem_data_out,

    // Registered destination register
    output reg [4:0] rd_out
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_write_out <= 1'b0;
            mem_to_reg_out <= 1'b0;

            alu_result_out <= 32'b0;
            mem_data_out <= 32'b0;

            rd_out <= 5'b0;
        end else if (!stall) begin
            reg_write_out <= reg_write;
            mem_to_reg_out <= mem_to_reg;

            alu_result_out <= alu_result;
            mem_data_out <= mem_data;

            rd_out <= rd;
        end
    end
endmodule

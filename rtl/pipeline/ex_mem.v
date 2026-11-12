module ex_mem (
    input clk,
    input rst,
    input stall,
    input flush,

    // Control signals
    input reg_write,
    input mem_write,
    input mem_read,
    input mem_to_reg,

    // Datapath signals
    input [31:0] alu_result,
    input [31:0] rs2_data,

    // Destination register
    input [4:0] rd,
    input [2:0] funct3,

    // Registered control outputs
    output reg reg_write_out,
    output reg mem_write_out,
    output reg mem_read_out,
    output reg mem_to_reg_out,

    // Registered datapath outputs
    output reg [31:0] alu_result_out,
    output reg [31:0] rs2_data_out,

    // Registered destination register
    output reg [2:0] funct3_out,
    output reg [4:0] rd_out
);

    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            reg_write_out <= 1'b0;
            mem_write_out <= 1'b0;
            mem_read_out <= 1'b0;
            mem_to_reg_out <= 1'b0;

            alu_result_out <= 32'b0;
            rs2_data_out <= 32'b0;

            rd_out <= 5'b0;
            funct3_out <= 3'd0;
        end else if (!stall) begin
            reg_write_out <= reg_write;
            mem_write_out <= mem_write;
            mem_read_out <= mem_read;
            mem_to_reg_out <= mem_to_reg;

            alu_result_out <= alu_result;
            rs2_data_out <= rs2_data;

            rd_out <= rd;
            funct3_out <= funct3;
        end
    end
endmodule

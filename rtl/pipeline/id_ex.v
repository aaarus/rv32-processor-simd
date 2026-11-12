`include "rtl/core/rv32_defs.vh"
module id_ex (
    input clk,
    input rst,
    input stall,
    input flush,

    // Control signals
    input reg_write,
    input [`ALU_WIDTH-1:0] alu_op,
    input mem_write,
    input mem_read,
    input mem_to_reg,
    input alu_src,
    input branch,
    input jump,
    input jump_reg,
    input [1:0] alu_a_sel,
    // Datapath signals
    input [31:0] rd_data_1,
    input [31:0] rd_data_2,
    input [31:0] imm,

    // Register addresses
    input [4:0] rd,
    input [4:0] rs1,
    input [4:0] rs2,

    // Instruction metadata
    input [2:0] funct3,
    input [6:0] funct7,
    input [31:0] pc,
    input predicted_taken,
    input [31:0] predicted_target,

    // Registered control outputs
    output reg reg_write_out,
    output reg [`ALU_WIDTH-1:0] alu_op_out,
    output reg mem_write_out,
    output reg mem_read_out,
    output reg mem_to_reg_out,
    output reg alu_src_out,
    output reg branch_out,
    output reg jump_out,
    output reg jump_reg_out,
    output reg [1:0] alu_a_sel_out,

    // Registered datapath outputs
    output reg [31:0] rd_data_1_out,
    output reg [31:0] rd_data_2_out,
    output reg [31:0] imm_out,

    // Registered register addresses
    output reg [4:0] rd_out,
    output reg [4:0] rs1_out,
    output reg [4:0] rs2_out,

    output reg [31:0] pc_out,
    output reg predicted_taken_out,
    output reg [31:0] predicted_target_out,

    output reg [2:0] funct3_out,
    output reg [6:0] funct7_out
);

    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            reg_write_out <= 1'b0;
            alu_op_out <= `ALU_ADD;
            mem_write_out <= 1'b0;
            mem_read_out <= 1'b0;
            mem_to_reg_out <= 1'b0;
            alu_src_out <= 1'b0;

            rd_data_1_out <= 32'b0;
            rd_data_2_out <= 32'b0;
            imm_out <= 32'b0;

            rd_out <= 5'b0;
            rs1_out <= 5'b0;
            rs2_out <= 5'b0;

            pc_out <= 32'b0;
            predicted_taken_out <= 1'b0;
            predicted_target_out <= 32'b0;

            branch_out <= 1'b0;

            funct3_out <= 3'b0;
            funct7_out <= 7'b0;
            jump_out <= 1'b0;
            jump_reg_out <= 1'b0;
            alu_a_sel_out <= `SRC_RS1;
        end else if (!stall) begin
            reg_write_out <= reg_write;
            alu_op_out <= alu_op;
            mem_write_out <= mem_write;
            mem_read_out <= mem_read;
            mem_to_reg_out <= mem_to_reg;
            alu_src_out <= alu_src;

            rd_data_1_out <= rd_data_1;
            rd_data_2_out <= rd_data_2;
            imm_out <= imm;

            rd_out <= rd;
            rs1_out <= rs1;
            rs2_out <= rs2;

            pc_out <= pc;
            predicted_taken_out <= predicted_taken;
            predicted_target_out <= predicted_target;

            branch_out <= branch;

            funct3_out <= funct3;
            funct7_out <= funct7;
            jump_out <= jump;
            jump_reg_out <= jump_reg;
            alu_a_sel_out <= alu_a_sel;
        end
    end
endmodule

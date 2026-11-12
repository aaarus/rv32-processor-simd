`include "rtl/core/rv32_defs.vh"
// Unsupported encodings have no architectural effects; traps are not implemented.
module control_unit (
    input rst,
    input [6:0] opcode,
    input [2:0] funct3,
    input [6:0] funct7,
    output reg [`ALU_WIDTH-1:0] alu_op,
    output reg [1:0] alu_a_sel,
    output reg reg_write, mem_write, mem_read, mem_to_reg, alu_src,
    output reg branch, jump, jump_reg,
    output reg uses_rs1, uses_rs2
);
    localparam [6:0] FUNCT7_BASE = 7'h00;
    localparam [6:0] FUNCT7_MUL  = 7'h01;
    localparam [6:0] FUNCT7_ALT  = 7'h20;

    localparam [2:0] FUNCT3_ADD_SUB_MUL = 3'b000;
    localparam [2:0] FUNCT3_SLL         = 3'b001;
    localparam [2:0] FUNCT3_SLT         = 3'b010;
    localparam [2:0] FUNCT3_SLTU        = 3'b011;
    localparam [2:0] FUNCT3_XOR         = 3'b100;
    localparam [2:0] FUNCT3_SRL_SRA     = 3'b101;
    localparam [2:0] FUNCT3_OR          = 3'b110;
    localparam [2:0] FUNCT3_AND         = 3'b111;
    localparam [2:0] FUNCT3_DOT8        = 3'b000;
    localparam [2:0] FUNCT3_JALR        = 3'b000;

    wire immediate_op = opcode == `OPCODE_OP_IMM;
    wire base_encoding = funct7 == FUNCT7_BASE;
    wire alt_encoding = funct7 == FUNCT7_ALT;
    wire base_or_immediate = base_encoding || immediate_op;
    reg valid_alu;

    always @(*) begin
        alu_op = `ALU_ADD;
        alu_a_sel = `SRC_RS1;
        reg_write = 1'b0;
        mem_write = 1'b0;
        mem_read = 1'b0;
        mem_to_reg = 1'b0;
        alu_src = 1'b0;
        branch = 1'b0;
        jump = 1'b0;
        jump_reg = 1'b0;
        uses_rs1 = 1'b0;
        uses_rs2 = 1'b0;
        valid_alu = 1'b0;
        if (!rst) begin
            case (opcode)
                `OPCODE_OP, `OPCODE_OP_IMM: begin
                    case (funct3)
                        FUNCT3_ADD_SUB_MUL: begin
                            if (base_or_immediate) begin
                                valid_alu = 1'b1;
                            end else if (alt_encoding) begin
                                valid_alu = 1'b1;
                                alu_op = `ALU_SUB;
                            end else if (funct7 == FUNCT7_MUL) begin
                                valid_alu = 1'b1;
                                alu_op = `ALU_MUL;
                            end
                        end
                        FUNCT3_SLL: begin
                            valid_alu = base_encoding;
                            alu_op = `ALU_SLL;
                        end
                        FUNCT3_SLT: begin
                            valid_alu = base_or_immediate;
                            alu_op = `ALU_SLT;
                        end
                        FUNCT3_SLTU: begin
                            valid_alu = base_or_immediate;
                            alu_op = `ALU_SLTU;
                        end
                        FUNCT3_XOR: begin
                            valid_alu = base_or_immediate;
                            alu_op = `ALU_XOR;
                        end
                        FUNCT3_SRL_SRA: begin
                            valid_alu = base_encoding || alt_encoding;
                            alu_op = alt_encoding ? `ALU_SRA : `ALU_SRL;
                        end
                        FUNCT3_OR: begin
                            valid_alu = base_or_immediate;
                            alu_op = `ALU_OR;
                        end
                        FUNCT3_AND: begin
                            valid_alu = base_or_immediate;
                            alu_op = `ALU_AND;
                        end
                        default: begin end
                    endcase

                    reg_write = valid_alu;
                    uses_rs1 = valid_alu;
                    uses_rs2 = valid_alu && !immediate_op;
                    alu_src = immediate_op;
                end
                `OPCODE_CUSTOM0: begin // DOT8 rd, rs1, rs2
                    if (base_encoding && funct3 == FUNCT3_DOT8) begin
                        reg_write = 1'b1;
                        uses_rs1 = 1'b1;
                        uses_rs2 = 1'b1;
                        alu_op = `ALU_DOT8;
                    end
                end
                `OPCODE_LOAD: begin
                    case (funct3)
                        `ACCESS_BYTE, `ACCESS_HALF, `ACCESS_WORD,
                        `ACCESS_BYTE_U, `ACCESS_HALF_U: begin
                            reg_write = 1'b1;
                            mem_read = 1'b1;
                            mem_to_reg = 1'b1;
                            alu_src = 1'b1;
                            uses_rs1 = 1'b1;
                        end
                        default: begin end
                    endcase
                end
                `OPCODE_STORE: begin
                    case (funct3)
                        `ACCESS_BYTE, `ACCESS_HALF, `ACCESS_WORD: begin
                            mem_write = 1'b1;
                            alu_src = 1'b1;
                            uses_rs1 = 1'b1;
                            uses_rs2 = 1'b1;
                        end
                        default: begin end
                    endcase
                end
                `OPCODE_LUI: begin
                    reg_write = 1'b1;
                    alu_src = 1'b1;
                    alu_a_sel = `SRC_ZERO;
                end
                `OPCODE_AUIPC: begin
                    reg_write = 1'b1;
                    alu_src = 1'b1;
                    alu_a_sel = `SRC_PC;
                end
                `OPCODE_BRANCH: begin
                    case (funct3)
                        `BRANCH_BEQ, `BRANCH_BNE, `BRANCH_BLT,
                        `BRANCH_BGE, `BRANCH_BLTU, `BRANCH_BGEU: begin
                            branch = 1'b1;
                            alu_op = `ALU_SUB;
                            uses_rs1 = 1'b1;
                            uses_rs2 = 1'b1;
                        end
                        default: begin end
                    endcase
                end
                `OPCODE_JAL: begin
                    reg_write = 1'b1;
                    jump = 1'b1;
                end
                `OPCODE_JALR: begin
                    if (funct3 == FUNCT3_JALR) begin
                        reg_write = 1'b1;
                        jump = 1'b1;
                        jump_reg = 1'b1;
                        uses_rs1 = 1'b1;
                    end
                end
                default: begin end
            endcase
        end
    end
endmodule

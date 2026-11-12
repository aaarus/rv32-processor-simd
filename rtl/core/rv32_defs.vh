`ifndef RV32_DEFS_VH
`define RV32_DEFS_VH
// Shared execution selectors; upper encodings are available for custom SIMD.
`define ALU_WIDTH 5
`define ALU_ADD  5'd0
`define ALU_SUB  5'd1
`define ALU_AND  5'd2
`define ALU_OR   5'd3
`define ALU_XOR  5'd4
`define ALU_SLL  5'd5
`define ALU_SRL  5'd6
`define ALU_SRA  5'd7
`define ALU_SLT  5'd8
`define ALU_SLTU 5'd9
`define ALU_MUL  5'd10
`define ALU_DOT8 5'd11
// Custom-0 R-type: funct7=0, funct3=0, opcode=0x0b.
`define OPCODE_CUSTOM0 7'h0b
`define SRC_RS1  2'd0
`define SRC_PC   2'd1
`define SRC_ZERO 2'd2

`define OPCODE_LOAD    7'h03
`define OPCODE_OP_IMM  7'h13
`define OPCODE_AUIPC   7'h17
`define OPCODE_STORE   7'h23
`define OPCODE_OP      7'h33
`define OPCODE_LUI     7'h37
`define OPCODE_BRANCH  7'h63
`define OPCODE_JALR    7'h67
`define OPCODE_JAL     7'h6f

`define BRANCH_BEQ   3'b000
`define BRANCH_BNE   3'b001
`define BRANCH_BLT   3'b100
`define BRANCH_BGE   3'b101
`define BRANCH_BLTU  3'b110
`define BRANCH_BGEU  3'b111

`define ACCESS_BYTE   3'b000
`define ACCESS_HALF   3'b001
`define ACCESS_WORD   3'b010
`define ACCESS_BYTE_U 3'b100
`define ACCESS_HALF_U 3'b101

`define FORWARD_REG 2'b00
`define FORWARD_WB  2'b01
`define FORWARD_MEM 2'b10
`endif

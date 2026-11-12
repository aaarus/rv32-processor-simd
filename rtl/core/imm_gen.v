`include "rtl/core/rv32_defs.vh"
module imm_gen (
    input [31:0] instr,
    output reg [31:0] imm
);
    always @(*) begin
        case (instr[6:0])
            `OPCODE_OP_IMM, `OPCODE_LOAD, `OPCODE_JALR:
                imm = {{20{instr[31]}}, instr[31:20]};
            `OPCODE_STORE:
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            `OPCODE_BRANCH:
                imm = {{19{instr[31]}}, instr[31], instr[7],
                       instr[30:25], instr[11:8], 1'b0};
            `OPCODE_JAL:
                imm = {{11{instr[31]}}, instr[31], instr[19:12],
                       instr[20], instr[30:21], 1'b0};
            `OPCODE_LUI, `OPCODE_AUIPC:
                imm = {instr[31:12], 12'd0};
            default: imm = 32'd0;
        endcase
    end
endmodule

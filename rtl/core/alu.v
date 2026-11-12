`include "rtl/core/rv32_defs.vh"
module alu (
    input [31:0] a, b,
    input [`ALU_WIDTH-1:0] control,
    output reg [31:0] result,
    output zero
);
    assign zero = (result == 32'd0);
    always @(*) begin
        case (control)
            `ALU_ADD:  result = a + b;
            `ALU_SUB:  result = a - b;
            `ALU_AND:  result = a & b;
            `ALU_OR:   result = a | b;
            `ALU_XOR:  result = a ^ b;
            `ALU_SLL:  result = a << b[4:0];
            `ALU_SRL:  result = a >> b[4:0];
            `ALU_SRA:  result = $signed(a) >>> b[4:0];
            `ALU_SLT:  result = {31'd0, ($signed(a) < $signed(b))};
            `ALU_SLTU: result = {31'd0, (a < b)};
            default: result = 32'd0;
        endcase
    end
endmodule

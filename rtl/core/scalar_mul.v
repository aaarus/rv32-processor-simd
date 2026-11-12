// RV32 MUL: low 32 bits of the full product (same bits signed or unsigned).
module scalar_mul (
    input [31:0] a, b,
    output [31:0] result
);
    wire [63:0] product = a * b;
    assign result = product[31:0];
endmodule

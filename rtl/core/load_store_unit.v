`include "rtl/core/rv32_defs.vh"
// Little-endian subword selection. Halfword/word accesses must be aligned.
module load_store_unit (
    input [2:0] funct3,
    input [1:0] byte_offset,
    input [31:0] store_value, memory_word,
    output [31:0] store_word,
    output reg [3:0] store_mask,
    output reg [31:0] load_value
);
    wire [4:0] bit_shift = {byte_offset, 3'b000};
    wire [31:0] shifted_word = memory_word >> bit_shift;
    assign store_word = store_value << bit_shift;
    always @(*) begin
        case (funct3)
            `ACCESS_BYTE: store_mask = 4'b0001 << byte_offset;
            `ACCESS_HALF: store_mask = 4'b0011 << byte_offset;
            `ACCESS_WORD: store_mask = 4'b1111;
            default: store_mask = 4'b0000;
        endcase
        case (funct3)
            `ACCESS_BYTE: load_value = {{24{shifted_word[7]}}, shifted_word[7:0]};
            `ACCESS_HALF: load_value = {{16{shifted_word[15]}}, shifted_word[15:0]};
            `ACCESS_WORD: load_value = memory_word;
            `ACCESS_BYTE_U: load_value = {24'd0, shifted_word[7:0]};
            `ACCESS_HALF_U: load_value = {16'd0, shifted_word[15:0]};
            default: load_value = 32'd0;
        endcase
    end
endmodule

`include "rtl/core/rv32_defs.vh"
module forwarding_unit (
    input [4:0] rs1_ex,
    input [4:0] rs2_ex,
    input [4:0] rd_mem,
    input [4:0] rd_wb,
    input       reg_write_mem,
    input       reg_write_wb,
    output reg [1:0] forward_a,
    output reg [1:0] forward_b
);

    always @(*) begin
        if (reg_write_mem && (rd_mem != 0) && (rd_mem == rs1_ex))
            forward_a = `FORWARD_MEM;
        else if (reg_write_wb && (rd_wb != 0) && (rd_wb == rs1_ex))
            forward_a = `FORWARD_WB;
        else
            forward_a = `FORWARD_REG;

        if (reg_write_mem && (rd_mem != 0) && (rd_mem == rs2_ex))
            forward_b = `FORWARD_MEM;
        else if (reg_write_wb && (rd_wb != 0) && (rd_wb == rs2_ex))
            forward_b = `FORWARD_WB;
        else
            forward_b = `FORWARD_REG;
    end
endmodule

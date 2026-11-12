module reg_bank (
    input clk,
    input rst,
    input [4:0] rd_reg1, rd_reg2,
    input reg_write,
    input [4:0] wr_reg,
    input [31:0] wr_data,
    output [31:0] rd_data1, rd_data2
);
    reg [31:0] regs [0:31];
    integer i;

    // Bypass a simultaneous WB write into decode before the clock edge.
    assign rd_data1 = (rd_reg1 == 0) ? 32'd0 :
        ((reg_write && wr_reg == rd_reg1) ? wr_data : regs[rd_reg1]);
    assign rd_data2 = (rd_reg2 == 0) ? 32'd0 :
        ((reg_write && wr_reg == rd_reg2) ? wr_data : regs[rd_reg2]);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (reg_write && wr_reg != 0) begin
            regs[wr_reg] <= wr_data;
        end
    end
endmodule

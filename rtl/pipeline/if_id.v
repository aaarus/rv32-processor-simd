module if_id (
    input clk,
    input rst,
    input stall,
    input flush,

    input [31:0] pc_in,
    input [31:0] instr_in,
    input predicted_taken_in,
    input [31:0] predicted_target_in,

    output reg [31:0] pc_out,
    output reg [31:0] instr_out,
    output reg predicted_taken_out,
    output reg [31:0] predicted_target_out
);

    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            pc_out <= 32'b0;
            instr_out <= 32'b0;
            predicted_taken_out <= 1'b0;
            predicted_target_out <= 32'b0;
        end else if (!stall) begin
            pc_out <= pc_in;
            instr_out <= instr_in;
            predicted_taken_out <= predicted_taken_in;
            predicted_target_out <= predicted_target_in;
        end
    end
endmodule

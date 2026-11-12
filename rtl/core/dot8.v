// Four signed 8-bit lanes. Exact sum, sign-extended to XLEN.
// Combinational EX operation; no accumulator or hidden state.
module dot8 (
    input [31:0] a, b,
    output [31:0] result
);
    wire signed [15:0] product [0:3];
    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : lanes
            wire signed [7:0] a_lane = a[lane*8 +: 8];
            wire signed [7:0] b_lane = b[lane*8 +: 8];
            assign product[lane] = a_lane * b_lane;
        end
    endgenerate

    wire signed [16:0] sum01 = {product[0][15], product[0]} +
                               {product[1][15], product[1]};
    wire signed [16:0] sum23 = {product[2][15], product[2]} +
                               {product[3][15], product[3]};
    wire signed [17:0] total = {sum01[16], sum01} + {sum23[16], sum23};
    assign result = {{14{total[17]}}, total};
endmodule

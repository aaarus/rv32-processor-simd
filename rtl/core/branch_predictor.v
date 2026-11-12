module branch_predictor (
    input clk,
    input rst,

    // Fetch stage
    input [31:0] fetch_pc,
    output predict_taken,
    output [31:0] predict_target,

    // Update from EX stage
    input update,
    input [31:0] branch_pc,
    input actual_taken,
    input [31:0] actual_target
);

    localparam ENTRIES = 64;
    localparam INDEX_BITS = $clog2(ENTRIES);
    localparam TAG_BITS = 32 - INDEX_BITS - 2;

    localparam [1:0] STRONGLY_NOT_TAKEN = 2'b00;
    localparam [1:0] WEAKLY_NOT_TAKEN   = 2'b01;
    localparam [1:0] STRONGLY_TAKEN     = 2'b11;

    wire [INDEX_BITS-1:0] index;
    wire [INDEX_BITS-1:0] update_index;

    assign index        = fetch_pc[INDEX_BITS+1:2];
    assign update_index = branch_pc[INDEX_BITS+1:2];

    reg [1:0] prediction_state [0:ENTRIES-1];

    reg              valid  [0:ENTRIES-1];
    reg [TAG_BITS-1:0] tag    [0:ENTRIES-1];
    reg [31:0]       target [0:ENTRIES-1];

    wire btb_hit;

    assign btb_hit =
        valid[index] &&
        (tag[index] == fetch_pc[31:INDEX_BITS+2]);

    assign predict_taken =
        btb_hit && prediction_state[index][1];

    assign predict_target =
        btb_hit ? target[index] : 32'b0;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                prediction_state[i] <= WEAKLY_NOT_TAKEN;
                valid[i] <= 1'b0;
                tag[i] <= {TAG_BITS{1'b0}};
                target[i] <= 32'b0;
            end
        end else if (update) begin
            // Update BTB only if branch was taken
            if (actual_taken) begin
                valid[update_index]  <= 1'b1;
                tag[update_index]    <= branch_pc[31:INDEX_BITS+2];
                target[update_index] <= actual_target;
            end

            if (actual_taken) begin
                if (prediction_state[update_index] != STRONGLY_TAKEN)
                    prediction_state[update_index]
                        <= prediction_state[update_index] + 1'b1;
            end else begin
                if (prediction_state[update_index] != STRONGLY_NOT_TAKEN)
                    prediction_state[update_index]
                        <= prediction_state[update_index] - 1'b1;
            end
        end
    end
endmodule

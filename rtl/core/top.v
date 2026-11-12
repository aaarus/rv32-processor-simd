`include "rtl/core/rv32_defs.vh"
module top #(
    parameter IMEM_INIT_FILE = "",
    parameter MEMORY_LATENCY = 5,
    parameter BYPASS_MODE = 0,
    parameter BYPASS_CACHES = BYPASS_MODE,
    parameter BYPASS_PREDICTOR = BYPASS_MODE,
    parameter DMEM_INIT_FILE = "",
    parameter DMEM_WORDS = 256
) (
    input clk,
    input rst
);

    wire [2:0] ex_mem_funct3;
    wire [31:0] dmem_read_data;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_write_data;
    wire dmem_read_req;
    wire dmem_write_req;
    // Global
    wire stall;
    wire uses_rs1_id;
    wire uses_rs2_id;

    // IF Stage
    wire [31:0] pc_out;
    wire [31:0] imem_out;

    wire icache_stall;
    wire dcache_stall;
    wire cache_stall;
    wire pc_redirect;
    wire pc_update;
    reg branch_taken;
    wire [31:0] branch_target;
    wire [31:0] pc_update_target;
    wire actual_taken;
    wire [31:0] actual_target;
    wire prediction_check;
    wire branch_mispredict;
    wire predictor_update;

    wire bp_predict_taken;
    wire [31:0] bp_predict_target;
    wire if_predicted_taken;
    wire [31:0] if_predicted_target;

    assign cache_stall = !BYPASS_CACHES && (icache_stall | dcache_stall);
    assign if_predicted_taken = !BYPASS_PREDICTOR && bp_predict_taken;
    assign if_predicted_target =
        if_predicted_taken ? bp_predict_target : (pc_out + 32'd4);
    assign pc_update = pc_redirect || (if_predicted_taken && !cache_stall && !stall);
    assign pc_update_target =
        pc_redirect ? actual_target : if_predicted_target;

    pc pc_inst (
        .clk(clk),
        .rst(rst),
        .cache_stall(cache_stall || stall),
        .pc_out(pc_out),
        .branch_taken(pc_update),
        .branch_target(pc_update_target)
    );

    wire req_data, ready;
    wire [31:0] miss_addr;
    wire [31:0] icache_out;
    icache icache_inst (
        .clk(clk),
        .rst(rst || BYPASS_CACHES),
        .address(pc_out),
        .data_in(imem_out),
        .instruction_out(icache_out),
        .req_data(req_data),
        .data_ready(ready),
        .cache_stall(icache_stall),
        .miss_addr(miss_addr)
    );

    instr_mem #(.LATENCY(MEMORY_LATENCY), .INIT_FILE(IMEM_INIT_FILE),
                .BYPASS(BYPASS_CACHES)) instr_mem_inst (
        .clk(clk),
        .rst(rst),
        .addr(BYPASS_CACHES ? pc_out : miss_addr),
        .instr(imem_out),
        .req(!BYPASS_CACHES && req_data),
        .ready(ready)
    );

    // IF/ID
    wire [31:0] if_id_pc;
    wire [31:0] if_id_instr;
    wire if_id_predicted_taken;
    wire [31:0] if_id_predicted_target;

    if_id if_id_inst (
        .clk(clk),
        .rst(rst),
        .stall(cache_stall || stall),
        .flush(pc_redirect),

        .pc_in(pc_out),
        .instr_in(BYPASS_CACHES ? imem_out : icache_out),
        .predicted_taken_in(if_predicted_taken),
        .predicted_target_in(if_predicted_target),

        .pc_out(if_id_pc),
        .instr_out(if_id_instr),
        .predicted_taken_out(if_id_predicted_taken),
        .predicted_target_out(if_id_predicted_target)
    );

    // Decode
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;

    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;

    assign opcode = if_id_instr[6:0];
    assign funct3 = if_id_instr[14:12];
    assign funct7 = if_id_instr[31:25];

    assign rs1 = if_id_instr[19:15];
    assign rs2 = if_id_instr[24:20];
    assign rd  = if_id_instr[11:7];

    // Control Unit
    wire reg_write;
    wire mem_write;
    wire mem_read;
    wire mem_to_reg;
    wire alu_src;
    wire [`ALU_WIDTH-1:0] alu_op;
    wire [1:0] alu_a_sel;
    wire jump_reg;
    wire branch;
    wire jump;

    control_unit cu (
        .rst(rst),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),

        .alu_op(alu_op),
        .reg_write(reg_write),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .mem_to_reg(mem_to_reg),
        .alu_src(alu_src),
        .branch(branch),
        .jump(jump),
        .jump_reg(jump_reg),
        .alu_a_sel(alu_a_sel),
        .uses_rs1(uses_rs1_id),
        .uses_rs2(uses_rs2_id)
    );

    // Register File
    wire [31:0] rd_data1;
    wire [31:0] rd_data2;

    wire wb_reg_write;
    wire [4:0] wb_rd;
    wire [31:0] wb_data;

    reg_bank rb (
        .clk(clk),
        .rst(rst),

        .rd_reg1(rs1),
        .rd_reg2(rs2),

        .reg_write(wb_reg_write),
        .wr_reg(wb_rd),
        .wr_data(wb_data),

        .rd_data1(rd_data1),
        .rd_data2(rd_data2)
    );

    // Immediate Generator
    wire [31:0] imm_data;

    imm_gen imm_gen_inst (
        .instr(if_id_instr),
        .imm(imm_data)
    );

    // Hazard Unit
    wire id_ex_mem_read;
    wire [4:0] id_ex_rd;

    hazard_unit hu (
        .rs1_id(rs1),
        .rs2_id(rs2),
        .uses_rs1_id(uses_rs1_id),
        .uses_rs2_id(uses_rs2_id),

        .rd_ex(id_ex_rd),
        .mem_read_ex(id_ex_mem_read),

        .stall(stall)
    );

    // ID/EX
    wire id_ex_reg_write;
    wire [`ALU_WIDTH-1:0] id_ex_alu_op;
    wire [1:0] id_ex_alu_a_sel;
    wire id_ex_jump_reg;
    wire id_ex_mem_write;
    wire id_ex_mem_to_reg;
    wire id_ex_alu_src;

    wire [31:0] id_ex_rd_data_1;
    wire [31:0] id_ex_rd_data_2;
    wire [31:0] id_ex_imm;

    wire [4:0] id_ex_rs1;
    wire [4:0] id_ex_rs2;

    wire id_ex_branch;
    wire [31:0] id_ex_pc;

    wire [2:0] id_ex_funct3;
    wire [6:0] id_ex_funct7;
    wire id_ex_jump;
    wire id_ex_predicted_taken;
    wire [31:0] id_ex_predicted_target;

    id_ex id_ex_inst (
        .clk(clk),
        .rst(rst),
        .stall(cache_stall),
        .flush(pc_redirect || (stall && !cache_stall)),

        .reg_write(reg_write),
        .alu_op(alu_op),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .mem_to_reg(mem_to_reg),
        .alu_src(alu_src),

        .rd_data_1(rd_data1),
        .rd_data_2(rd_data2),
        .imm(imm_data),

        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .pc(if_id_pc),
        .funct3(funct3),
        .funct7(funct7),
        .jump(jump),
        .jump_reg(jump_reg),
        .alu_a_sel(alu_a_sel),
        .predicted_taken(if_id_predicted_taken),
        .predicted_target(if_id_predicted_target),

        .reg_write_out(id_ex_reg_write),
        .alu_op_out(id_ex_alu_op),
        .mem_write_out(id_ex_mem_write),
        .mem_read_out(id_ex_mem_read),
        .mem_to_reg_out(id_ex_mem_to_reg),
        .alu_src_out(id_ex_alu_src),

        .rd_data_1_out(id_ex_rd_data_1),
        .rd_data_2_out(id_ex_rd_data_2),
        .imm_out(id_ex_imm),

        .rd_out(id_ex_rd),
        .rs1_out(id_ex_rs1),
        .rs2_out(id_ex_rs2),
        .branch(branch),
        .branch_out(id_ex_branch),
        .pc_out(id_ex_pc),
        .predicted_taken_out(id_ex_predicted_taken),
        .predicted_target_out(id_ex_predicted_target),

        .funct3_out(id_ex_funct3),
        .funct7_out(id_ex_funct7),
        .jump_reg_out(id_ex_jump_reg),
        .alu_a_sel_out(id_ex_alu_a_sel),
        .jump_out(id_ex_jump)
    );

    branch_predictor bp_inst (
        .clk(clk),
        .rst(rst || BYPASS_PREDICTOR),
        .fetch_pc(pc_out),
        .predict_taken(bp_predict_taken),
        .predict_target(bp_predict_target),
        .update(predictor_update),
        .branch_pc(id_ex_pc),
        .actual_taken(branch_taken),
        .actual_target(branch_target)
    );

    // Forwarding Unit
    wire [1:0] forward_a;
    wire [1:0] forward_b;

    wire ex_mem_reg_write;
    wire ex_mem_mem_write;
    wire ex_mem_mem_read;
    wire ex_mem_mem_to_reg;

    wire [31:0] ex_mem_alu_result;
    wire [31:0] ex_mem_rs2_data;
    wire [4:0] ex_mem_rd;

    wire mem_wb_reg_write;
    wire mem_wb_mem_to_reg;
    wire [31:0] mem_wb_alu_result;
    wire [31:0] mem_wb_mem_data;
    wire [4:0] mem_wb_rd;

    forwarding_unit fu (
        .rs1_ex(id_ex_rs1),
        .rs2_ex(id_ex_rs2),

        .rd_mem(ex_mem_rd),
        .rd_wb(mem_wb_rd),

        .reg_write_mem(ex_mem_reg_write),
        .reg_write_wb(mem_wb_reg_write),

        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    // EX Stage
    wire [31:0] src_a;
    wire [31:0] src_b_reg;
    wire [31:0] src_b;

    wire [31:0] alu_result;

    assign src_a =
        (forward_a == `FORWARD_MEM) ? ex_mem_alu_result :
        (forward_a == `FORWARD_WB) ? wb_data :
                              id_ex_rd_data_1;

    assign src_b_reg =
        (forward_b == `FORWARD_MEM) ? ex_mem_alu_result :
        (forward_b == `FORWARD_WB) ? wb_data :
                              id_ex_rd_data_2;

    assign src_b = id_ex_alu_src ? id_ex_imm : src_b_reg;

    wire [31:0] alu_a = (id_ex_alu_a_sel == `SRC_PC) ? id_ex_pc :
        ((id_ex_alu_a_sel == `SRC_ZERO) ? 32'd0 : src_a);
    wire zero;

    wire [31:0] normal_alu_result;
    alu alu_inst (
        .a(alu_a),
        .b(src_b),
        .control(id_ex_alu_op),
        .result(normal_alu_result),
        .zero(zero)
    );

    wire [31:0] mul_result, dot_result;
    scalar_mul mul_inst (.a(src_a), .b(src_b_reg), .result(mul_result));
    dot8 dot_inst (.a(src_a), .b(src_b_reg), .result(dot_result));

    assign alu_result = id_ex_jump ? (id_ex_pc + 32'd4) :
        (id_ex_alu_op == `ALU_MUL) ? mul_result :
        (id_ex_alu_op == `ALU_DOT8) ? dot_result : normal_alu_result;

    wire less_than_signed;
    assign less_than_signed = ($signed(src_a) < $signed(src_b_reg));
    wire less_than_unsigned;
    assign less_than_unsigned = (src_a < src_b_reg);

    always @(*) begin
        branch_taken = 1'b0;
        if (id_ex_branch) begin
            case (id_ex_funct3)
                `BRANCH_BEQ: branch_taken = zero;
                `BRANCH_BNE: branch_taken = !zero;
                `BRANCH_BLT: branch_taken = less_than_signed;
                `BRANCH_BGE: branch_taken = !less_than_signed;
                `BRANCH_BLTU: branch_taken = less_than_unsigned;
                `BRANCH_BGEU: branch_taken = !less_than_unsigned;
                default: branch_taken = 1'b0;
            endcase
        end
    end

    assign branch_target = id_ex_jump_reg ?
        ((src_a + id_ex_imm) & 32'hfffffffe) : (id_ex_pc + id_ex_imm);
    assign actual_taken = branch_taken || id_ex_jump;
    assign actual_target =
        actual_taken ? branch_target : (id_ex_pc + 32'd4);
    assign prediction_check =
        id_ex_branch || id_ex_jump || id_ex_predicted_taken;
    assign branch_mispredict =
        prediction_check &&
        ((id_ex_predicted_taken != actual_taken) ||
         (id_ex_predicted_target != actual_target));
    // Resolve only when EX can advance; cache holds preserve the instruction.
    assign pc_redirect = branch_mispredict && !cache_stall;
    assign predictor_update = !BYPASS_PREDICTOR && id_ex_branch && !cache_stall;

    // EX/MEM
    ex_mem ex_mem_inst (
        .clk(clk),
        .rst(rst),
        .stall(cache_stall),
        .flush(1'b0),

        .reg_write(id_ex_reg_write),
        .mem_write(id_ex_mem_write),
        .mem_read(id_ex_mem_read),
        .mem_to_reg(id_ex_mem_to_reg),

        .alu_result(alu_result),
        .rs2_data(src_b_reg),

        .rd(id_ex_rd),
        .funct3(id_ex_funct3),
        .funct3_out(ex_mem_funct3),

        .reg_write_out(ex_mem_reg_write),
        .mem_write_out(ex_mem_mem_write),
        .mem_read_out(ex_mem_mem_read),
        .mem_to_reg_out(ex_mem_mem_to_reg),

        .alu_result_out(ex_mem_alu_result),
        .rs2_data_out(ex_mem_rs2_data),

        .rd_out(ex_mem_rd)
    );

    // MEM Stage
    wire [31:0] mem_read_data;
    wire [31:0] cache_read_data;
    wire [31:0] store_word;
    wire [3:0] store_mask;
    wire [31:0] cache_mem_addr, cache_mem_wdata;
    wire cache_mem_read, cache_mem_write;
    wire [3:0] dmem_write_mask;

    load_store_unit lsu (
        .funct3(ex_mem_funct3),
        .byte_offset(ex_mem_alu_result[1:0]),
        .store_value(ex_mem_rs2_data),
        .memory_word(BYPASS_CACHES ? dmem_read_data : cache_read_data),
        .store_word(store_word),
        .store_mask(store_mask),
        .load_value(mem_read_data)
    );

    assign dmem_addr = BYPASS_CACHES ? ex_mem_alu_result : cache_mem_addr;
    assign dmem_write_data = BYPASS_CACHES ? store_word : cache_mem_wdata;
    assign dmem_write_mask = BYPASS_CACHES ? store_mask : 4'b1111;
    assign dmem_read_req = BYPASS_CACHES ? ex_mem_mem_read : cache_mem_read;
    assign dmem_write_req = BYPASS_CACHES ? ex_mem_mem_write : cache_mem_write;
    wire dmem_ready;
    wire dcache_hit;
    wire dcache_miss;
    wire dcache_dirty;
    wire dcache_cache_write_en;
    wire dcache_data_src;
    wire dcache_addr_src;
    wire dcache_dirty_value;

    dcache_controller dcache_controller_inst (
        .clk(clk),
        .rst(rst || BYPASS_CACHES),
        .hit(dcache_hit),
        .miss(dcache_miss),
        .cache_stall(dcache_stall),
        .dirty(dcache_dirty),
        .cpu_read(!BYPASS_CACHES && ex_mem_mem_read),
        .cpu_write(!BYPASS_CACHES && ex_mem_mem_write),
        .cache_write_en(dcache_cache_write_en),
        .mem_ready(dmem_ready),
        .mem_read(cache_mem_read),
        .mem_write(cache_mem_write),
        .data_src(dcache_data_src),
        .addr_src(dcache_addr_src),
        .dirty_value(dcache_dirty_value)
    );

    dcache_datapath dcache_datapath_inst (
        .clk(clk),
        .rst(rst || BYPASS_CACHES),
        .cache_write_en(dcache_cache_write_en),
        .hit(dcache_hit),
        .miss(dcache_miss),
        .dirty(dcache_dirty),
        .cpu_addr_in(ex_mem_alu_result),
        .mem_data_in(dmem_read_data),
        .cpu_wdata_in(store_word),
        .cpu_wmask(store_mask),
        .cache_data_out(cache_read_data),
        .mem_wdata_out(cache_mem_wdata),
        .data_src(dcache_data_src),
        .addr_out(cache_mem_addr),
        .addr_src(dcache_addr_src),
        .dirty_value(dcache_dirty_value)
    );

    data_mem #(.LATENCY(MEMORY_LATENCY), .BYPASS(BYPASS_CACHES),
               .INIT_FILE(DMEM_INIT_FILE), .WORDS(DMEM_WORDS)) data_mem_inst (
        .clk(clk),
        .rst(rst),

        .mem_write(dmem_write_req),
        .mem_read(dmem_read_req),
        .wr_mask(dmem_write_mask),

        .addr(dmem_addr),
        .wr_data(dmem_write_data),

        .rd_data(dmem_read_data),
        .ready(dmem_ready)
    );

    // MEM/WB
    mem_wb mem_wb_inst (
        .clk(clk),
        .rst(rst),
        .stall(cache_stall),

        .reg_write(ex_mem_reg_write),
        .mem_to_reg(ex_mem_mem_to_reg),

        .alu_result(ex_mem_alu_result),
        .mem_data(mem_read_data),

        .rd(ex_mem_rd),

        .reg_write_out(mem_wb_reg_write),
        .mem_to_reg_out(mem_wb_mem_to_reg),

        .alu_result_out(mem_wb_alu_result),
        .mem_data_out(mem_wb_mem_data),

        .rd_out(mem_wb_rd)
    );

    // WB Stage
    assign wb_data = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;

    assign wb_reg_write = mem_wb_reg_write && !cache_stall && !rst;
    assign wb_rd = mem_wb_rd;
endmodule

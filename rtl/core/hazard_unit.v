module hazard_unit (
    input [4:0] rs1_id, rs2_id,
    input uses_rs1_id, uses_rs2_id,
    input [4:0] rd_ex,
    input mem_read_ex,
    output stall
);
    // Hold fetch/decode and insert one EX bubble for an adjacent load consumer.
    assign stall = mem_read_ex && (rd_ex != 0) &&
        ((uses_rs1_id && rd_ex == rs1_id) ||
         (uses_rs2_id && rd_ex == rs2_id));
endmodule

module opt4c_int_fp_mode_wrapper_pipepe_cfg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mode_fp,

    input  logic        int_clr,
    input  logic [7:0]  int_en_multiplicand,
    input  logic [3:0]  int_sign_en_multiplicand,
    input  logic        int_encode_valid,
    input  logic [7:0]  int_operand_b,
    output logic [1:0]  int_position,
    output logic [2:0]  int_cal_cycle,
    output logic [51:0] int_pe_result,

    input  logic        fp_start,
    input  logic [23:0] fp_mantissa_a,
    input  logic [23:0] fp_mantissa_b,
    input  logic [2:0]  fp_min_group,
    output logic        fp_busy,
    output logic        fp_done,
    output logic        fp_result_valid,
    output logic [47:0] fp_mantissa_product,
    output logic [15:0] fp_pair_valid_mask,
    output logic [6:0]  fp_group_valid_mask
);

opt4c_int_fp_mode_wrapper #(
    .FP_CLR_DELAY_CYCLES(4),
    .FP_BW_DELAY_CYCLES(5),
    .FP_DRAIN_LIMIT(9),
    .FP_CAPTURE_AT_DRAIN_END(0),
    .FP_CAPTURE_WITH_TOKEN(1),
    .FP_CAPTURE_TOKEN_DELAY_CYCLES(3)
) wrapper (
    .clk(clk),
    .rst_n(rst_n),
    .mode_fp(mode_fp),
    .int_clr(int_clr),
    .int_en_multiplicand(int_en_multiplicand),
    .int_sign_en_multiplicand(int_sign_en_multiplicand),
    .int_encode_valid(int_encode_valid),
    .int_operand_b(int_operand_b),
    .int_position(int_position),
    .int_cal_cycle(int_cal_cycle),
    .int_pe_result(int_pe_result),
    .fp_start(fp_start),
    .fp_mantissa_a(fp_mantissa_a),
    .fp_mantissa_b(fp_mantissa_b),
    .fp_min_group(fp_min_group),
    .fp_busy(fp_busy),
    .fp_done(fp_done),
    .fp_result_valid(fp_result_valid),
    .fp_mantissa_product(fp_mantissa_product),
    .fp_pair_valid_mask(fp_pair_valid_mask),
    .fp_group_valid_mask(fp_group_valid_mask)
);

endmodule

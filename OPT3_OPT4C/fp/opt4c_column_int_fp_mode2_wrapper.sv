module opt4c_column_int_fp_mode2_wrapper #(
    parameter N = 4
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [1:0]       mode,

    input  logic             int_clr,
    input  logic [7:0]       int_en_multiplicand,
    input  logic [3:0]       int_sign_en_multiplicand,
    input  logic             int_encode_valid,
    input  logic [8*N-1:0]   int_operand_b,
    output logic [1:0]       int_position,
    output logic [2:0]       int_cal_cycle,
    output logic [52*N-1:0]  int_pe_result,

    input  logic             fp_start,
    input  logic [31:0]      fp_operand_a,
    input  logic [31:0]      fp_operand_b,
    output logic             fp_busy,
    output logic             fp_done,
    output logic             fp_result_valid,
    output logic [47:0]      fp_mantissa_product,
    output logic [31:0]      fp_result,
    output logic             fp_invalid,
    output logic             fp_overflow,
    output logic             fp_underflow,
    output logic             fp_inexact
);

logic       mode_fp;
logic [2:0] fp_min_group;

always_comb begin
    mode_fp = (mode != 2'b00);
    case (mode)
        2'b10: fp_min_group = 3'd1;
        2'b11: fp_min_group = 3'd2;
        default: fp_min_group = 3'd0;
    endcase
end

opt4c_column_int_fp_mode_wrapper #(
    .N(N)
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
    .fp_operand_a(fp_operand_a),
    .fp_operand_b(fp_operand_b),
    .fp_min_group(fp_min_group),
    .fp_busy(fp_busy),
    .fp_done(fp_done),
    .fp_result_valid(fp_result_valid),
    .fp_mantissa_product(fp_mantissa_product),
    .fp_result(fp_result),
    .fp_invalid(fp_invalid),
    .fp_overflow(fp_overflow),
    .fp_underflow(fp_underflow),
    .fp_inexact(fp_inexact)
);

endmodule

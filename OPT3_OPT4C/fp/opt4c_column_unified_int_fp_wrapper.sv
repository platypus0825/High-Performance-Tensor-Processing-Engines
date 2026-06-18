module opt4c_column_unified_int_fp_wrapper #(
    parameter N = 4
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [1:0]       mode,
    input  logic             start,
    input  logic [31:0]      operand_a,
    input  logic [31:0]      operand_b,

    output logic             busy,
    output logic             done,
    output logic             result_valid,
    output logic [31:0]      result,

    output logic signed [15:0] int_result,
    output logic [47:0]      fp_mantissa_product,
    output logic [31:0]      fp_result,
    output logic             fp_invalid,
    output logic             fp_overflow,
    output logic             fp_underflow,
    output logic             fp_inexact
);

wire mode_int;
wire mode_fp;

wire inner_fp_busy;
wire inner_fp_done;
wire inner_fp_result_valid;
wire [47:0] inner_fp_mantissa_product;
wire [31:0] inner_fp_result;
wire inner_fp_invalid;
wire inner_fp_overflow;
wire inner_fp_underflow;
wire inner_fp_inexact;

wire [1:0] unused_int_position;
wire [2:0] unused_int_cal_cycle;
wire [52*N-1:0] unused_int_pe_result;
wire [32*N-1:0] unused_int_lane_result;
wire [63:0] unused_int_mac_result;

logic signed [7:0] int_a_s1;
logic signed [7:0] int_b_s1;
logic int_valid_s1;
logic signed [15:0] int_product_s2;
logic int_valid_s2;

assign mode_int = (mode == 2'b00);
assign mode_fp = !mode_int;
assign busy = mode_fp ? inner_fp_busy : 1'b0;
assign done = mode_fp ? inner_fp_done : int_valid_s2;
assign result_valid = mode_fp ? inner_fp_result_valid : int_valid_s2;
assign result = mode_fp ? inner_fp_result : {{16{int_product_s2[15]}}, int_product_s2};
assign int_result = int_product_s2;
assign fp_mantissa_product = inner_fp_mantissa_product;
assign fp_result = inner_fp_result;
assign fp_invalid = mode_fp ? inner_fp_invalid : 1'b0;
assign fp_overflow = mode_fp ? inner_fp_overflow : 1'b0;
assign fp_underflow = mode_fp ? inner_fp_underflow : 1'b0;
assign fp_inexact = mode_fp ? inner_fp_inexact : 1'b0;

opt4c_column_int_fp_mode2_wrapper #(
    .N(N)
) fp_column (
    .clk(clk),
    .rst_n(rst_n),
    .mode(mode),
    .int_clr(1'b0),
    .int_en_multiplicand(8'd0),
    .int_sign_en_multiplicand(4'd0),
    .int_encode_valid(1'b0),
    .int_operand_b({8*N{1'b0}}),
    .int_position(unused_int_position),
    .int_cal_cycle(unused_int_cal_cycle),
    .int_pe_result(unused_int_pe_result),
    .int_lane_result(unused_int_lane_result),
    .int_mac_result(unused_int_mac_result),
    .fp_start(mode_fp && start),
    .fp_operand_a(operand_a),
    .fp_operand_b(operand_b),
    .fp_busy(inner_fp_busy),
    .fp_done(inner_fp_done),
    .fp_result_valid(inner_fp_result_valid),
    .fp_mantissa_product(inner_fp_mantissa_product),
    .fp_result(inner_fp_result),
    .fp_invalid(inner_fp_invalid),
    .fp_overflow(inner_fp_overflow),
    .fp_underflow(inner_fp_underflow),
    .fp_inexact(inner_fp_inexact)
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        int_a_s1 <= 8'sd0;
        int_b_s1 <= 8'sd0;
        int_valid_s1 <= 1'b0;
        int_product_s2 <= 16'sd0;
        int_valid_s2 <= 1'b0;
    end else begin
        int_valid_s1 <= mode_int && start;
        int_a_s1 <= $signed(operand_a[7:0]);
        int_b_s1 <= $signed(operand_b[7:0]);
        int_product_s2 <= int_a_s1 * int_b_s1;
        int_valid_s2 <= int_valid_s1;
    end
end

endmodule

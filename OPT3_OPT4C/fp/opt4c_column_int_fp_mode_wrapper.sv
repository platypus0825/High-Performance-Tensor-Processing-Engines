module opt4c_column_int_fp_mode_wrapper #(
    parameter N = 4,
    parameter FP_CLR_DELAY_CYCLES = 4,
    parameter FP_BW_DELAY_CYCLES = 5,
    parameter FP_DRAIN_LIMIT = 9,
    parameter FP_CAPTURE_TOKEN_DELAY_CYCLES = 5
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             mode_fp,

    input  logic             int_clr,
    input  logic [7:0]       int_en_multiplicand,
    input  logic [3:0]       int_sign_en_multiplicand,
    input  logic             int_encode_valid,
    input  logic [8*N-1:0]   int_operand_b,
    output logic [1:0]       int_position,
    output logic [2:0]       int_cal_cycle,
    output logic [52*N-1:0]  int_pe_result,
    output logic [32*N-1:0]  int_lane_result,
    output logic [63:0]      int_mac_result,

    input  logic             fp_start,
    input  logic [31:0]      fp_operand_a,
    input  logic [31:0]      fp_operand_b,
    input  logic [2:0]       fp_min_group,
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

localparam int FP_LANES = 4;

localparam logic [3:0] S_IDLE       = 4'd0;
localparam logic [3:0] S_LOAD_ROW   = 4'd1;
localparam logic [3:0] S_ENC_START  = 4'd2;
localparam logic [3:0] S_ENC_WAIT   = 4'd3;
localparam logic [3:0] S_BW_SETUP   = 4'd4;
localparam logic [3:0] S_BW_RUN     = 4'd5;
localparam logic [3:0] S_BW_GAP     = 4'd6;
localparam logic [3:0] S_ROW_DRAIN  = 4'd7;
localparam logic [3:0] S_ACC_ROW    = 4'd8;
localparam logic [3:0] S_DONE       = 4'd9;

logic [3:0] state;

logic [31:0] fp_operand_a_reg;
logic [31:0] fp_operand_b_reg;
logic [2:0]  fp_min_group_reg;
wire  [31:0] fp_operand_a_active;
wire  [31:0] fp_operand_b_active;

wire        fp_sign_a;
wire        fp_sign_b;
wire [7:0]  fp_exponent_a;
wire [7:0]  fp_exponent_b;
wire [22:0] fp_fraction_a;
wire [22:0] fp_fraction_b;
wire [23:0] fp_unpacked_mantissa_a;
wire [23:0] fp_unpacked_mantissa_b;
wire        fp_a_is_zero;
wire        fp_b_is_zero;
wire        fp_a_is_subnormal;
wire        fp_b_is_subnormal;
wire        fp_a_is_inf;
wire        fp_b_is_inf;
wire        fp_a_is_nan;
wire        fp_b_is_nan;

logic [7:0] a_chunk [0:FP_LANES-1];
logic [7:0] b_chunk [0:FP_LANES-1];
logic [1:0] row_index;
logic [7:0] current_a;
logic [7:0] current_b [0:FP_LANES-1];
logic [8:0] encoded_a;
logic [1:0] bw_index;
logic [2:0] bw_cycle;
logic [4:0] drain_count;

logic        fp_multiplicand_valid;
logic [7:0]  fp_multiplicand;
wire  [8:0]  fp_encoded_multiplicand;
wire         fp_encoded_multiplicand_valid;

logic        fp_clr;
wire         fp_clr_to_column;
wire         fp_capture_result;
logic [2:0]  fp_bw_count;
wire  [2:0]  fp_bw_count_delayed;
logic        fp_capture_token;
wire         fp_capture_token_delayed;
logic [2:0]  fp_capture_bw_count;
wire  [2:0]  fp_capture_bw_count_delayed;
wire  [2:0]  fp_shift_bw_count;
logic [7:0]  fp_en_multiplicand;
logic [3:0]  fp_sign_en_multiplicand;
logic        fp_encode_valid;
logic [8*N-1:0] fp_operand_b_pre;
logic [8*N-1:0] fp_operand_b_to_column;
logic        fp_compute_phase;

logic        column_clr;
logic [7:0]  column_en_multiplicand;
logic [3:0]  column_sign_en_multiplicand;
logic        column_encode_valid;
logic [8*N-1:0] column_operand_b;
logic        column_clr_issue;
logic [7:0]  column_en_multiplicand_issue;
logic [3:0]  column_sign_en_multiplicand_issue;
logic        column_encode_valid_issue;
logic [8*N-1:0] column_operand_b_issue;
wire  [1:0]  column_position;
wire  [2:0]  column_cal_cycle;
wire  [52*N-1:0] column_pe_result;
wire  signed [32*N-1:0] shared_lane_fused_result;
wire  signed [32*N-1:0] shared_lane_shifted_result;
wire  signed [63:0] shared_fixed_mac_result;
wire  [63:0] shared_fp_row_accumulated_product;
logic signed [31:0] fp_chunk_acc [0:FP_LANES-1];
logic signed [32*N-1:0] fp_chunk_acc_packed;
logic [63:0] fp_product_acc;
wire  [31:0] fp_result_next;
wire         fp_invalid_next;
wire         fp_overflow_next;
wire         fp_underflow_next;
wire         fp_inexact_next;

integer acc_lane;
integer seq_lane;

assign fp_operand_a_active = ((state == S_IDLE) && fp_start) ? fp_operand_a : fp_operand_a_reg;
assign fp_operand_b_active = ((state == S_IDLE) && fp_start) ? fp_operand_b : fp_operand_b_reg;

fp32_unpack unpack_a (
    .fp(fp_operand_a_active),
    .sign(fp_sign_a),
    .exponent(fp_exponent_a),
    .fraction(fp_fraction_a),
    .mantissa(fp_unpacked_mantissa_a),
    .is_zero(fp_a_is_zero),
    .is_subnormal(fp_a_is_subnormal),
    .is_inf(fp_a_is_inf),
    .is_nan(fp_a_is_nan)
);

fp32_unpack unpack_b (
    .fp(fp_operand_b_active),
    .sign(fp_sign_b),
    .exponent(fp_exponent_b),
    .fraction(fp_fraction_b),
    .mantissa(fp_unpacked_mantissa_b),
    .is_zero(fp_b_is_zero),
    .is_subnormal(fp_b_is_subnormal),
    .is_inf(fp_b_is_inf),
    .is_nan(fp_b_is_nan)
);

fp32_mul_postprocess fp_postprocess (
    .operand_a(fp_operand_a_reg),
    .operand_b(fp_operand_b_reg),
    .mantissa_product(fp_product_acc[47:0]),
    .result(fp_result_next),
    .invalid(fp_invalid_next),
    .overflow(fp_overflow_next),
    .underflow(fp_underflow_next),
    .inexact(fp_inexact_next)
);

always_comb begin
    a_chunk[0] = {1'b0, fp_unpacked_mantissa_a[6:0]};
    a_chunk[1] = {1'b0, fp_unpacked_mantissa_a[13:7]};
    a_chunk[2] = {1'b0, fp_unpacked_mantissa_a[20:14]};
    a_chunk[3] = {5'b0, fp_unpacked_mantissa_a[23:21]};

    b_chunk[0] = {1'b0, fp_unpacked_mantissa_b[6:0]};
    b_chunk[1] = {1'b0, fp_unpacked_mantissa_b[13:7]};
    b_chunk[2] = {1'b0, fp_unpacked_mantissa_b[20:14]};
    b_chunk[3] = {5'b0, fp_unpacked_mantissa_b[23:21]};
end

assign fp_capture_result = fp_capture_token_delayed;
assign fp_shift_bw_count = fp_capture_bw_count_delayed;

encoder_multi_bit fp_encoder (
    .clk(clk),
    .rst_n(rst_n),
    .multiplicand(fp_multiplicand),
    .multiplicand_valid(fp_multiplicand_valid),
    .en_multiplicand(fp_encoded_multiplicand),
    .en_multiplicand_valid(fp_encoded_multiplicand_valid)
);

get_pipeline_mulwidth #(
    .N(FP_CLR_DELAY_CYCLES),
    .WIDTH(1)
) fp_clr_delay (
    .clk(clk),
    .rst_n(rst_n),
    .signal(fp_clr),
    .pipeline_signal(fp_clr_to_column)
);

get_pipeline_mulwidth #(
    .N(FP_BW_DELAY_CYCLES),
    .WIDTH(3)
) fp_bw_delay (
    .clk(clk),
    .rst_n(rst_n),
    .signal(fp_bw_count),
    .pipeline_signal(fp_bw_count_delayed)
);

get_pipeline_mulwidth #(
    .N(FP_CAPTURE_TOKEN_DELAY_CYCLES),
    .WIDTH(1)
) fp_capture_token_delay (
    .clk(clk),
    .rst_n(rst_n),
    .signal(fp_capture_token),
    .pipeline_signal(fp_capture_token_delayed)
);

get_pipeline_mulwidth #(
    .N(FP_CAPTURE_TOKEN_DELAY_CYCLES),
    .WIDTH(3)
) fp_capture_bw_delay (
    .clk(clk),
    .rst_n(rst_n),
    .signal(fp_capture_bw_count),
    .pipeline_signal(fp_capture_bw_count_delayed)
);

top_pe_column_pipe #(
    .N(N)
) shared_column (
    .clk(clk),
    .rst_n(rst_n),
    .clr(column_clr_issue),
    .en_multiplicand(column_en_multiplicand_issue),
    .sign_en_multiplicand(column_sign_en_multiplicand_issue),
    .encode_valid(column_encode_valid_issue),
    .operand_b(column_operand_b_issue),
    .position(column_position),
    .cal_cycle(column_cal_cycle),
    .pe_result(column_pe_result)
);

assign column_clr                  = mode_fp ? fp_clr_to_column : int_clr;
assign column_en_multiplicand      = mode_fp ? fp_en_multiplicand : int_en_multiplicand;
assign column_sign_en_multiplicand = mode_fp ? fp_sign_en_multiplicand : int_sign_en_multiplicand;
assign column_encode_valid         = mode_fp ? fp_encode_valid : int_encode_valid;
assign column_operand_b            = mode_fp ? fp_operand_b_to_column : int_operand_b;

assign int_position  = column_position;
assign int_cal_cycle = column_cal_cycle;
assign int_pe_result = column_pe_result;
assign int_lane_result = shared_lane_fused_result;
assign int_mac_result = shared_fixed_mac_result;

assign fp_busy = mode_fp && (state != S_IDLE);

always_comb begin
    case (bw_index)
        2'd0: fp_en_multiplicand = {6'd0, encoded_a[1:0]};
        2'd1: fp_en_multiplicand = {6'd0, encoded_a[3:2]};
        2'd2: fp_en_multiplicand = {6'd0, encoded_a[5:4]};
        default: fp_en_multiplicand = {6'd0, encoded_a[7:6]};
    endcase
end

assign fp_sign_en_multiplicand = {3'd0, encoded_a[8]};

always_comb begin
    fp_chunk_acc_packed = '0;
    for (acc_lane = 0; acc_lane < FP_LANES; acc_lane = acc_lane + 1) begin
        fp_chunk_acc_packed[32*acc_lane +: 32] = fp_chunk_acc[acc_lane];
    end
end

opt4c_column_shift_accum_backend #(
    .N(N),
    .ACC_WIDTH(26)
) shared_backend (
    .lane_csa_result(column_pe_result),
    .local_shift({fp_shift_bw_count, 1'b0}),
    .row_index(row_index),
    .fp_chunk_acc(fp_chunk_acc_packed),
    .fp_product_acc(fp_product_acc),
    .lane_fused_result(shared_lane_fused_result),
    .lane_shifted_result(shared_lane_shifted_result),
    .fixed_mac_result(shared_fixed_mac_result),
    .fp_row_accumulated_product(shared_fp_row_accumulated_product)
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fp_operand_b_to_column <= {8*N{1'b0}};
        column_clr_issue <= 1'b0;
        column_en_multiplicand_issue <= 8'd0;
        column_sign_en_multiplicand_issue <= 4'd0;
        column_encode_valid_issue <= 1'b0;
        column_operand_b_issue <= {8*N{1'b0}};
    end else begin
        fp_operand_b_to_column <= fp_operand_b_pre;
        column_clr_issue <= column_clr;
        column_en_multiplicand_issue <= column_en_multiplicand;
        column_sign_en_multiplicand_issue <= column_sign_en_multiplicand;
        column_encode_valid_issue <= column_encode_valid;
        column_operand_b_issue <= column_operand_b;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        row_index <= 2'd0;
        current_a <= 8'd0;
        encoded_a <= 9'd0;
        bw_index <= 2'd0;
        bw_cycle <= 3'd0;
        drain_count <= 5'd0;
        fp_multiplicand <= 8'd0;
        fp_multiplicand_valid <= 1'b0;
        fp_clr <= 1'b0;
        fp_bw_count <= 3'd0;
        fp_capture_token <= 1'b0;
        fp_capture_bw_count <= 3'd0;
        fp_encode_valid <= 1'b0;
        fp_operand_b_pre <= {8*N{1'b0}};
        fp_compute_phase <= 1'b0;
        fp_product_acc <= 64'd0;
        fp_operand_a_reg <= 32'd0;
        fp_operand_b_reg <= 32'd0;
        fp_min_group_reg <= 3'd0;
        fp_mantissa_product <= 48'd0;
        fp_result <= 32'd0;
        fp_invalid <= 1'b0;
        fp_overflow <= 1'b0;
        fp_underflow <= 1'b0;
        fp_inexact <= 1'b0;
        fp_done <= 1'b0;
        fp_result_valid <= 1'b0;
        for (seq_lane = 0; seq_lane < FP_LANES; seq_lane = seq_lane + 1) begin
            current_b[seq_lane] <= 8'd0;
            fp_chunk_acc[seq_lane] <= 32'sd0;
        end
    end else begin
        fp_multiplicand_valid <= 1'b0;
        fp_encode_valid <= 1'b0;
        fp_done <= 1'b0;
        fp_result_valid <= 1'b0;
        fp_capture_token <= 1'b0;

        if (mode_fp && fp_compute_phase && fp_capture_result) begin
            for (seq_lane = 0; seq_lane < FP_LANES; seq_lane = seq_lane + 1) begin
                fp_chunk_acc[seq_lane] <= fp_chunk_acc[seq_lane] +
                                          $signed(shared_lane_shifted_result[32*seq_lane +: 32]);
            end
        end

        if (!mode_fp) begin
            state <= S_IDLE;
            fp_clr <= 1'b0;
            fp_bw_count <= 3'd0;
            fp_capture_token <= 1'b0;
            fp_capture_bw_count <= 3'd0;
            fp_operand_b_pre <= {8*N{1'b0}};
            fp_compute_phase <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    row_index <= 2'd0;
                    fp_product_acc <= 64'd0;
                    fp_mantissa_product <= 48'd0;
                    fp_clr <= 1'b0;
                    fp_bw_count <= 3'd0;
                    fp_capture_token <= 1'b0;
                    fp_capture_bw_count <= 3'd0;
                    fp_operand_b_pre <= {8*N{1'b0}};
                    fp_compute_phase <= 1'b0;
                    if (fp_start) begin
                        fp_operand_a_reg <= fp_operand_a;
                        fp_operand_b_reg <= fp_operand_b;
                        fp_min_group_reg <= fp_min_group;
                        state <= S_LOAD_ROW;
                    end
                end

                S_LOAD_ROW: begin
                    current_a <= a_chunk[row_index];
                    for (seq_lane = 0; seq_lane < FP_LANES; seq_lane = seq_lane + 1) begin
                        current_b[seq_lane] <= (((row_index + seq_lane) >= fp_min_group_reg) &&
                                                (a_chunk[row_index] != 8'd0)) ? b_chunk[seq_lane] : 8'd0;
                        fp_chunk_acc[seq_lane] <= 32'sd0;
                    end
                    fp_clr <= 1'b0;
                    fp_bw_count <= 3'd0;
                    fp_operand_b_pre <= {8*N{1'b0}};
                    fp_compute_phase <= 1'b0;
                    state <= S_ENC_START;
                end

                S_ENC_START: begin
                    fp_multiplicand <= current_a;
                    fp_multiplicand_valid <= 1'b1;
                    state <= S_ENC_WAIT;
                end

                S_ENC_WAIT: begin
                    if (fp_encoded_multiplicand_valid) begin
                        encoded_a <= fp_encoded_multiplicand;
                        bw_index <= 2'd0;
                        fp_compute_phase <= 1'b1;
                        state <= S_BW_SETUP;
                    end
                end

                S_BW_SETUP: begin
                    fp_clr <= 1'b1;
                    fp_bw_count <= {1'b0, bw_index};
                    fp_encode_valid <= 1'b1;
                    bw_cycle <= 3'd1;
                    fp_operand_b_pre <= {8*N{1'b0}};
                    state <= S_BW_RUN;
                end

                S_BW_RUN: begin
                    fp_operand_b_pre <= {8*N{1'b0}};
                    if (column_cal_cycle != 3'd0) begin
                        for (seq_lane = 0; seq_lane < FP_LANES; seq_lane = seq_lane + 1) begin
                            fp_operand_b_pre[8*seq_lane +: 8] <= (column_position == 2'd0) ? current_b[seq_lane] : 8'd0;
                        end
                    end

                    if ((column_cal_cycle <= bw_cycle) || (bw_cycle == 3'd4)) begin
                        fp_capture_token <= 1'b1;
                        fp_capture_bw_count <= {1'b0, bw_index};
                        fp_clr <= 1'b0;
                        state <= S_BW_GAP;
                    end else begin
                        bw_cycle <= bw_cycle + 3'd1;
                    end
                end

                S_BW_GAP: begin
                    fp_clr <= 1'b0;
                    fp_operand_b_pre <= {8*N{1'b0}};
                    if (bw_index == 2'd3) begin
                        drain_count <= 5'd0;
                        state <= S_ROW_DRAIN;
                    end else begin
                        bw_index <= bw_index + 2'd1;
                        state <= S_BW_SETUP;
                    end
                end

                S_ROW_DRAIN: begin
                    fp_clr <= 1'b0;
                    fp_operand_b_pre <= {8*N{1'b0}};
                    drain_count <= drain_count + 5'd1;
                    if (drain_count == FP_DRAIN_LIMIT) begin
                        fp_compute_phase <= 1'b0;
                        state <= S_ACC_ROW;
                    end
                end

                S_ACC_ROW: begin
                    fp_product_acc <= shared_fp_row_accumulated_product;
                    if (row_index == 2'd3) begin
                        state <= S_DONE;
                    end else begin
                        row_index <= row_index + 2'd1;
                        state <= S_LOAD_ROW;
                    end
                end

                S_DONE: begin
                    fp_mantissa_product <= fp_product_acc[47:0];
                    fp_result <= fp_result_next;
                    fp_invalid <= fp_invalid_next;
                    fp_overflow <= fp_overflow_next;
                    fp_underflow <= fp_underflow_next;
                    fp_inexact <= fp_inexact_next;
                    fp_result_valid <= 1'b1;
                    fp_done <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
end

endmodule

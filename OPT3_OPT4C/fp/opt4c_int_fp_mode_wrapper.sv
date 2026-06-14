module opt4c_int_fp_mode_wrapper #(
    parameter FP_CLR_DELAY_CYCLES = 3,
    parameter FP_BW_DELAY_CYCLES = 4,
    parameter FP_DRAIN_LIMIT = 5
) (
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

localparam int MAX_PAIRS = 16;

localparam logic [3:0] S_IDLE       = 4'd0;
localparam logic [3:0] S_SCHED      = 4'd1;
localparam logic [3:0] S_LOAD_PAIR  = 4'd2;
localparam logic [3:0] S_ENC_START  = 4'd3;
localparam logic [3:0] S_ENC_WAIT   = 4'd4;
localparam logic [3:0] S_BW_SETUP   = 4'd5;
localparam logic [3:0] S_BW_RUN     = 4'd6;
localparam logic [3:0] S_BW_GAP     = 4'd7;
localparam logic [3:0] S_PAIR_DRAIN = 4'd8;
localparam logic [3:0] S_ACC_PAIR   = 4'd9;
localparam logic [3:0] S_DONE       = 4'd10;

logic [3:0] state;

logic        sched_start;
wire         sched_busy;
wire         sched_valid;
wire         sched_done;
wire  [7:0]  sched_a_operand;
wire  [7:0]  sched_b_operand;
wire  [5:0]  sched_shift_amount;
wire  [15:0] sched_pair_valid_mask;
wire  [6:0]  sched_group_valid_mask;

logic [7:0] pair_a     [0:MAX_PAIRS-1];
logic [7:0] pair_b     [0:MAX_PAIRS-1];
logic [5:0] pair_shift [0:MAX_PAIRS-1];
logic [4:0] pair_count;
logic [4:0] pair_total;
logic [4:0] pair_index;

logic [7:0] current_a;
logic [7:0] current_b;
logic [5:0] current_shift;
logic [8:0] encoded_a;
logic [1:0] bw_index;
logic [2:0] bw_cycle;
logic [2:0] drain_count;

logic        fp_multiplicand_valid;
logic [7:0]  fp_multiplicand;
wire  [8:0]  fp_encoded_multiplicand;
wire         fp_encoded_multiplicand_valid;

logic        fp_clr;
wire         fp_clr_to_pe;
logic [2:0]  fp_bw_count;
wire  [2:0]  fp_bw_count_delayed;
logic [7:0]  fp_en_multiplicand;
logic [3:0]  fp_sign_en_multiplicand;
logic        fp_encode_valid;
logic [7:0]  fp_operand_b_pre;
logic [7:0]  fp_operand_b_to_pe;
logic        fp_compute_phase;

logic        pe_clr;
logic [7:0]  pe_en_multiplicand;
logic [3:0]  pe_sign_en_multiplicand;
logic        pe_encode_valid;
logic [7:0]  pe_operand_b;
logic        pe_clr_issue;
logic [7:0]  pe_en_multiplicand_issue;
logic [3:0]  pe_sign_en_multiplicand_issue;
logic        pe_encode_valid_issue;
logic [7:0]  pe_operand_b_issue;
wire  [1:0]  pe_position;
wire  [2:0]  pe_cal_cycle;
wire  [51:0] pe_result;

logic signed [25:0] fp_fuse_result;
logic signed [31:0] fp_shift_result;
logic signed [31:0] fp_chunk_acc;
logic [63:0] fp_product_acc;

fp32_mantissa_7bit_pair_scheduler fp_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .start(sched_start),
    .mantissa_a(fp_mantissa_a),
    .mantissa_b(fp_mantissa_b),
    .min_group(fp_min_group),
    .busy(sched_busy),
    .valid(sched_valid),
    .done(sched_done),
    .a_operand(sched_a_operand),
    .b_operand(sched_b_operand),
    .a_chunk_index(),
    .b_chunk_index(),
    .group_index(),
    .shift_amount(sched_shift_amount),
    .pair_valid_mask(sched_pair_valid_mask),
    .group_valid_mask(sched_group_valid_mask)
);

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
    .pipeline_signal(fp_clr_to_pe)
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

top_pe shared_top_pe (
    .clk(clk),
    .rst_n(rst_n),
    .clr(pe_clr_issue),
    .en_multiplicand(pe_en_multiplicand_issue),
    .sign_en_multiplicand(pe_sign_en_multiplicand_issue),
    .encode_valid(pe_encode_valid_issue),
    .operand_b(pe_operand_b_issue),
    .position(pe_position),
    .cal_cycle(pe_cal_cycle),
    .pe_result(pe_result)
);

assign pe_clr                  = mode_fp ? fp_clr_to_pe : int_clr;
assign pe_en_multiplicand      = mode_fp ? fp_en_multiplicand : int_en_multiplicand;
assign pe_sign_en_multiplicand = mode_fp ? fp_sign_en_multiplicand : int_sign_en_multiplicand;
assign pe_encode_valid         = mode_fp ? fp_encode_valid : int_encode_valid;
assign pe_operand_b            = mode_fp ? fp_operand_b_to_pe : int_operand_b;

assign int_position  = pe_position;
assign int_cal_cycle = pe_cal_cycle;
assign int_pe_result = pe_result;

assign fp_busy             = mode_fp && (state != S_IDLE);
assign fp_pair_valid_mask  = sched_pair_valid_mask;
assign fp_group_valid_mask = sched_group_valid_mask;

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
    fp_fuse_result = $signed(pe_result[25:0]) + $signed(pe_result[51:26]);
    fp_shift_result = $signed(fp_fuse_result << {fp_bw_count_delayed, 1'b0});
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fp_operand_b_to_pe <= 8'd0;
        pe_clr_issue <= 1'b0;
        pe_en_multiplicand_issue <= 8'd0;
        pe_sign_en_multiplicand_issue <= 4'd0;
        pe_encode_valid_issue <= 1'b0;
        pe_operand_b_issue <= 8'd0;
    end else begin
        fp_operand_b_to_pe <= fp_operand_b_pre;
        pe_clr_issue <= pe_clr;
        pe_en_multiplicand_issue <= pe_en_multiplicand;
        pe_sign_en_multiplicand_issue <= pe_sign_en_multiplicand;
        pe_encode_valid_issue <= pe_encode_valid;
        pe_operand_b_issue <= pe_operand_b;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        sched_start <= 1'b0;
        pair_count <= 5'd0;
        pair_total <= 5'd0;
        pair_index <= 5'd0;
        current_a <= 8'd0;
        current_b <= 8'd0;
        current_shift <= 6'd0;
        encoded_a <= 9'd0;
        bw_index <= 2'd0;
        bw_cycle <= 3'd0;
        drain_count <= 3'd0;
        fp_multiplicand <= 8'd0;
        fp_multiplicand_valid <= 1'b0;
        fp_clr <= 1'b0;
        fp_bw_count <= 3'd0;
        fp_encode_valid <= 1'b0;
        fp_operand_b_pre <= 8'd0;
        fp_compute_phase <= 1'b0;
        fp_chunk_acc <= 32'sd0;
        fp_product_acc <= 64'd0;
        fp_mantissa_product <= 48'd0;
        fp_done <= 1'b0;
        fp_result_valid <= 1'b0;
    end else begin
        sched_start <= 1'b0;
        fp_multiplicand_valid <= 1'b0;
        fp_encode_valid <= 1'b0;
        fp_done <= 1'b0;
        fp_result_valid <= 1'b0;

        if (mode_fp && fp_compute_phase && !fp_clr_to_pe) begin
            fp_chunk_acc <= fp_chunk_acc + fp_shift_result;
        end

        if (!mode_fp) begin
            state <= S_IDLE;
            pair_count <= 5'd0;
            pair_total <= 5'd0;
            pair_index <= 5'd0;
            fp_clr <= 1'b0;
            fp_bw_count <= 3'd0;
            fp_operand_b_pre <= 8'd0;
            fp_compute_phase <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    pair_count <= 5'd0;
                    pair_total <= 5'd0;
                    pair_index <= 5'd0;
                    fp_product_acc <= 64'd0;
                    fp_chunk_acc <= 32'sd0;
                    fp_mantissa_product <= 48'd0;
                    fp_clr <= 1'b0;
                    fp_bw_count <= 3'd0;
                    fp_operand_b_pre <= 8'd0;
                    fp_compute_phase <= 1'b0;
                    if (fp_start) begin
                        sched_start <= 1'b1;
                        state <= S_SCHED;
                    end
                end

                S_SCHED: begin
                    if (sched_valid) begin
                        pair_a[pair_count] <= sched_a_operand;
                        pair_b[pair_count] <= sched_b_operand;
                        pair_shift[pair_count] <= sched_shift_amount;
                        pair_count <= pair_count + 5'd1;
                    end
                    if (sched_done) begin
                        pair_total <= pair_count + (sched_valid ? 5'd1 : 5'd0);
                        pair_index <= 5'd0;
                        state <= S_LOAD_PAIR;
                    end
                end

                S_LOAD_PAIR: begin
                    fp_chunk_acc <= 32'sd0;
                    fp_clr <= 1'b0;
                    fp_bw_count <= 3'd0;
                    fp_operand_b_pre <= 8'd0;
                    fp_compute_phase <= 1'b0;
                    if (pair_index >= pair_total) begin
                        fp_mantissa_product <= fp_product_acc[47:0];
                        fp_result_valid <= 1'b1;
                        fp_done <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        current_a <= pair_a[pair_index];
                        current_b <= pair_b[pair_index];
                        current_shift <= pair_shift[pair_index];
                        state <= S_ENC_START;
                    end
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
                    fp_operand_b_pre <= 8'd0;
                    state <= S_BW_RUN;
                end

                S_BW_RUN: begin
                    if (pe_cal_cycle == 3'd0) begin
                        fp_operand_b_pre <= 8'd0;
                    end else begin
                        fp_operand_b_pre <= (pe_position == 2'd0) ? current_b : 8'd0;
                    end

                    if ((pe_cal_cycle <= bw_cycle) || (bw_cycle == 3'd4)) begin
                        fp_clr <= 1'b0;
                        state <= S_BW_GAP;
                    end else begin
                        bw_cycle <= bw_cycle + 3'd1;
                    end
                end

                S_BW_GAP: begin
                    fp_clr <= 1'b0;
                    fp_operand_b_pre <= 8'd0;
                    if (bw_index == 2'd3) begin
                        drain_count <= 3'd0;
                        state <= S_PAIR_DRAIN;
                    end else begin
                        bw_index <= bw_index + 2'd1;
                        state <= S_BW_SETUP;
                    end
                end

                S_PAIR_DRAIN: begin
                    fp_clr <= 1'b0;
                    fp_operand_b_pre <= 8'd0;
                    drain_count <= drain_count + 3'd1;
                    if (drain_count == FP_DRAIN_LIMIT) begin
                        fp_compute_phase <= 1'b0;
                        state <= S_ACC_PAIR;
                    end
                end

                S_ACC_PAIR: begin
                    fp_product_acc <= fp_product_acc + ({32'd0, fp_chunk_acc} << current_shift);
                    pair_index <= pair_index + 5'd1;
                    state <= S_LOAD_PAIR;
                end

                S_DONE: begin
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

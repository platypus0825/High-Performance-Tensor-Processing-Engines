module opt4c_column_int_fp_mode_wrapper #(
    parameter N = 4
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

    input  logic             fp_start,
    input  logic [23:0]      fp_mantissa_a,
    input  logic [23:0]      fp_mantissa_b,
    input  logic [2:0]       fp_min_group,
    output logic             fp_busy,
    output logic             fp_done,
    output logic             fp_result_valid,
    output logic [47:0]      fp_mantissa_product
);

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

logic [7:0] a_chunk [0:3];
logic [7:0] b_chunk [0:3];
logic [1:0] row_index;
logic [7:0] current_a;
logic [7:0] current_b [0:3];
logic [8:0] encoded_a;
logic [1:0] bw_index;
logic [2:0] bw_cycle;
logic [2:0] drain_count;

logic        fp_multiplicand_valid;
logic [7:0]  fp_multiplicand;
wire  [8:0]  fp_encoded_multiplicand;
wire         fp_encoded_multiplicand_valid;

logic        fp_clr;
wire         fp_clr_to_column;
logic [2:0]  fp_bw_count;
wire  [2:0]  fp_bw_count_delayed;
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
wire  [1:0]  column_position;
wire  [2:0]  column_cal_cycle;
wire  [52*N-1:0] column_pe_result;

logic signed [25:0] fp_fuse_result [0:3];
logic signed [31:0] fp_shift_result [0:3];
logic signed [31:0] fp_chunk_acc [0:3];
logic [63:0] fp_product_acc;
logic [63:0] fp_row_accumulated_product;

integer fuse_lane;
integer acc_lane;
integer seq_lane;

always_comb begin
    a_chunk[0] = {1'b0, fp_mantissa_a[6:0]};
    a_chunk[1] = {1'b0, fp_mantissa_a[13:7]};
    a_chunk[2] = {1'b0, fp_mantissa_a[20:14]};
    a_chunk[3] = {5'b0, fp_mantissa_a[23:21]};

    b_chunk[0] = {1'b0, fp_mantissa_b[6:0]};
    b_chunk[1] = {1'b0, fp_mantissa_b[13:7]};
    b_chunk[2] = {1'b0, fp_mantissa_b[20:14]};
    b_chunk[3] = {5'b0, fp_mantissa_b[23:21]};
end

encoder_multi_bit fp_encoder (
    .clk(clk),
    .rst_n(rst_n),
    .multiplicand(fp_multiplicand),
    .multiplicand_valid(fp_multiplicand_valid),
    .en_multiplicand(fp_encoded_multiplicand),
    .en_multiplicand_valid(fp_encoded_multiplicand_valid)
);

get_pipeline_mulwidth #(
    .N(3),
    .WIDTH(1)
) fp_clr_delay (
    .clk(clk),
    .rst_n(rst_n),
    .signal(fp_clr),
    .pipeline_signal(fp_clr_to_column)
);

get_pipeline_mulwidth #(
    .N(4),
    .WIDTH(3)
) fp_bw_delay (
    .clk(clk),
    .rst_n(rst_n),
    .signal(fp_bw_count),
    .pipeline_signal(fp_bw_count_delayed)
);

top_pe_column #(
    .N(N)
) shared_column (
    .clk(clk),
    .rst_n(rst_n),
    .clr(column_clr),
    .en_multiplicand(column_en_multiplicand),
    .sign_en_multiplicand(column_sign_en_multiplicand),
    .encode_valid(column_encode_valid),
    .operand_b(column_operand_b),
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
    for (fuse_lane = 0; fuse_lane < 4; fuse_lane = fuse_lane + 1) begin
        fp_fuse_result[fuse_lane] = $signed(column_pe_result[52*fuse_lane +: 26]) +
                                    $signed(column_pe_result[52*fuse_lane+26 +: 26]);
        fp_shift_result[fuse_lane] = $signed(fp_fuse_result[fuse_lane] << {fp_bw_count_delayed, 1'b0});
    end
end

always_comb begin
    fp_row_accumulated_product = fp_product_acc;
    for (acc_lane = 0; acc_lane < 4; acc_lane = acc_lane + 1) begin
        fp_row_accumulated_product = fp_row_accumulated_product +
            ({32'd0, fp_chunk_acc[acc_lane]} << (7 * (row_index + acc_lane)));
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fp_operand_b_to_column <= {8*N{1'b0}};
    end else begin
        fp_operand_b_to_column <= fp_operand_b_pre;
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
        drain_count <= 3'd0;
        fp_multiplicand <= 8'd0;
        fp_multiplicand_valid <= 1'b0;
        fp_clr <= 1'b0;
        fp_bw_count <= 3'd0;
        fp_encode_valid <= 1'b0;
        fp_operand_b_pre <= {8*N{1'b0}};
        fp_compute_phase <= 1'b0;
        fp_product_acc <= 64'd0;
        fp_mantissa_product <= 48'd0;
        fp_done <= 1'b0;
        fp_result_valid <= 1'b0;
        for (seq_lane = 0; seq_lane < 4; seq_lane = seq_lane + 1) begin
            current_b[seq_lane] <= 8'd0;
            fp_chunk_acc[seq_lane] <= 32'sd0;
        end
    end else begin
        fp_multiplicand_valid <= 1'b0;
        fp_encode_valid <= 1'b0;
        fp_done <= 1'b0;
        fp_result_valid <= 1'b0;

        if (mode_fp && fp_compute_phase && !fp_clr_to_column) begin
            for (seq_lane = 0; seq_lane < 4; seq_lane = seq_lane + 1) begin
                fp_chunk_acc[seq_lane] <= fp_chunk_acc[seq_lane] + fp_shift_result[seq_lane];
            end
        end

        if (!mode_fp) begin
            state <= S_IDLE;
            fp_clr <= 1'b0;
            fp_bw_count <= 3'd0;
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
                    fp_operand_b_pre <= {8*N{1'b0}};
                    fp_compute_phase <= 1'b0;
                    if (fp_start) begin
                        state <= S_LOAD_ROW;
                    end
                end

                S_LOAD_ROW: begin
                    current_a <= a_chunk[row_index];
                    for (seq_lane = 0; seq_lane < 4; seq_lane = seq_lane + 1) begin
                        current_b[seq_lane] <= (((row_index + seq_lane) >= fp_min_group) &&
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
                        for (seq_lane = 0; seq_lane < 4; seq_lane = seq_lane + 1) begin
                            fp_operand_b_pre[8*seq_lane +: 8] <= (column_position == 2'd0) ? current_b[seq_lane] : 8'd0;
                        end
                    end

                    if ((column_cal_cycle <= bw_cycle) || (bw_cycle == 3'd4)) begin
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
                        drain_count <= 3'd0;
                        state <= S_ROW_DRAIN;
                    end else begin
                        bw_index <= bw_index + 2'd1;
                        state <= S_BW_SETUP;
                    end
                end

                S_ROW_DRAIN: begin
                    fp_clr <= 1'b0;
                    fp_operand_b_pre <= {8*N{1'b0}};
                    drain_count <= drain_count + 3'd1;
                    if (drain_count == 3'd5) begin
                        fp_compute_phase <= 1'b0;
                        state <= S_ACC_ROW;
                    end
                end

                S_ACC_ROW: begin
                    fp_product_acc <= fp_row_accumulated_product;
                    if (row_index == 2'd3) begin
                        state <= S_DONE;
                    end else begin
                        row_index <= row_index + 2'd1;
                        state <= S_LOAD_ROW;
                    end
                end

                S_DONE: begin
                    fp_mantissa_product <= fp_product_acc[47:0];
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

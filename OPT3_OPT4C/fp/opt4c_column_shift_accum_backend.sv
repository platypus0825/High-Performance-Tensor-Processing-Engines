module opt4c_column_shift_accum_backend #(
    parameter N = 4,
    parameter ACC_WIDTH = 26
) (
    input  logic [52*N-1:0]              lane_csa_result,
    input  logic [3:0]                   local_shift,
    input  logic [1:0]                   row_index,
    input  logic signed [32*N-1:0]       fp_chunk_acc,
    input  logic [63:0]                  fp_product_acc,
    output logic signed [32*N-1:0]       lane_fused_result,
    output logic signed [32*N-1:0]       lane_shifted_result,
    output logic signed [63:0]           fixed_mac_result,
    output logic [63:0]                  fp_row_accumulated_product
);

localparam int LANE_CSA_WIDTH = 52;
localparam int FUSED_WIDTH = ACC_WIDTH + 1;

integer lane;
logic signed [ACC_WIDTH-1:0] sum_part;
logic signed [ACC_WIDTH-1:0] carry_part;
logic signed [FUSED_WIDTH-1:0] lane_sum;
logic signed [31:0] lane_fused32;
logic signed [31:0] lane_shifted32;
logic signed [31:0] chunk_acc32;

always_comb begin
    lane_fused_result = '0;
    lane_shifted_result = '0;
    fixed_mac_result = 64'sd0;
    fp_row_accumulated_product = fp_product_acc;

    for (lane = 0; lane < N; lane = lane + 1) begin
        sum_part = $signed(lane_csa_result[LANE_CSA_WIDTH*lane +: ACC_WIDTH]);
        carry_part = $signed(lane_csa_result[LANE_CSA_WIDTH*lane+ACC_WIDTH +: ACC_WIDTH]);
        lane_sum = $signed({sum_part[ACC_WIDTH-1], sum_part}) +
                   $signed({carry_part[ACC_WIDTH-1], carry_part});

        lane_fused32 = {{(32-FUSED_WIDTH){lane_sum[FUSED_WIDTH-1]}}, lane_sum};
        lane_shifted32 = $signed(lane_fused32 <<< local_shift);
        chunk_acc32 = $signed(fp_chunk_acc[32*lane +: 32]);

        lane_fused_result[32*lane +: 32] = lane_fused32;
        lane_shifted_result[32*lane +: 32] = lane_shifted32;
        fixed_mac_result = fixed_mac_result + {{32{lane_fused32[31]}}, lane_fused32};
        fp_row_accumulated_product = fp_row_accumulated_product +
            ({32'd0, chunk_acc32} << (7 * (row_index + lane)));
    end
end

endmodule

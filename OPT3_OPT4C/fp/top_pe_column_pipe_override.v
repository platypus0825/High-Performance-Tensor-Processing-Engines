module top_pe_column_pipe #(
    parameter N = 4,
    parameter ACC_WIDTH = 26
)(
    input                  clk,
    input                  rst_n,
    input                  clr,
    input   [7:0]          en_multiplicand,
    input   [3:0]          sign_en_multiplicand,
    input                  encode_valid,
    input   [8*N-1:0]      operand_b,
    output  [1:0]          position,
    output  [2:0]          cal_cycle,
    output  [52*N-1:0]     pe_result
);

wire [1:0] partial_product_index;

sparse_encoder sp_encoder (
    .clk(clk),
    .rst_n(rst_n),
    .en_multiplicand(en_multiplicand),
    .sign_en_multiplicand(sign_en_multiplicand),
    .encode_valid(encode_valid),
    .partial_product_index(partial_product_index),
    .position_0(position),
    .cal_cycle(cal_cycle)
);

genvar i;
generate
    for (i = 0; i < N; i = i + 1) begin : gen_pipe_pe
        pe_pipelined #(
            .ACC_WIDTH(ACC_WIDTH)
        ) sparse_pe (
            .clk(clk),
            .rst_n(rst_n),
            .clr(clr),
            .encoder_position_ins(partial_product_index),
            .operand_b_ins(operand_b[8*i +: 8]),
            .result(pe_result[52*i +: 52])
        );
    end
endgenerate

endmodule

module pe_pipelined #(
    parameter ACC_WIDTH = 26
)(
    input               clk,
    input               rst_n,
    input               clr,
    input  wire  [1:0]  encoder_position_ins,
    input  wire  [7:0]  operand_b_ins,
    output wire  [51:0] result
);

reg         [1:0]           encoder_position;
reg  signed [7:0]           operand_b;
reg                         clr_s1;
reg  signed [ACC_WIDTH-1:0] mux_extend_b_s1;
reg  signed [ACC_WIDTH-1:0] acc_sum;
reg  signed [ACC_WIDTH-1:0] acc_carry;

wire signed [8:0] b;
wire signed [8:0] b_2;
wire signed [8:0] neg_b;
wire signed [9:0] neg_b_2;
reg  signed [9:0] mux_select_b;
wire signed [ACC_WIDTH-1:0] mux_extend_b;
wire signed [ACC_WIDTH-1:0] sum;
wire signed [ACC_WIDTH-1:0] carry;
wire signed [ACC_WIDTH-1:0] sum_input;
wire signed [ACC_WIDTH-1:0] carry_input;
wire        [3*ACC_WIDTH-1:0] csa_input;

assign b = $signed(operand_b);
assign b_2 = {operand_b, 1'b0};
assign neg_b = ~b + 1'b1;
assign neg_b_2 = {neg_b, 1'b0};
assign mux_extend_b = mux_select_b;
assign sum_input = !clr_s1 ? {ACC_WIDTH{1'b0}} : acc_sum;
assign carry_input = !clr_s1 ? {ACC_WIDTH{1'b0}} : acc_carry;
assign csa_input = {mux_extend_b_s1, sum_input, carry_input};

always @(*) begin
    case (encoder_position)
        2'd0: mux_select_b = $signed(neg_b_2);
        2'd1: mux_select_b = $signed(b);
        2'd2: mux_select_b = $signed(b_2);
        2'd3: mux_select_b = $signed(neg_b);
        default: mux_select_b = 10'sd0;
    endcase
end

DW02_tree #(3, ACC_WIDTH, 1) U1 (
    .INPUT(csa_input),
    .OUT0(sum),
    .OUT1(carry)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        encoder_position <= 2'd0;
        operand_b <= 8'sd0;
        clr_s1 <= 1'b0;
        mux_extend_b_s1 <= {ACC_WIDTH{1'b0}};
    end else begin
        encoder_position <= encoder_position_ins;
        operand_b <= operand_b_ins;
        clr_s1 <= clr;
        mux_extend_b_s1 <= mux_extend_b;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        acc_sum <= {ACC_WIDTH{1'b0}};
        acc_carry <= {ACC_WIDTH{1'b0}};
    end else begin
        acc_sum <= sum;
        acc_carry <= carry;
    end
end

assign result = {acc_sum, acc_carry};

endmodule

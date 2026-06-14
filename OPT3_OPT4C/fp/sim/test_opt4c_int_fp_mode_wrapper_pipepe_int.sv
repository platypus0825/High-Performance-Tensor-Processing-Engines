module test_opt4c_int_fp_mode_wrapper_pipepe_int;

parameter clk_T = 2.0;

logic        clk;
logic        rst_n;
logic        mode_fp;

logic        int_clr;
logic [7:0]  int_en_multiplicand;
logic [3:0]  int_sign_en_multiplicand;
logic        int_encode_valid;
logic [7:0]  int_operand_b;
wire  [1:0]  int_position;
wire  [2:0]  int_cal_cycle;
wire  [51:0] int_pe_result;

wire  [1:0]  ref_position;
wire  [2:0]  ref_cal_cycle;
wire  [51:0] ref_pe_result;
logic        ref_int_clr;
logic [7:0]  ref_int_en_multiplicand;
logic [3:0]  ref_int_sign_en_multiplicand;
logic        ref_int_encode_valid;
logic [7:0]  ref_int_operand_b;

opt4c_int_fp_mode_wrapper dut (
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
    .fp_start(1'b0),
    .fp_mantissa_a(24'd0),
    .fp_mantissa_b(24'd0),
    .fp_min_group(3'd0),
    .fp_busy(),
    .fp_done(),
    .fp_result_valid(),
    .fp_mantissa_product(),
    .fp_pair_valid_mask(),
    .fp_group_valid_mask()
);

top_pe ref_int_pe (
    .clk(clk),
    .rst_n(rst_n),
    .clr(ref_int_clr),
    .en_multiplicand(ref_int_en_multiplicand),
    .sign_en_multiplicand(ref_int_sign_en_multiplicand),
    .encode_valid(ref_int_encode_valid),
    .operand_b(ref_int_operand_b),
    .position(ref_position),
    .cal_cycle(ref_cal_cycle),
    .pe_result(ref_pe_result)
);

initial begin
    clk = 1'b0;
    forever #(clk_T / 2) clk = ~clk;
end

initial begin
    initialize();
    check_int_passthrough();
    $display("\033[1;32mSUCCESS: OPT4C INT/FP wrapper pipelined-PE INT-mode test passed.\033[0m");
    $finish;
end

task initialize;
    begin
        rst_n = 1'b0;
        mode_fp = 1'b0;
        int_clr = 1'b0;
        int_en_multiplicand = 8'd0;
        int_sign_en_multiplicand = 4'd0;
        int_encode_valid = 1'b0;
        int_operand_b = 8'd0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
    end
endtask

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ref_int_clr <= 1'b0;
        ref_int_en_multiplicand <= 8'd0;
        ref_int_sign_en_multiplicand <= 4'd0;
        ref_int_encode_valid <= 1'b0;
        ref_int_operand_b <= 8'd0;
    end else begin
        ref_int_clr <= int_clr;
        ref_int_en_multiplicand <= int_en_multiplicand;
        ref_int_sign_en_multiplicand <= int_sign_en_multiplicand;
        ref_int_encode_valid <= int_encode_valid;
        ref_int_operand_b <= int_operand_b;
    end
end

task check_int_passthrough;
    integer cycle;
    begin
        mode_fp = 1'b0;
        for (cycle = 0; cycle < 120; cycle = cycle + 1) begin
            @(negedge clk);
            int_clr = (cycle % 7) != 0;
            int_encode_valid = (cycle % 5) == 0;
            int_en_multiplicand = $urandom() & 8'hff;
            int_sign_en_multiplicand = $urandom() & 4'hf;
            int_operand_b = $urandom() & 8'hff;
            @(posedge clk);
            #1;
            if ((int_position !== ref_position) ||
                (int_cal_cycle !== ref_cal_cycle) ||
                (int_pe_result !== ref_pe_result)) begin
                $error("pipelined PE INT passthrough mismatch cycle=%0d", cycle);
                #1 $finish;
            end
        end
    end
endtask

endmodule

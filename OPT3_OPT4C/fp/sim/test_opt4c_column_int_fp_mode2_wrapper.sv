module test_opt4c_column_int_fp_mode2_wrapper;

parameter clk_T = 2.0;
parameter N = 4;

logic             clk;
logic             rst_n;
logic [1:0]       mode;
logic             int_clr;
logic [7:0]       int_en_multiplicand;
logic [3:0]       int_sign_en_multiplicand;
logic             int_encode_valid;
logic [8*N-1:0]   int_operand_b;
wire  [1:0]       int_position;
wire  [2:0]       int_cal_cycle;
wire  [52*N-1:0]  int_pe_result;
logic             fp_start;
logic [23:0]      fp_mantissa_a;
logic [23:0]      fp_mantissa_b;
wire              fp_busy;
wire              fp_done;
wire              fp_result_valid;
wire  [47:0]      fp_mantissa_product;

wire  [1:0]       ref_position;
wire  [2:0]       ref_cal_cycle;
wire  [52*N-1:0]  ref_pe_result;
logic             ref_int_clr;
logic [7:0]       ref_int_en_multiplicand;
logic [3:0]       ref_int_sign_en_multiplicand;
logic             ref_int_encode_valid;
logic [8*N-1:0]   ref_int_operand_b;

integer test_id;

opt4c_column_int_fp_mode2_wrapper #(
    .N(N)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .mode(mode),
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
    .fp_busy(fp_busy),
    .fp_done(fp_done),
    .fp_result_valid(fp_result_valid),
    .fp_mantissa_product(fp_mantissa_product)
);

top_pe_column_pipe #(
    .N(N)
) ref_column (
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

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ref_int_clr <= 1'b0;
        ref_int_en_multiplicand <= 8'd0;
        ref_int_sign_en_multiplicand <= 4'd0;
        ref_int_encode_valid <= 1'b0;
        ref_int_operand_b <= {8*N{1'b0}};
    end else begin
        ref_int_clr <= int_clr;
        ref_int_en_multiplicand <= int_en_multiplicand;
        ref_int_sign_en_multiplicand <= int_sign_en_multiplicand;
        ref_int_encode_valid <= int_encode_valid;
        ref_int_operand_b <= int_operand_b;
    end
end

initial begin
    clk = 1'b0;
    forever #(clk_T / 2) clk = ~clk;
end

initial begin
    initialize();
    check_int_passthrough();

    check_fp_mode(2'b01, 24'h800000, 24'h800000);
    check_fp_mode(2'b01, 24'hffffff, 24'hffffff);
    check_fp_mode(2'b10, 24'hffffff, 24'hffffff);
    check_fp_mode(2'b11, 24'hffffff, 24'hffffff);
    check_fp_mode(2'b10, 24'h812345, 24'h8abcde);
    check_fp_mode(2'b11, 24'h812345, 24'h8abcde);

    repeat (20) begin
        check_fp_mode(2'b01, $urandom() & 24'hffffff, $urandom() & 24'hffffff);
        check_fp_mode(2'b10, $urandom() & 24'hffffff, $urandom() & 24'hffffff);
        check_fp_mode(2'b11, $urandom() & 24'hffffff, $urandom() & 24'hffffff);
    end

    $display("\033[1;32mSUCCESS: OPT4C column 2-bit mode wrapper tests passed.\033[0m");
    $finish;
end

task initialize;
    begin
        rst_n = 1'b0;
        mode = 2'b00;
        int_clr = 1'b0;
        int_en_multiplicand = 8'd0;
        int_sign_en_multiplicand = 4'd0;
        int_encode_valid = 1'b0;
        int_operand_b = {8*N{1'b0}};
        fp_start = 1'b0;
        fp_mantissa_a = 24'd0;
        fp_mantissa_b = 24'd0;
        test_id = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
    end
endtask

task check_int_passthrough;
    integer cycle;
    begin
        mode = 2'b00;
        for (cycle = 0; cycle < 80; cycle = cycle + 1) begin
            @(negedge clk);
            int_clr = (cycle % 7) != 0;
            int_encode_valid = (cycle % 5) == 0;
            int_en_multiplicand = $urandom() & 8'hff;
            int_sign_en_multiplicand = $urandom() & 4'hf;
            int_operand_b = {$urandom(), $urandom()} & {8*N{1'b1}};
            @(posedge clk);
            #1;
            if ((int_position !== ref_position) ||
                (int_cal_cycle !== ref_cal_cycle) ||
                (int_pe_result !== ref_pe_result)) begin
                $error("2-bit mode INT passthrough mismatch cycle=%0d", cycle);
                #1 $finish;
            end
        end

        @(negedge clk);
        int_clr = 1'b0;
        int_encode_valid = 1'b0;
        int_en_multiplicand = 8'd0;
        int_sign_en_multiplicand = 4'd0;
        int_operand_b = {8*N{1'b0}};
        repeat (4) @(posedge clk);
    end
endtask

task check_fp_mode;
    input [1:0]  test_mode;
    input [23:0] a;
    input [23:0] b;
    reg [47:0] golden;
    reg [2:0] min_group;
    integer cycles;
    begin
        test_id = test_id + 1;
        min_group = mode_to_min_group(test_mode);
        golden = pruned_product(a, b, min_group);

        @(negedge clk);
        mode = test_mode;
        fp_mantissa_a = a;
        fp_mantissa_b = b;
        fp_start = 1'b1;
        @(negedge clk);
        fp_start = 1'b0;

        cycles = 0;
        while (!fp_done) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            if (cycles > 1200) begin
                $error("2-bit mode FP timeout test=%0d mode=%b a=%h b=%h",
                       test_id, test_mode, a, b);
                #1 $finish;
            end
        end

        if (!fp_result_valid) begin
            $error("2-bit mode FP done without result_valid test=%0d", test_id);
            #1 $finish;
        end

        if (fp_mantissa_product !== golden) begin
            $error("2-bit mode FP mismatch test=%0d mode=%b min_group=%0d a=%h b=%h expected=%h got=%h cycles=%0d",
                   test_id, test_mode, min_group, a, b, golden, fp_mantissa_product, cycles);
            #1 $finish;
        end

        @(negedge clk);
        mode = 2'b00;
        repeat (6) @(posedge clk);
    end
endtask

function [2:0] mode_to_min_group;
    input [1:0] test_mode;
    begin
        case (test_mode)
            2'b10: mode_to_min_group = 3'd1;
            2'b11: mode_to_min_group = 3'd2;
            default: mode_to_min_group = 3'd0;
        endcase
    end
endfunction

function [7:0] get_mantissa_chunk;
    input [23:0] value;
    input integer chunk_index;
    begin
        case (chunk_index)
            0: get_mantissa_chunk = {1'b0, value[6:0]};
            1: get_mantissa_chunk = {1'b0, value[13:7]};
            2: get_mantissa_chunk = {1'b0, value[20:14]};
            default: get_mantissa_chunk = {5'b0, value[23:21]};
        endcase
    end
endfunction

function [47:0] pruned_product;
    input [23:0] a;
    input [23:0] b;
    input [2:0]  prune_min_group;
    reg [63:0] acc;
    reg [15:0] pair_product;
    integer i;
    integer j;
    begin
        acc = 64'd0;
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                if ((i + j) >= prune_min_group) begin
                    pair_product = get_mantissa_chunk(a, i) * get_mantissa_chunk(b, j);
                    acc = acc + ({48'd0, pair_product} << (7 * (i + j)));
                end
            end
        end
        pruned_product = acc[47:0];
    end
endfunction

endmodule

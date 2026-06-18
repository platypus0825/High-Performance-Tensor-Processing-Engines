module test_opt4c_column_unified_int_fp_wrapper;

parameter clk_T = 2.0;
parameter N = 4;

logic clk;
logic rst_n;
logic [1:0] mode;
logic start;
logic [31:0] operand_a;
logic [31:0] operand_b;
wire busy;
wire done;
wire result_valid;
wire [31:0] result;
wire signed [15:0] int_result;
wire [47:0] fp_mantissa_product;
wire [31:0] fp_result;
wire fp_invalid;
wire fp_overflow;
wire fp_underflow;
wire fp_inexact;

logic [31:0] ref_fp_operand_a;
logic [31:0] ref_fp_operand_b;
logic [47:0] ref_mantissa_product;
wire [31:0] ref_fp_result;
wire ref_fp_invalid;
wire ref_fp_overflow;
wire ref_fp_underflow;
wire ref_fp_inexact;

integer test_id;

opt4c_column_unified_int_fp_wrapper #(
    .N(N)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .mode(mode),
    .start(start),
    .operand_a(operand_a),
    .operand_b(operand_b),
    .busy(busy),
    .done(done),
    .result_valid(result_valid),
    .result(result),
    .int_result(int_result),
    .fp_mantissa_product(fp_mantissa_product),
    .fp_result(fp_result),
    .fp_invalid(fp_invalid),
    .fp_overflow(fp_overflow),
    .fp_underflow(fp_underflow),
    .fp_inexact(fp_inexact)
);

fp32_mul_postprocess ref_postprocess (
    .operand_a(ref_fp_operand_a),
    .operand_b(ref_fp_operand_b),
    .mantissa_product(ref_mantissa_product),
    .result(ref_fp_result),
    .invalid(ref_fp_invalid),
    .overflow(ref_fp_overflow),
    .underflow(ref_fp_underflow),
    .inexact(ref_fp_inexact)
);

initial begin
    clk = 1'b0;
    forever #(clk_T / 2) clk = ~clk;
end

initial begin
    initialize();

    check_int_case(8'sd7, 8'sd9);
    check_int_case(-8'sd7, 8'sd9);
    check_int_case(8'sd127, -8'sd2);
    check_int_case(-8'sd128, 8'sd1);
    repeat (40) begin
        check_int_case($signed($urandom() & 8'hff), $signed($urandom() & 8'hff));
    end

    check_fp_mode(2'b01, fp32_from_mantissa(24'h800000), fp32_from_mantissa(24'h800000));
    check_fp_mode(2'b01, fp32_from_mantissa(24'hffffff), fp32_from_mantissa(24'hffffff));
    check_fp_mode(2'b10, fp32_from_mantissa(24'hffffff), fp32_from_mantissa(24'hffffff));
    check_fp_mode(2'b11, fp32_from_mantissa(24'hffffff), fp32_from_mantissa(24'hffffff));

    repeat (12) begin
        check_fp_mode(2'b01, fp32_from_mantissa(24'h800000 | ($urandom() & 24'h7fffff)),
                              fp32_from_mantissa(24'h800000 | ($urandom() & 24'h7fffff)));
        check_fp_mode(2'b10, fp32_from_mantissa(24'h800000 | ($urandom() & 24'h7fffff)),
                              fp32_from_mantissa(24'h800000 | ($urandom() & 24'h7fffff)));
        check_fp_mode(2'b11, fp32_from_mantissa(24'h800000 | ($urandom() & 24'h7fffff)),
                              fp32_from_mantissa(24'h800000 | ($urandom() & 24'h7fffff)));
    end

    $display("\033[1;32mSUCCESS: OPT4C unified INT/FP input wrapper tests passed.\033[0m");
    $finish;
end

task initialize;
    begin
        rst_n = 1'b0;
        mode = 2'b00;
        start = 1'b0;
        operand_a = 32'd0;
        operand_b = 32'd0;
        ref_fp_operand_a = 32'd0;
        ref_fp_operand_b = 32'd0;
        ref_mantissa_product = 48'd0;
        test_id = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
    end
endtask

task check_int_case;
    input signed [7:0] a;
    input signed [7:0] b;
    reg signed [15:0] golden;
    begin
        test_id = test_id + 1;
        golden = a * b;

        @(negedge clk);
        mode = 2'b00;
        operand_a = {{24{a[7]}}, a};
        operand_b = {{24{b[7]}}, b};
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        @(posedge clk);
        #1;
        if (!done || !result_valid || (int_result !== golden) ||
            (result !== {{16{golden[15]}}, golden})) begin
            $error("unified INT mismatch test=%0d a=%0d b=%0d expected=%0d got_int=%0d got_result=%h done=%b valid=%b",
                   test_id, a, b, golden, int_result, result, done, result_valid);
            #1 $finish;
        end

        @(negedge clk);
    end
endtask

task check_fp_mode;
    input [1:0] test_mode;
    input [31:0] a;
    input [31:0] b;
    reg [23:0] mantissa_a;
    reg [23:0] mantissa_b;
    reg [47:0] golden;
    reg [2:0] min_group;
    integer cycles;
    begin
        test_id = test_id + 1;
        min_group = mode_to_min_group(test_mode);
        mantissa_a = unpack_fp32_mantissa(a);
        mantissa_b = unpack_fp32_mantissa(b);
        golden = pruned_product(mantissa_a, mantissa_b, min_group);
        ref_fp_operand_a = a;
        ref_fp_operand_b = b;
        ref_mantissa_product = golden;
        #1;

        @(negedge clk);
        mode = test_mode;
        operand_a = a;
        operand_b = b;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        cycles = 0;
        while (!done) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            if (cycles > 1400) begin
                $error("unified FP timeout test=%0d mode=%b a=%h b=%h",
                       test_id, test_mode, a, b);
                #1 $finish;
            end
        end

        if (!result_valid ||
            (fp_mantissa_product !== golden) ||
            (fp_result !== ref_fp_result) ||
            (result !== ref_fp_result) ||
            (fp_invalid !== ref_fp_invalid) ||
            (fp_overflow !== ref_fp_overflow) ||
            (fp_underflow !== ref_fp_underflow) ||
            (fp_inexact !== ref_fp_inexact)) begin
            $error("unified FP mismatch test=%0d mode=%b expected_mant=%h got_mant=%h expected_result=%h got=%h",
                   test_id, test_mode, golden, fp_mantissa_product, ref_fp_result, result);
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

function [31:0] fp32_from_mantissa;
    input [23:0] mantissa;
    begin
        fp32_from_mantissa = {1'b0, 8'h7f, mantissa[22:0]};
    end
endfunction

function [23:0] unpack_fp32_mantissa;
    input [31:0] fp;
    begin
        if (fp[30:23] == 8'd0) begin
            unpack_fp32_mantissa = {1'b0, fp[22:0]};
        end else begin
            unpack_fp32_mantissa = {1'b1, fp[22:0]};
        end
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
    input [2:0] prune_min_group;
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

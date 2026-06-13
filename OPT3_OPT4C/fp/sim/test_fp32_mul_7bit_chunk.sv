module test_fp32_mul_7bit_chunk;

logic [31:0] operand_a;
logic [31:0] operand_b;
wire  [31:0] result;
wire         invalid;
wire         overflow;
wire         underflow;
wire         inexact;

integer test_id;

fp32_mul_7bit_chunk dut (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .result(result),
    .invalid(invalid),
    .overflow(overflow),
    .underflow(underflow),
    .inexact(inexact)
);

initial begin
    test_id = 0;

    check_exact(32'h3f800000, 32'h3f800000, 32'h3f800000); // 1.0 * 1.0
    check_exact(32'h3fc00000, 32'h40000000, 32'h40400000); // 1.5 * 2.0
    check_exact(32'hbfc00000, 32'h40000000, 32'hc0400000); // -1.5 * 2.0
    check_exact(32'h00000000, 32'h3f800000, 32'h00000000); // 0.0 * 1.0
    check_exact(32'h80000000, 32'h3f800000, 32'h80000000); // -0.0 * 1.0
    check_exact(32'h7f800000, 32'h40000000, 32'h7f800000); // inf * 2.0
    check_exact(32'hff800000, 32'h40000000, 32'hff800000); // -inf * 2.0
    check_nan_invalid(32'h7f800000, 32'h00000000);         // inf * 0.0
    check_nan(32'h7fc12345, 32'h3f800000);                 // qNaN * 1.0
    check_exact(32'h7f7fffff, 32'h40000000, 32'h7f800000); // overflow

    repeat (2000) begin
        check_shortreal(random_normal(), random_normal());
    end

    $display("\033[1;32mSUCCESS: fp32 7-bit chunk multiply tests passed.\033[0m");
    $finish;
end

task check_exact;
    input [31:0] a;
    input [31:0] b;
    input [31:0] expected;
    begin
        test_id = test_id + 1;
        operand_a = a;
        operand_b = b;
        #1;
        if (result !== expected) begin
            $error("exact mismatch test=%0d a=%h b=%h expected=%h got=%h flags invalid=%b overflow=%b underflow=%b inexact=%b",
                   test_id, a, b, expected, result, invalid, overflow, underflow, inexact);
            #1 $finish;
        end
    end
endtask

task check_nan;
    input [31:0] a;
    input [31:0] b;
    begin
        test_id = test_id + 1;
        operand_a = a;
        operand_b = b;
        #1;
        if (!(result[30:23] == 8'hff && result[22:0] != 23'd0)) begin
            $error("NaN mismatch test=%0d a=%h b=%h got=%h", test_id, a, b, result);
            #1 $finish;
        end
    end
endtask

task check_nan_invalid;
    input [31:0] a;
    input [31:0] b;
    begin
        check_nan(a, b);
        if (!invalid) begin
            $error("invalid flag not set for test=%0d a=%h b=%h", test_id, a, b);
            #1 $finish;
        end
    end
endtask

task check_shortreal;
    input [31:0] a;
    input [31:0] b;
    shortreal real_a;
    shortreal real_b;
    shortreal real_product;
    reg [31:0] expected;
    begin
        test_id = test_id + 1;
        operand_a = a;
        operand_b = b;
        real_a = $bitstoshortreal(a);
        real_b = $bitstoshortreal(b);
        real_product = real_a * real_b;
        expected = $shortrealtobits(real_product);
        #1;
        if (result !== expected) begin
            $error("shortreal mismatch test=%0d a=%h b=%h expected=%h got=%h flags invalid=%b overflow=%b underflow=%b inexact=%b",
                   test_id, a, b, expected, result, invalid, overflow, underflow, inexact);
            #1 $finish;
        end
    end
endtask

function [31:0] random_normal;
    reg        sign;
    reg [7:0]  exponent;
    reg [22:0] fraction;
    begin
        sign = $urandom_range(1, 0);
        exponent = $urandom_range(190, 60);
        fraction = $urandom() & 23'h7fffff;
        random_normal = {sign, exponent, fraction};
    end
endfunction

endmodule


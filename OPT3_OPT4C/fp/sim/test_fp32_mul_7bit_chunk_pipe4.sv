module test_fp32_mul_7bit_chunk_pipe4;

logic        clk;
logic        rst_n;
logic        valid_in;
logic [31:0] operand_a;
logic [31:0] operand_b;
wire         valid_out;
wire  [31:0] result;
wire         invalid;
wire         overflow;
wire         underflow;
wire         inexact;

wire [31:0] ref_result;
wire        ref_invalid;
wire        ref_overflow;
wire        ref_underflow;
wire        ref_inexact;

integer test_id;
integer wait_count;

fp32_mul_7bit_chunk_pipe4 dut (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .operand_a(operand_a),
    .operand_b(operand_b),
    .valid_out(valid_out),
    .result(result),
    .invalid(invalid),
    .overflow(overflow),
    .underflow(underflow),
    .inexact(inexact)
);

fp32_mul_7bit_chunk ref_dut (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .result(ref_result),
    .invalid(ref_invalid),
    .overflow(ref_overflow),
    .underflow(ref_underflow),
    .inexact(ref_inexact)
);

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

initial begin
    test_id = 0;
    rst_n = 1'b0;
    valid_in = 1'b0;
    operand_a = 32'd0;
    operand_b = 32'd0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    check_against_ref(32'h3f800000, 32'h3f800000);
    check_against_ref(32'h3fc00000, 32'h40000000);
    check_against_ref(32'hbfc00000, 32'h40000000);
    check_against_ref(32'h00000000, 32'h3f800000);
    check_against_ref(32'h80000000, 32'h3f800000);
    check_against_ref(32'h7f800000, 32'h40000000);
    check_against_ref(32'hff800000, 32'h40000000);
    check_against_ref(32'h7f800000, 32'h00000000);
    check_against_ref(32'h7fc12345, 32'h3f800000);
    check_against_ref(32'h7f7fffff, 32'h40000000);

    repeat (2000) begin
        check_against_ref(random_normal(), random_normal());
    end

    $display("\033[1;32mSUCCESS: fp32 7-bit chunk 4-stage pipelined multiply tests passed.\033[0m");
    $finish;
end

task check_against_ref;
    input [31:0] a;
    input [31:0] b;
    reg [31:0] expected_result;
    reg        expected_invalid;
    reg        expected_overflow;
    reg        expected_underflow;
    reg        expected_inexact;
    begin
        test_id = test_id + 1;

        @(negedge clk);
        operand_a = a;
        operand_b = b;
        valid_in = 1'b1;
        #1;
        expected_result = ref_result;
        expected_invalid = ref_invalid;
        expected_overflow = ref_overflow;
        expected_underflow = ref_underflow;
        expected_inexact = ref_inexact;

        @(negedge clk);
        valid_in = 1'b0;

        wait_count = 0;
        while (!valid_out && wait_count < 12) begin
            @(posedge clk);
            #1;
            wait_count = wait_count + 1;
        end

        if (!valid_out) begin
            $error("valid_out not set test=%0d a=%h b=%h", test_id, a, b);
            #1 $finish;
        end
        if (result !== expected_result ||
            invalid !== expected_invalid ||
            overflow !== expected_overflow ||
            underflow !== expected_underflow ||
            inexact !== expected_inexact) begin
            $error("pipe4 mismatch test=%0d a=%h b=%h expected=%h got=%h flags expected=%b%b%b%b got=%b%b%b%b",
                   test_id, a, b, expected_result, result,
                   expected_invalid, expected_overflow, expected_underflow, expected_inexact,
                   invalid, overflow, underflow, inexact);
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

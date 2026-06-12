module test_fp32_mantissa_7bit_chunk;

parameter clk_T = 2.0;

logic        clk;
logic        rst_n;
logic        start;
logic [23:0] mantissa_a;
logic [23:0] mantissa_b;
logic [47:0] product;
logic [31:0] a_chunks;
logic [31:0] b_chunks;
logic [15:0] pair_valid_mask;
logic [6:0]  group_valid_mask;
logic        busy;
logic        valid;
logic        done;
logic [7:0]  a_operand;
logic [7:0]  b_operand;
logic [1:0]  a_chunk_index;
logic [1:0]  b_chunk_index;
logic [2:0]  group_index;
logic [5:0]  shift_amount;
logic [15:0] sched_pair_valid_mask;
logic [6:0]  sched_group_valid_mask;

integer test_id;

fp32_mantissa_7bit_chunk_mul dut_comb (
    .mantissa_a(mantissa_a),
    .mantissa_b(mantissa_b),
    .product(product),
    .a_chunks(a_chunks),
    .b_chunks(b_chunks),
    .pair_valid_mask(pair_valid_mask),
    .group_valid_mask(group_valid_mask)
);

fp32_mantissa_7bit_pair_scheduler dut_sched (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .mantissa_a(mantissa_a),
    .mantissa_b(mantissa_b),
    .busy(busy),
    .valid(valid),
    .done(done),
    .a_operand(a_operand),
    .b_operand(b_operand),
    .a_chunk_index(a_chunk_index),
    .b_chunk_index(b_chunk_index),
    .group_index(group_index),
    .shift_amount(shift_amount),
    .pair_valid_mask(sched_pair_valid_mask),
    .group_valid_mask(sched_group_valid_mask)
);

initial begin
    clk = 1'b0;
    forever #(clk_T / 2) clk = ~clk;
end

initial begin
    rst_n = 1'b0;
    start = 1'b0;
    mantissa_a = 24'd0;
    mantissa_b = 24'd0;
    test_id = 0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    check_case(24'h800000, 24'h800000);
    check_case(24'hffffff, 24'hffffff);
    check_case(24'h800001, 24'hffffff);
    check_case(24'h812345, 24'h8abcde);
    check_case(24'h000000, 24'hffffff);
    check_case(24'h00007f, 24'h00007f);
    check_case(24'h00ff80, 24'h7f0081);

    repeat (1000) begin
        check_case($urandom() & 24'hffffff, $urandom() & 24'hffffff);
    end

    $display("\033[1;32mSUCCESS: fp32 mantissa 7-bit chunk tests passed.\033[0m");
    $finish;
end

task check_case;
    input [23:0] a;
    input [23:0] b;
    reg [47:0] golden;
    reg [63:0] sched_acc;
    reg [15:0] pair_product;
    integer cycles;
    begin
        test_id = test_id + 1;
        mantissa_a = a;
        mantissa_b = b;
        #1;

        golden = {24'd0, a} * {24'd0, b};
        if (product !== golden) begin
            $error("comb mismatch test=%0d a=%h b=%h expected=%h got=%h chunks_a=%h chunks_b=%h",
                   test_id, a, b, golden, product, a_chunks, b_chunks);
            #1 $finish;
        end

        sched_acc = 64'd0;
        cycles = 0;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        while (!done) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            if (valid) begin
                pair_product = a_operand * b_operand;
                sched_acc = sched_acc + ({48'd0, pair_product} << shift_amount);
            end
            if (cycles > 20) begin
                $error("scheduler timeout test=%0d a=%h b=%h", test_id, a, b);
                #1 $finish;
            end
        end

        if (sched_acc[47:0] !== golden) begin
            $error("scheduler mismatch test=%0d a=%h b=%h expected=%h got=%h pair_mask=%h group_mask=%h",
                   test_id, a, b, golden, sched_acc[47:0], sched_pair_valid_mask, sched_group_valid_mask);
            #1 $finish;
        end
    end
endtask

endmodule

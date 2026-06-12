module test_fp32_mantissa_7bit_opt4c;

parameter clk_T = 2.0;
parameter MAX_PAIRS = 16;

logic        clk;
logic        rst_n;

logic        start;
logic [23:0] mantissa_a;
logic [23:0] mantissa_b;
wire  [47:0] product;
wire  [31:0] a_chunks;
wire  [31:0] b_chunks;
wire  [15:0] pair_valid_mask;
wire  [6:0]  group_valid_mask;
wire         sched_busy;
wire         sched_valid;
wire         sched_done;
wire  [7:0]  sched_a_operand;
wire  [7:0]  sched_b_operand;
wire  [1:0]  sched_a_chunk_index;
wire  [1:0]  sched_b_chunk_index;
wire  [2:0]  sched_group_index;
wire  [5:0]  sched_shift_amount;
wire  [15:0] sched_pair_valid_mask;
wire  [6:0]  sched_group_valid_mask;

reg  signed [7:0] multiplicand;
reg               multiplicand_valid;
wire       [8:0] en_t_multiplicand;
wire             en_t_multiplicand_valid;
reg signed [1:0] vector_en_a [0:3][0:3];
reg        [3:0] signed_vector;

reg              compute_phase;
reg        [2:0] bw_count;
wire       [2:0] bw_count_control;
wire             result_valid;
reg signed [25:0] fuse_result;
reg signed [31:0] shift_result;
reg signed [31:0] tpe_chunk_c;
reg               clr;
wire              clr_ins;
reg        [7:0]  en_multiplicand;
reg        [3:0]  sign_en_multiplicand;
reg               encode_valid;
reg        [7:0]  operand_b;
reg        [7:0]  operand_b_ins;
wire       [1:0]  position;
wire       [2:0]  cal_cycle;
wire       [51:0] pe_result;

reg [7:0]  pair_a [0:MAX_PAIRS-1];
reg [7:0]  pair_b [0:MAX_PAIRS-1];
reg [5:0]  pair_shift [0:MAX_PAIRS-1];

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
    .busy(sched_busy),
    .valid(sched_valid),
    .done(sched_done),
    .a_operand(sched_a_operand),
    .b_operand(sched_b_operand),
    .a_chunk_index(sched_a_chunk_index),
    .b_chunk_index(sched_b_chunk_index),
    .group_index(sched_group_index),
    .shift_amount(sched_shift_amount),
    .pair_valid_mask(sched_pair_valid_mask),
    .group_valid_mask(sched_group_valid_mask)
);

encoder_multi_bit en_t_encoder (
    .clk(clk),
    .rst_n(rst_n),
    .multiplicand(multiplicand),
    .multiplicand_valid(multiplicand_valid),
    .en_multiplicand(en_t_multiplicand),
    .en_multiplicand_valid(en_t_multiplicand_valid)
);

get_pipeline_mulwidth #(
    .N(3),
    .WIDTH(1)
) pipeline_valid (
    .clk(clk),
    .rst_n(rst_n),
    .signal(clr),
    .pipeline_signal(clr_ins)
);

get_pipeline_mulwidth #(
    .N(4),
    .WIDTH(3)
) pipeline_bw_count (
    .clk(clk),
    .rst_n(rst_n),
    .signal(bw_count),
    .pipeline_signal(bw_count_control)
);

top_pe opt4c_pe (
    .clk(clk),
    .rst_n(rst_n),
    .clr(clr_ins),
    .en_multiplicand(en_multiplicand),
    .sign_en_multiplicand(sign_en_multiplicand),
    .encode_valid(encode_valid),
    .operand_b(operand_b_ins),
    .position(position),
    .cal_cycle(cal_cycle),
    .pe_result(pe_result)
);

initial begin
    clk = 1'b0;
    forever #(clk_T / 2) clk = ~clk;
end

initial begin
    initialize();

    check_case(24'h800000, 24'h800000);
    check_case(24'hffffff, 24'hffffff);
    check_case(24'h800001, 24'hffffff);
    check_case(24'h812345, 24'h8abcde);
    check_case(24'h000000, 24'hffffff);
    check_case(24'h00007f, 24'h00007f);
    check_case(24'h00ff80, 24'h7f0081);

    repeat (100) begin
        check_case($urandom() & 24'hffffff, $urandom() & 24'hffffff);
    end

    $display("\033[1;32mSUCCESS: fp32 mantissa 7-bit OPT4C integration tests passed.\033[0m");
    $finish;
end

task initialize;
    begin
        rst_n = 1'b0;
        start = 1'b0;
        mantissa_a = 24'd0;
        mantissa_b = 24'd0;
        multiplicand = 8'd0;
        multiplicand_valid = 1'b0;
        compute_phase = 1'b0;
        bw_count = 3'd0;
        tpe_chunk_c = 32'd0;
        clr = 1'b0;
        en_multiplicand = 8'd0;
        sign_en_multiplicand = 4'd0;
        encode_valid = 1'b0;
        operand_b = 8'd0;
        operand_b_ins = 8'd0;
        test_id = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
    end
endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        operand_b_ins <= 8'd0;
    end else begin
        operand_b_ins <= operand_b;
    end
end

assign result_valid = (~clr_ins) & compute_phase;

always @(*) begin
    fuse_result = 26'd0;
    shift_result = 32'd0;
    if (result_valid) begin
        fuse_result = $signed(pe_result[25:0]) + $signed(pe_result[51:26]);
        shift_result = $signed(fuse_result << {bw_count_control, 1'b0});
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tpe_chunk_c <= 32'd0;
    end else if (result_valid) begin
        tpe_chunk_c <= tpe_chunk_c + shift_result;
    end
end

task check_case;
    input [23:0] a;
    input [23:0] b;
    reg [47:0] golden;
    reg [63:0] opt4c_acc;
    reg [31:0] chunk_product;
    integer pair_count;
    integer pair_id;
    begin
        test_id = test_id + 1;
        mantissa_a = a;
        mantissa_b = b;
        #1;

        golden = {24'd0, a} * {24'd0, b};
        if (product !== golden) begin
            $error("comb mismatch test=%0d a=%h b=%h expected=%h got=%h",
                   test_id, a, b, golden, product);
            #1 $finish;
        end

        collect_scheduler_pairs(pair_count);

        opt4c_acc = 64'd0;
        for (pair_id = 0; pair_id < pair_count; pair_id = pair_id + 1) begin
            run_opt4c_product(pair_a[pair_id], pair_b[pair_id], chunk_product);
            opt4c_acc = opt4c_acc + ({32'd0, chunk_product} << pair_shift[pair_id]);
        end

        if (opt4c_acc[47:0] !== golden) begin
            $error("opt4c mismatch test=%0d a=%h b=%h expected=%h got=%h pair_count=%0d pair_mask=%h group_mask=%h",
                   test_id, a, b, golden, opt4c_acc[47:0], pair_count,
                   sched_pair_valid_mask, sched_group_valid_mask);
            #1 $finish;
        end
    end
endtask

task collect_scheduler_pairs;
    output integer pair_count;
    integer cycles;
    begin
        pair_count = 0;
        cycles = 0;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        while (!sched_done) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            if (sched_valid) begin
                if (pair_count >= MAX_PAIRS) begin
                    $error("too many scheduler pairs");
                    #1 $finish;
                end
                pair_a[pair_count] = sched_a_operand;
                pair_b[pair_count] = sched_b_operand;
                pair_shift[pair_count] = sched_shift_amount;
                pair_count = pair_count + 1;
            end
            if (cycles > 20) begin
                $error("scheduler timeout test=%0d a=%h b=%h", test_id, mantissa_a, mantissa_b);
                #1 $finish;
            end
        end
    end
endtask

task encode_single_a;
    input [7:0] a_value;
    integer wait_count;
    integer lane;
    begin
        for (lane = 0; lane < 4; lane = lane + 1) begin
            vector_en_a[lane][0] = 2'd0;
            vector_en_a[lane][1] = 2'd0;
            vector_en_a[lane][2] = 2'd0;
            vector_en_a[lane][3] = 2'd0;
            signed_vector[lane] = 1'b0;
        end

        @(negedge clk);
        multiplicand = a_value;
        multiplicand_valid = 1'b1;
        @(negedge clk);
        multiplicand = 8'd0;
        multiplicand_valid = 1'b0;

        wait_count = 0;
        while (!en_t_multiplicand_valid) begin
            @(posedge clk);
            #1;
            wait_count = wait_count + 1;
            if (wait_count > 10) begin
                $error("encoder timeout a=%0d", a_value);
                #1 $finish;
            end
        end

        vector_en_a[0][0] = en_t_multiplicand[1:0];
        vector_en_a[0][1] = en_t_multiplicand[3:2];
        vector_en_a[0][2] = en_t_multiplicand[5:4];
        vector_en_a[0][3] = en_t_multiplicand[7:6];
        signed_vector[0] = en_t_multiplicand[8];
    end
endtask

task run_opt4c_product;
    input  [7:0] a_value;
    input  [7:0] b_value;
    output [31:0] result;
    integer bw;
    integer cycle;
    integer wait_count;
    reg signed [2:0] cal_count;
    begin
        result = 32'd0;
        tpe_chunk_c = 32'd0;
        clr = 1'b0;
        encode_valid = 1'b0;
        en_multiplicand = 8'd0;
        sign_en_multiplicand = 4'd0;
        operand_b = 8'd0;
        bw_count = 3'd0;
        compute_phase = 1'b0;

        repeat (2) @(posedge clk);
        encode_single_a(a_value);

        compute_phase = 1'b1;
        for (bw = 0; bw < 4; bw = bw + 1) begin
            bw_count = bw[2:0];
            en_multiplicand = {6'd0, vector_en_a[0][bw]};
            sign_en_multiplicand = {3'd0, signed_vector[0]};

            for (cycle = 1; cycle <= 4; cycle = cycle + 1) begin
                @(negedge clk);
                clr = 1'b1;
                encode_valid = (cycle == 1);

                @(posedge clk);
                #1;
                if (cal_cycle == 0) begin
                    operand_b = 8'd0;
                end else begin
                    operand_b = (position == 2'd0) ? b_value : 8'd0;
                end

                cal_count = cal_cycle - cycle;
                if (cal_count < 1) begin
                    cycle = 5;
                end
            end

            @(negedge clk);
            encode_valid = 1'b0;
            clr = 1'b0;
            operand_b = 8'd0;
        end

        wait_count = 0;
        repeat (6) begin
            @(posedge clk);
            wait_count = wait_count + 1;
        end

        compute_phase = 1'b0;
        result = tpe_chunk_c;

        if (result !== ({24'd0, a_value} * {24'd0, b_value})) begin
            $error("chunk product mismatch a=%0d b=%0d expected=%0d got=%0d",
                   a_value, b_value, ({24'd0, a_value} * {24'd0, b_value}), result);
            #1 $finish;
        end
    end
endtask

endmodule


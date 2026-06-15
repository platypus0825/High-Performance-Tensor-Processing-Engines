module test_opt4c_int_fp_mode_wrapper_pipepe_fp;

parameter clk_T = 2.0;

logic        clk;
logic        rst_n;
logic        mode_fp;
logic        fp_start;
logic [23:0] fp_mantissa_a;
logic [23:0] fp_mantissa_b;
logic [2:0]  fp_min_group;
wire         fp_busy;
wire         fp_done;
wire         fp_result_valid;
wire  [47:0] fp_mantissa_product;
wire  [15:0] fp_pair_valid_mask;
wire  [6:0]  fp_group_valid_mask;

integer test_id;
integer trace_cycle;

opt4c_int_fp_mode_wrapper_pipepe_cfg dut (
    .clk(clk),
    .rst_n(rst_n),
    .mode_fp(mode_fp),
    .int_clr(1'b0),
    .int_en_multiplicand(8'd0),
    .int_sign_en_multiplicand(4'd0),
    .int_encode_valid(1'b0),
    .int_operand_b(8'd0),
    .int_position(),
    .int_cal_cycle(),
    .int_pe_result(),
    .fp_start(fp_start),
    .fp_mantissa_a(fp_mantissa_a),
    .fp_mantissa_b(fp_mantissa_b),
    .fp_min_group(fp_min_group),
    .fp_busy(fp_busy),
    .fp_done(fp_done),
    .fp_result_valid(fp_result_valid),
    .fp_mantissa_product(fp_mantissa_product),
    .fp_pair_valid_mask(fp_pair_valid_mask),
    .fp_group_valid_mask(fp_group_valid_mask)
);

initial begin
    clk = 1'b0;
    forever #(clk_T / 2) clk = ~clk;
end

always @(posedge clk) begin
    if (!rst_n) begin
        trace_cycle <= 0;
    end else if ($test$plusargs("TRACE_PIPEPE_FP") && (test_id <= 1) && (fp_busy || fp_done)) begin
        trace_cycle <= trace_cycle + 1;
        $display("[PIPEPE_FP_TRACE] t=%0t cyc=%0d test=%0d state=%0d pair=%0d/%0d bw=%0d bwcy=%0d drain=%0d a=%h b=%h shift=%0d enc=%h",
                 $time, trace_cycle, test_id,
                 dut.wrapper.state,
                 dut.wrapper.pair_index,
                 dut.wrapper.pair_total,
                 dut.wrapper.bw_index,
                 dut.wrapper.bw_cycle,
                 dut.wrapper.drain_count,
                 dut.wrapper.current_a,
                 dut.wrapper.current_b,
                 dut.wrapper.current_shift,
                 dut.wrapper.encoded_a);
        $display("[PIPEPE_FP_TRACE]   ctrl fp_clr=%b clr_to_pe=%b pe_clr_issue=%b enc_valid=%b enc_issue=%b cap_tok=%b cap_tok_d=%b cap=%b shift_bw=%0d",
                 dut.wrapper.fp_clr,
                 dut.wrapper.fp_clr_to_pe,
                 dut.wrapper.pe_clr_issue,
                 dut.wrapper.fp_encode_valid,
                 dut.wrapper.pe_encode_valid_issue,
                 dut.wrapper.fp_capture_token,
                 dut.wrapper.fp_capture_token_delayed,
                 dut.wrapper.fp_capture_result,
                 dut.wrapper.fp_shift_bw_count);
        $display("[PIPEPE_FP_TRACE]   pe pos=%0d cal=%0d b_pre=%h b_to_pe=%h b_issue=%h pe_b=%h enc_pos=%0d clr_s1=%b mux_s1=%0d result=%h fuse=%0d shift_res=%0d chunk_acc=%0d prod_acc=%h",
                 dut.wrapper.pe_position,
                 dut.wrapper.pe_cal_cycle,
                 dut.wrapper.fp_operand_b_pre,
                 dut.wrapper.fp_operand_b_to_pe,
                 dut.wrapper.pe_operand_b_issue,
                 dut.wrapper.shared_top_pe.sparse_pe.operand_b,
                 dut.wrapper.shared_top_pe.sparse_pe.encoder_position,
                 dut.wrapper.shared_top_pe.sparse_pe.clr_s1,
                 dut.wrapper.shared_top_pe.sparse_pe.mux_extend_b_s1,
                 dut.wrapper.pe_result,
                 dut.wrapper.fp_fuse_result,
                 dut.wrapper.fp_shift_result,
                 dut.wrapper.fp_chunk_acc,
                 dut.wrapper.fp_product_acc);
    end
end

initial begin
    initialize();

    check_fp_case(24'h800000, 24'h800000, 3'd0);
    check_fp_case(24'hffffff, 24'hffffff, 3'd0);
    check_fp_case(24'hffffff, 24'hffffff, 3'd1);
    check_fp_case(24'hffffff, 24'hffffff, 3'd2);
    check_fp_case(24'hffffff, 24'hffffff, 3'd3);
    check_fp_case(24'h812345, 24'h8abcde, 3'd4);
    check_fp_case(24'h000000, 24'hffffff, 3'd0);
    check_fp_case(24'h00007f, 24'h00007f, 3'd0);

    repeat (40) begin
        check_fp_case($urandom() & 24'hffffff, $urandom() & 24'hffffff, ($urandom() % 5));
    end

    $display("\033[1;32mSUCCESS: shared-PE pipePE FP mantissa tests passed.\033[0m");
    $finish;
end

task initialize;
    begin
        rst_n = 1'b0;
        mode_fp = 1'b1;
        fp_start = 1'b0;
        fp_mantissa_a = 24'd0;
        fp_mantissa_b = 24'd0;
        fp_min_group = 3'd0;
        test_id = 0;
        trace_cycle = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
    end
endtask

task check_fp_case;
    input [23:0] a;
    input [23:0] b;
    input [2:0]  min_group;
    reg [47:0] golden;
    integer cycles;
    begin
        test_id = test_id + 1;
        golden = pruned_product(a, b, min_group);

        @(negedge clk);
        fp_mantissa_a = a;
        fp_mantissa_b = b;
        fp_min_group = min_group;
        fp_start = 1'b1;
        @(negedge clk);
        fp_start = 1'b0;

        cycles = 0;
        while (!fp_done) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            if (cycles > 1400) begin
                $error("pipePE FP wrapper timeout test=%0d a=%h b=%h min_group=%0d",
                       test_id, a, b, min_group);
                #1 $finish;
            end
        end

        if (!fp_result_valid) begin
            $error("pipePE FP wrapper done without result_valid test=%0d", test_id);
            #1 $finish;
        end

        if (fp_mantissa_product !== golden) begin
            $error("pipePE FP wrapper mismatch test=%0d a=%h b=%h min_group=%0d expected=%h got=%h pair_mask=%h group_mask=%h cycles=%0d",
                   test_id, a, b, min_group, golden, fp_mantissa_product,
                   fp_pair_valid_mask, fp_group_valid_mask, cycles);
            #1 $finish;
        end

        repeat (6) @(posedge clk);
    end
endtask

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

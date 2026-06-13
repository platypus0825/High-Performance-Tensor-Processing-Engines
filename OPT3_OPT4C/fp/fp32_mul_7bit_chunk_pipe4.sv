module fp32_mul_7bit_chunk_pipe4 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    output logic        valid_out,
    output logic [31:0] result,
    output logic        invalid,
    output logic        overflow,
    output logic        underflow,
    output logic        inexact
);

logic        sign_result_s0;
logic [7:0]  exp_a_s0;
logic [7:0]  exp_b_s0;
logic [22:0] frac_a_s0;
logic [22:0] frac_b_s0;
logic [7:0]  a_chunk_s0 [0:3];
logic [7:0]  b_chunk_s0 [0:3];
logic [15:0] pair_product_s0 [0:15];

logic        a_is_zero_s0;
logic        b_is_zero_s0;
logic        a_is_inf_s0;
logic        b_is_inf_s0;
logic        a_is_nan_s0;
logic        b_is_nan_s0;
logic signed [31:0] exp_a_unbiased_s0;
logic signed [31:0] exp_b_unbiased_s0;

logic        valid_s1;
logic        sign_result_s1;
logic        a_is_zero_s1;
logic        b_is_zero_s1;
logic        a_is_inf_s1;
logic        b_is_inf_s1;
logic        a_is_nan_s1;
logic        b_is_nan_s1;
logic signed [31:0] exp_a_unbiased_s1;
logic signed [31:0] exp_b_unbiased_s1;
logic [15:0] pair_product_s1 [0:15];

logic [55:0] product_acc_s2_next;
logic        valid_s2;
logic        sign_result_s2;
logic        a_is_zero_s2;
logic        b_is_zero_s2;
logic        a_is_inf_s2;
logic        b_is_inf_s2;
logic        a_is_nan_s2;
logic        b_is_nan_s2;
logic signed [31:0] exp_a_unbiased_s2;
logic signed [31:0] exp_b_unbiased_s2;
logic [47:0] mantissa_product_s2;

logic        direct_path_s3_next;
logic [31:0] direct_result_s3_next;
logic        invalid_s3_next;
logic        overflow_s3_next;
logic        underflow_s3_next;
logic        inexact_s3_next;
logic signed [31:0] biased_exp_s3_next;
logic [23:0] mantissa_rounded_s3_next;
logic        round_up_s3_next;
logic        sub_direct_path_s3_next;
logic [31:0] sub_direct_result_s3_next;
logic [22:0] sub_frac_s3_next;
logic        sub_round_up_s3_next;
logic        sub_inexact_s3_next;

logic        valid_s3;
logic        sign_result_s3;
logic        direct_path_s3;
logic [31:0] direct_result_s3;
logic        invalid_s3;
logic        overflow_s3;
logic        underflow_s3;
logic        inexact_s3;
logic signed [31:0] biased_exp_s3;
logic [23:0] mantissa_rounded_s3;
logic        round_up_s3;
logic        sub_direct_path_s3;
logic [31:0] sub_direct_result_s3;
logic [22:0] sub_frac_s3;
logic        sub_round_up_s3;
logic        sub_inexact_s3;

integer idx;
integer lead_index;
integer product_exp;
integer shift_right;
integer sub_target;
integer sub_shift;
integer k;

logic [47:0] shifted_product;
logic        guard_bit;
logic        sticky_bit;
logic [63:0] sub_direct;
logic [23:0] sub_mantissa;
logic        sub_guard;
logic        sub_sticky;
logic [24:0] mantissa_round_ext;
logic [24:0] sub_ext;
logic [23:0] mantissa_rounded_final;
logic signed [31:0] biased_exp_final;
logic [7:0]  biased_exp_final_u;

always_comb begin
    sign_result_s0 = operand_a[31] ^ operand_b[31];
    exp_a_s0 = operand_a[30:23];
    exp_b_s0 = operand_b[30:23];
    frac_a_s0 = operand_a[22:0];
    frac_b_s0 = operand_b[22:0];

    a_chunk_s0[0] = {1'b0, frac_a_s0[6:0]};
    a_chunk_s0[1] = {1'b0, frac_a_s0[13:7]};
    a_chunk_s0[2] = {1'b0, frac_a_s0[20:14]};
    a_chunk_s0[3] = (exp_a_s0 == 8'd0) ? {5'd0, frac_a_s0[22:21]} : {4'd1, frac_a_s0[22:21]};

    b_chunk_s0[0] = {1'b0, frac_b_s0[6:0]};
    b_chunk_s0[1] = {1'b0, frac_b_s0[13:7]};
    b_chunk_s0[2] = {1'b0, frac_b_s0[20:14]};
    b_chunk_s0[3] = (exp_b_s0 == 8'd0) ? {5'd0, frac_b_s0[22:21]} : {4'd1, frac_b_s0[22:21]};

    pair_product_s0[0]  = a_chunk_s0[0] * b_chunk_s0[0];
    pair_product_s0[1]  = a_chunk_s0[0] * b_chunk_s0[1];
    pair_product_s0[2]  = a_chunk_s0[0] * b_chunk_s0[2];
    pair_product_s0[3]  = a_chunk_s0[0] * b_chunk_s0[3];
    pair_product_s0[4]  = a_chunk_s0[1] * b_chunk_s0[0];
    pair_product_s0[5]  = a_chunk_s0[1] * b_chunk_s0[1];
    pair_product_s0[6]  = a_chunk_s0[1] * b_chunk_s0[2];
    pair_product_s0[7]  = a_chunk_s0[1] * b_chunk_s0[3];
    pair_product_s0[8]  = a_chunk_s0[2] * b_chunk_s0[0];
    pair_product_s0[9]  = a_chunk_s0[2] * b_chunk_s0[1];
    pair_product_s0[10] = a_chunk_s0[2] * b_chunk_s0[2];
    pair_product_s0[11] = a_chunk_s0[2] * b_chunk_s0[3];
    pair_product_s0[12] = a_chunk_s0[3] * b_chunk_s0[0];
    pair_product_s0[13] = a_chunk_s0[3] * b_chunk_s0[1];
    pair_product_s0[14] = a_chunk_s0[3] * b_chunk_s0[2];
    pair_product_s0[15] = a_chunk_s0[3] * b_chunk_s0[3];

    a_is_zero_s0 = (exp_a_s0 == 8'd0) && (frac_a_s0 == 23'd0);
    b_is_zero_s0 = (exp_b_s0 == 8'd0) && (frac_b_s0 == 23'd0);
    a_is_inf_s0 = (exp_a_s0 == 8'hff) && (frac_a_s0 == 23'd0);
    b_is_inf_s0 = (exp_b_s0 == 8'hff) && (frac_b_s0 == 23'd0);
    a_is_nan_s0 = (exp_a_s0 == 8'hff) && (frac_a_s0 != 23'd0);
    b_is_nan_s0 = (exp_b_s0 == 8'hff) && (frac_b_s0 != 23'd0);

    exp_a_unbiased_s0 = (exp_a_s0 == 8'd0) ? -32'sd126 : ($signed({24'd0, exp_a_s0}) - 32'sd127);
    exp_b_unbiased_s0 = (exp_b_s0 == 8'd0) ? -32'sd126 : ($signed({24'd0, exp_b_s0}) - 32'sd127);
end

always_comb begin
    product_acc_s2_next =
        ({40'd0, pair_product_s1[0]}  << 0)  +
        ({40'd0, pair_product_s1[1]}  << 7)  +
        ({40'd0, pair_product_s1[2]}  << 14) +
        ({40'd0, pair_product_s1[3]}  << 21) +
        ({40'd0, pair_product_s1[4]}  << 7)  +
        ({40'd0, pair_product_s1[5]}  << 14) +
        ({40'd0, pair_product_s1[6]}  << 21) +
        ({40'd0, pair_product_s1[7]}  << 28) +
        ({40'd0, pair_product_s1[8]}  << 14) +
        ({40'd0, pair_product_s1[9]}  << 21) +
        ({40'd0, pair_product_s1[10]} << 28) +
        ({40'd0, pair_product_s1[11]} << 35) +
        ({40'd0, pair_product_s1[12]} << 21) +
        ({40'd0, pair_product_s1[13]} << 28) +
        ({40'd0, pair_product_s1[14]} << 35) +
        ({40'd0, pair_product_s1[15]} << 42);
end

always_comb begin
    direct_path_s3_next = 1'b0;
    direct_result_s3_next = 32'd0;
    invalid_s3_next = 1'b0;
    overflow_s3_next = 1'b0;
    underflow_s3_next = 1'b0;
    inexact_s3_next = 1'b0;
    biased_exp_s3_next = 32'sd0;
    mantissa_rounded_s3_next = 24'd0;
    round_up_s3_next = 1'b0;
    sub_direct_path_s3_next = 1'b0;
    sub_direct_result_s3_next = 32'd0;
    sub_frac_s3_next = 23'd0;
    sub_round_up_s3_next = 1'b0;
    sub_inexact_s3_next = 1'b0;

    lead_index = 0;
    product_exp = 0;
    shift_right = 0;
    sub_target = 0;
    sub_shift = 0;
    shifted_product = 48'd0;
    guard_bit = 1'b0;
    sticky_bit = 1'b0;
    sub_direct = 64'd0;
    sub_mantissa = 24'd0;
    sub_guard = 1'b0;
    sub_sticky = 1'b0;

    if (a_is_nan_s2 || b_is_nan_s2 || ((a_is_inf_s2 || b_is_inf_s2) && (a_is_zero_s2 || b_is_zero_s2))) begin
        direct_path_s3_next = 1'b1;
        invalid_s3_next = ((a_is_inf_s2 || b_is_inf_s2) && (a_is_zero_s2 || b_is_zero_s2));
        direct_result_s3_next = 32'h7fc00000;
    end else if (a_is_inf_s2 || b_is_inf_s2) begin
        direct_path_s3_next = 1'b1;
        direct_result_s3_next = {sign_result_s2, 8'hff, 23'd0};
    end else if (a_is_zero_s2 || b_is_zero_s2 || (mantissa_product_s2 == 48'd0)) begin
        direct_path_s3_next = 1'b1;
        direct_result_s3_next = {sign_result_s2, 31'd0};
    end else begin
        for (k = 0; k < 48; k = k + 1) begin
            if (mantissa_product_s2[k]) begin
                lead_index = k;
            end
        end

        product_exp = exp_a_unbiased_s2 + exp_b_unbiased_s2 - 46 + lead_index;
        biased_exp_s3_next = product_exp + 127;

        if (lead_index >= 23) begin
            shift_right = lead_index - 23;
            shifted_product = mantissa_product_s2 >> shift_right;
            mantissa_rounded_s3_next = shifted_product[23:0];

            if (shift_right > 0) begin
                for (k = 0; k < 48; k = k + 1) begin
                    if (k == (shift_right - 1)) begin
                        guard_bit = mantissa_product_s2[k];
                    end
                    if (k < (shift_right - 1)) begin
                        sticky_bit = sticky_bit | mantissa_product_s2[k];
                    end
                end
                round_up_s3_next = guard_bit & (sticky_bit | mantissa_rounded_s3_next[0]);
                inexact_s3_next = guard_bit | sticky_bit;
            end
        end else begin
            mantissa_rounded_s3_next = mantissa_product_s2 << (23 - lead_index);
        end

        sub_target = exp_a_unbiased_s2 + exp_b_unbiased_s2 + 103;
        if (sub_target >= 0) begin
            sub_direct_path_s3_next = 1'b1;
            sub_direct = {16'd0, mantissa_product_s2} << sub_target;
            if (sub_direct[23]) begin
                sub_direct_result_s3_next = {sign_result_s2, 8'd1, 23'd0};
            end else begin
                sub_direct_result_s3_next = {sign_result_s2, 8'd0, sub_direct[22:0]};
            end
        end else begin
            sub_shift = -sub_target;

            if (sub_shift >= 49) begin
                sub_frac_s3_next = 23'd0;
                sub_guard = 1'b0;
                sub_sticky = |mantissa_product_s2;
            end else begin
                sub_mantissa = mantissa_product_s2 >> sub_shift;
                sub_frac_s3_next = sub_mantissa[22:0];
                for (k = 0; k < 48; k = k + 1) begin
                    if (k == (sub_shift - 1)) begin
                        sub_guard = mantissa_product_s2[k];
                    end
                    if (k < (sub_shift - 1)) begin
                        sub_sticky = sub_sticky | mantissa_product_s2[k];
                    end
                end
            end

            sub_round_up_s3_next = sub_guard & (sub_sticky | sub_frac_s3_next[0]);
            sub_inexact_s3_next = sub_guard | sub_sticky;
        end
    end
end

always_comb begin
    mantissa_round_ext = {1'b0, mantissa_rounded_s3} + {24'd0, round_up_s3};
    mantissa_rounded_final = mantissa_round_ext[24] ? mantissa_round_ext[24:1] : mantissa_round_ext[23:0];
    biased_exp_final = biased_exp_s3 + (mantissa_round_ext[24] ? 32'sd1 : 32'sd0);
    biased_exp_final_u = biased_exp_final;

    sub_ext = {2'd0, sub_frac_s3} + {24'd0, sub_round_up_s3};
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_s1 <= 1'b0;
        sign_result_s1 <= 1'b0;
        a_is_zero_s1 <= 1'b0;
        b_is_zero_s1 <= 1'b0;
        a_is_inf_s1 <= 1'b0;
        b_is_inf_s1 <= 1'b0;
        a_is_nan_s1 <= 1'b0;
        b_is_nan_s1 <= 1'b0;
        exp_a_unbiased_s1 <= 32'sd0;
        exp_b_unbiased_s1 <= 32'sd0;

        valid_s2 <= 1'b0;
        sign_result_s2 <= 1'b0;
        a_is_zero_s2 <= 1'b0;
        b_is_zero_s2 <= 1'b0;
        a_is_inf_s2 <= 1'b0;
        b_is_inf_s2 <= 1'b0;
        a_is_nan_s2 <= 1'b0;
        b_is_nan_s2 <= 1'b0;
        exp_a_unbiased_s2 <= 32'sd0;
        exp_b_unbiased_s2 <= 32'sd0;
        mantissa_product_s2 <= 48'd0;

        valid_s3 <= 1'b0;
        sign_result_s3 <= 1'b0;
        direct_path_s3 <= 1'b0;
        direct_result_s3 <= 32'd0;
        invalid_s3 <= 1'b0;
        overflow_s3 <= 1'b0;
        underflow_s3 <= 1'b0;
        inexact_s3 <= 1'b0;
        biased_exp_s3 <= 32'sd0;
        mantissa_rounded_s3 <= 24'd0;
        round_up_s3 <= 1'b0;
        sub_direct_path_s3 <= 1'b0;
        sub_direct_result_s3 <= 32'd0;
        sub_frac_s3 <= 23'd0;
        sub_round_up_s3 <= 1'b0;
        sub_inexact_s3 <= 1'b0;

        valid_out <= 1'b0;
        result <= 32'd0;
        invalid <= 1'b0;
        overflow <= 1'b0;
        underflow <= 1'b0;
        inexact <= 1'b0;

        for (idx = 0; idx < 16; idx = idx + 1) begin
            pair_product_s1[idx] <= 16'd0;
        end
    end else begin
        valid_s1 <= valid_in;
        sign_result_s1 <= sign_result_s0;
        a_is_zero_s1 <= a_is_zero_s0;
        b_is_zero_s1 <= b_is_zero_s0;
        a_is_inf_s1 <= a_is_inf_s0;
        b_is_inf_s1 <= b_is_inf_s0;
        a_is_nan_s1 <= a_is_nan_s0;
        b_is_nan_s1 <= b_is_nan_s0;
        exp_a_unbiased_s1 <= exp_a_unbiased_s0;
        exp_b_unbiased_s1 <= exp_b_unbiased_s0;
        for (idx = 0; idx < 16; idx = idx + 1) begin
            pair_product_s1[idx] <= pair_product_s0[idx];
        end

        valid_s2 <= valid_s1;
        sign_result_s2 <= sign_result_s1;
        a_is_zero_s2 <= a_is_zero_s1;
        b_is_zero_s2 <= b_is_zero_s1;
        a_is_inf_s2 <= a_is_inf_s1;
        b_is_inf_s2 <= b_is_inf_s1;
        a_is_nan_s2 <= a_is_nan_s1;
        b_is_nan_s2 <= b_is_nan_s1;
        exp_a_unbiased_s2 <= exp_a_unbiased_s1;
        exp_b_unbiased_s2 <= exp_b_unbiased_s1;
        mantissa_product_s2 <= product_acc_s2_next[47:0];

        valid_s3 <= valid_s2;
        sign_result_s3 <= sign_result_s2;
        direct_path_s3 <= direct_path_s3_next;
        direct_result_s3 <= direct_result_s3_next;
        invalid_s3 <= invalid_s3_next;
        overflow_s3 <= overflow_s3_next;
        underflow_s3 <= underflow_s3_next;
        inexact_s3 <= inexact_s3_next;
        biased_exp_s3 <= biased_exp_s3_next;
        mantissa_rounded_s3 <= mantissa_rounded_s3_next;
        round_up_s3 <= round_up_s3_next;
        sub_direct_path_s3 <= sub_direct_path_s3_next;
        sub_direct_result_s3 <= sub_direct_result_s3_next;
        sub_frac_s3 <= sub_frac_s3_next;
        sub_round_up_s3 <= sub_round_up_s3_next;
        sub_inexact_s3 <= sub_inexact_s3_next;

        valid_out <= valid_s3;
        if (direct_path_s3) begin
            result <= direct_result_s3;
            invalid <= invalid_s3;
            overflow <= overflow_s3;
            underflow <= underflow_s3;
            inexact <= inexact_s3;
        end else if (biased_exp_final >= 255) begin
            result <= {sign_result_s3, 8'hff, 23'd0};
            invalid <= 1'b0;
            overflow <= 1'b1;
            underflow <= 1'b0;
            inexact <= 1'b1;
        end else if (biased_exp_final > 0) begin
            result <= {sign_result_s3, biased_exp_final_u, mantissa_rounded_final[22:0]};
            invalid <= 1'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
            inexact <= inexact_s3;
        end else begin
            invalid <= 1'b0;
            overflow <= 1'b0;
            underflow <= 1'b1;
            if (sub_direct_path_s3) begin
                result <= sub_direct_result_s3;
                inexact <= inexact_s3;
            end else if (sub_ext[23]) begin
                result <= {sign_result_s3, 8'd1, 23'd0};
                inexact <= sub_inexact_s3;
            end else begin
                result <= {sign_result_s3, 8'd0, sub_ext[22:0]};
                inexact <= sub_inexact_s3;
            end
        end
    end
end

endmodule

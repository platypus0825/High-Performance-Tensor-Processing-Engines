module fp32_mul_7bit_chunk_pipe (
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

logic        sign_a;
logic        sign_b;
logic        sign_result_s0;
logic [7:0]  exp_a;
logic [7:0]  exp_b;
logic [22:0] frac_a;
logic [22:0] frac_b;
logic [23:0] mantissa_a;
logic [23:0] mantissa_b;
logic [47:0] mantissa_product_s0;
logic [31:0] unused_a_chunks;
logic [31:0] unused_b_chunks;
logic [15:0] unused_pair_valid_mask;
logic [6:0]  unused_group_valid_mask;

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
logic [47:0] mantissa_product_s1;

integer lead_index;
integer product_exp;
integer biased_exp;
integer shift_right;
integer sub_shift;
integer sub_target;
integer k;

logic [31:0] result_next;
logic        invalid_next;
logic        overflow_next;
logic        underflow_next;
logic        inexact_next;
logic [23:0] mantissa_rounded;
logic [24:0] mantissa_round_ext;
logic [47:0] shifted_product;
logic        guard_bit;
logic        sticky_bit;
logic        round_up;
logic [24:0] sub_ext;
logic [63:0] sub_direct;
logic [23:0] sub_mantissa;
logic [22:0] sub_frac;
logic        sub_guard;
logic        sub_sticky;
logic        sub_round_up;
logic [7:0]  result_exp;

fp32_mantissa_7bit_chunk_mul mantissa_mul (
    .mantissa_a(mantissa_a),
    .mantissa_b(mantissa_b),
    .product(mantissa_product_s0),
    .a_chunks(unused_a_chunks),
    .b_chunks(unused_b_chunks),
    .pair_valid_mask(unused_pair_valid_mask),
    .group_valid_mask(unused_group_valid_mask)
);

always_comb begin
    sign_a = operand_a[31];
    sign_b = operand_b[31];
    sign_result_s0 = sign_a ^ sign_b;
    exp_a = operand_a[30:23];
    exp_b = operand_b[30:23];
    frac_a = operand_a[22:0];
    frac_b = operand_b[22:0];

    a_is_zero_s0 = (exp_a == 8'd0) && (frac_a == 23'd0);
    b_is_zero_s0 = (exp_b == 8'd0) && (frac_b == 23'd0);
    a_is_inf_s0 = (exp_a == 8'hff) && (frac_a == 23'd0);
    b_is_inf_s0 = (exp_b == 8'hff) && (frac_b == 23'd0);
    a_is_nan_s0 = (exp_a == 8'hff) && (frac_a != 23'd0);
    b_is_nan_s0 = (exp_b == 8'hff) && (frac_b != 23'd0);

    mantissa_a = (exp_a == 8'd0) ? {1'b0, frac_a} : {1'b1, frac_a};
    mantissa_b = (exp_b == 8'd0) ? {1'b0, frac_b} : {1'b1, frac_b};

    if (exp_a == 8'd0) begin
        exp_a_unbiased_s0 = -32'sd126;
    end else begin
        exp_a_unbiased_s0 = $signed({24'd0, exp_a}) - 32'sd127;
    end

    if (exp_b == 8'd0) begin
        exp_b_unbiased_s0 = -32'sd126;
    end else begin
        exp_b_unbiased_s0 = $signed({24'd0, exp_b}) - 32'sd127;
    end
end

always_comb begin
    invalid_next = 1'b0;
    overflow_next = 1'b0;
    underflow_next = 1'b0;
    inexact_next = 1'b0;
    result_next = 32'd0;

    lead_index = 0;
    product_exp = 0;
    biased_exp = 0;
    shift_right = 0;
    sub_shift = 0;
    sub_target = 0;
    shifted_product = 48'd0;
    mantissa_rounded = 24'd0;
    mantissa_round_ext = 25'd0;
    guard_bit = 1'b0;
    sticky_bit = 1'b0;
    round_up = 1'b0;
    sub_ext = 25'd0;
    sub_direct = 64'd0;
    sub_mantissa = 24'd0;
    sub_frac = 23'd0;
    sub_guard = 1'b0;
    sub_sticky = 1'b0;
    sub_round_up = 1'b0;
    result_exp = 8'd0;

    if (a_is_nan_s1 || b_is_nan_s1 || ((a_is_inf_s1 || b_is_inf_s1) && (a_is_zero_s1 || b_is_zero_s1))) begin
        invalid_next = ((a_is_inf_s1 || b_is_inf_s1) && (a_is_zero_s1 || b_is_zero_s1));
        result_next = 32'h7fc00000;
    end else if (a_is_inf_s1 || b_is_inf_s1) begin
        result_next = {sign_result_s1, 8'hff, 23'd0};
    end else if (a_is_zero_s1 || b_is_zero_s1 || (mantissa_product_s1 == 48'd0)) begin
        result_next = {sign_result_s1, 31'd0};
    end else begin
        for (k = 0; k < 48; k = k + 1) begin
            if (mantissa_product_s1[k]) begin
                lead_index = k;
            end
        end

        product_exp = exp_a_unbiased_s1 + exp_b_unbiased_s1 - 46 + lead_index;
        biased_exp = product_exp + 127;

        if (lead_index >= 23) begin
            shift_right = lead_index - 23;
            shifted_product = mantissa_product_s1 >> shift_right;
            mantissa_rounded = shifted_product[23:0];

            if (shift_right > 0) begin
                guard_bit = 1'b0;
                sticky_bit = 1'b0;
                for (k = 0; k < 48; k = k + 1) begin
                    if (k == (shift_right - 1)) begin
                        guard_bit = mantissa_product_s1[k];
                    end
                    if (k < (shift_right - 1)) begin
                        sticky_bit = sticky_bit | mantissa_product_s1[k];
                    end
                end
                round_up = guard_bit & (sticky_bit | mantissa_rounded[0]);
                inexact_next = guard_bit | sticky_bit;
            end
        end else begin
            mantissa_rounded = mantissa_product_s1 << (23 - lead_index);
        end

        mantissa_round_ext = {1'b0, mantissa_rounded} + {24'd0, round_up};
        if (mantissa_round_ext[24]) begin
            mantissa_rounded = mantissa_round_ext[24:1];
            product_exp = product_exp + 1;
            biased_exp = biased_exp + 1;
        end else begin
            mantissa_rounded = mantissa_round_ext[23:0];
        end

        if (biased_exp >= 255) begin
            overflow_next = 1'b1;
            inexact_next = 1'b1;
            result_next = {sign_result_s1, 8'hff, 23'd0};
        end else if (biased_exp > 0) begin
            result_exp = biased_exp;
            result_next = {sign_result_s1, result_exp, mantissa_rounded[22:0]};
        end else begin
            underflow_next = 1'b1;
            sub_target = exp_a_unbiased_s1 + exp_b_unbiased_s1 + 103;

            if (sub_target >= 0) begin
                sub_direct = {16'd0, mantissa_product_s1} << sub_target;
                if (sub_direct[23]) begin
                    result_next = {sign_result_s1, 8'd1, 23'd0};
                end else begin
                    sub_frac = sub_direct[22:0];
                    result_next = {sign_result_s1, 8'd0, sub_frac};
                end
            end else begin
                sub_shift = -sub_target;

                if (sub_shift >= 49) begin
                    sub_frac = 23'd0;
                    sub_guard = 1'b0;
                    sub_sticky = |mantissa_product_s1;
                end else begin
                    sub_mantissa = mantissa_product_s1 >> sub_shift;
                    sub_frac = sub_mantissa[22:0];
                    sub_guard = 1'b0;
                    sub_sticky = 1'b0;
                    for (k = 0; k < 48; k = k + 1) begin
                        if (k == (sub_shift - 1)) begin
                            sub_guard = mantissa_product_s1[k];
                        end
                        if (k < (sub_shift - 1)) begin
                            sub_sticky = sub_sticky | mantissa_product_s1[k];
                        end
                    end
                end

                sub_round_up = sub_guard & (sub_sticky | sub_frac[0]);
                sub_ext = {2'd0, sub_frac} + {24'd0, sub_round_up};
                if (sub_ext[23]) begin
                    result_next = {sign_result_s1, 8'd1, 23'd0};
                end else begin
                    sub_frac = sub_ext[22:0];
                    result_next = {sign_result_s1, 8'd0, sub_frac};
                end
                inexact_next = sub_guard | sub_sticky;
            end
        end
    end
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
        mantissa_product_s1 <= 48'd0;
        valid_out <= 1'b0;
        result <= 32'd0;
        invalid <= 1'b0;
        overflow <= 1'b0;
        underflow <= 1'b0;
        inexact <= 1'b0;
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
        mantissa_product_s1 <= mantissa_product_s0;
        valid_out <= valid_s1;
        result <= result_next;
        invalid <= invalid_next;
        overflow <= overflow_next;
        underflow <= underflow_next;
        inexact <= inexact_next;
    end
end

endmodule

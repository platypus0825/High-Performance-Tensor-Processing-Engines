module fp32_mul_postprocess (
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic [47:0] mantissa_product,
    output logic [31:0] result,
    output logic        invalid,
    output logic        overflow,
    output logic        underflow,
    output logic        inexact
);

logic        sign_a;
logic        sign_b;
logic        sign_result;
logic [7:0]  exp_a;
logic [7:0]  exp_b;
logic [22:0] frac_a;
logic [22:0] frac_b;

logic a_is_zero;
logic b_is_zero;
logic a_is_inf;
logic b_is_inf;
logic a_is_nan;
logic b_is_nan;

integer exp_a_unbiased;
integer exp_b_unbiased;
integer lead_index;
integer product_exp;
integer biased_exp;
integer shift_right;
integer sub_shift;
integer sub_target;
integer k;

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

always_comb begin
    sign_a = operand_a[31];
    sign_b = operand_b[31];
    sign_result = sign_a ^ sign_b;
    exp_a = operand_a[30:23];
    exp_b = operand_b[30:23];
    frac_a = operand_a[22:0];
    frac_b = operand_b[22:0];

    a_is_zero = (exp_a == 8'd0) && (frac_a == 23'd0);
    b_is_zero = (exp_b == 8'd0) && (frac_b == 23'd0);
    a_is_inf = (exp_a == 8'hff) && (frac_a == 23'd0);
    b_is_inf = (exp_b == 8'hff) && (frac_b == 23'd0);
    a_is_nan = (exp_a == 8'hff) && (frac_a != 23'd0);
    b_is_nan = (exp_b == 8'hff) && (frac_b != 23'd0);

    invalid = 1'b0;
    overflow = 1'b0;
    underflow = 1'b0;
    inexact = 1'b0;
    result = 32'd0;

    if (exp_a == 8'd0) begin
        exp_a_unbiased = -126;
    end else begin
        exp_a_unbiased = exp_a;
        exp_a_unbiased = exp_a_unbiased - 127;
    end

    if (exp_b == 8'd0) begin
        exp_b_unbiased = -126;
    end else begin
        exp_b_unbiased = exp_b;
        exp_b_unbiased = exp_b_unbiased - 127;
    end

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

    if (a_is_nan || b_is_nan || ((a_is_inf || b_is_inf) && (a_is_zero || b_is_zero))) begin
        invalid = ((a_is_inf || b_is_inf) && (a_is_zero || b_is_zero));
        result = 32'h7fc00000;
    end else if (a_is_inf || b_is_inf) begin
        result = {sign_result, 8'hff, 23'd0};
    end else if (a_is_zero || b_is_zero || (mantissa_product == 48'd0)) begin
        result = {sign_result, 31'd0};
    end else begin
        for (k = 0; k < 48; k = k + 1) begin
            if (mantissa_product[k]) begin
                lead_index = k;
            end
        end

        product_exp = exp_a_unbiased + exp_b_unbiased - 46 + lead_index;
        biased_exp = product_exp + 127;

        if (lead_index >= 23) begin
            shift_right = lead_index - 23;
            shifted_product = mantissa_product >> shift_right;
            mantissa_rounded = shifted_product[23:0];

            if (shift_right > 0) begin
                guard_bit = 1'b0;
                sticky_bit = 1'b0;
                for (k = 0; k < 48; k = k + 1) begin
                    if (k == (shift_right - 1)) begin
                        guard_bit = mantissa_product[k];
                    end
                    if (k < (shift_right - 1)) begin
                        sticky_bit = sticky_bit | mantissa_product[k];
                    end
                end
                round_up = guard_bit & (sticky_bit | mantissa_rounded[0]);
                inexact = guard_bit | sticky_bit;
            end
        end else begin
            mantissa_rounded = mantissa_product << (23 - lead_index);
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
            overflow = 1'b1;
            inexact = 1'b1;
            result = {sign_result, 8'hff, 23'd0};
        end else if (biased_exp > 0) begin
            result_exp = biased_exp;
            result = {sign_result, result_exp, mantissa_rounded[22:0]};
        end else begin
            underflow = 1'b1;
            sub_target = exp_a_unbiased + exp_b_unbiased + 103;

            if (sub_target >= 0) begin
                sub_direct = {16'd0, mantissa_product} << sub_target;
                if (sub_direct[23]) begin
                    result = {sign_result, 8'd1, 23'd0};
                end else begin
                    sub_frac = sub_direct[22:0];
                    result = {sign_result, 8'd0, sub_frac};
                end
            end else begin
                sub_shift = -sub_target;

                if (sub_shift >= 49) begin
                    sub_frac = 23'd0;
                    sub_guard = 1'b0;
                    sub_sticky = |mantissa_product;
                end else begin
                    sub_mantissa = mantissa_product >> sub_shift;
                    sub_frac = sub_mantissa[22:0];
                    sub_guard = 1'b0;
                    sub_sticky = 1'b0;
                    for (k = 0; k < 48; k = k + 1) begin
                        if (k == (sub_shift - 1)) begin
                            sub_guard = mantissa_product[k];
                        end
                        if (k < (sub_shift - 1)) begin
                            sub_sticky = sub_sticky | mantissa_product[k];
                        end
                    end
                end

                sub_round_up = sub_guard & (sub_sticky | sub_frac[0]);
                sub_ext = {2'd0, sub_frac} + {24'd0, sub_round_up};
                if (sub_ext[23]) begin
                    result = {sign_result, 8'd1, 23'd0};
                end else begin
                    sub_frac = sub_ext[22:0];
                    result = {sign_result, 8'd0, sub_frac};
                end
                inexact = sub_guard | sub_sticky;
            end
        end
    end
end

endmodule

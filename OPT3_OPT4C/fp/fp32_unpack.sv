module fp32_unpack (
    input  logic [31:0] fp,
    output logic        sign,
    output logic [7:0]  exponent,
    output logic [22:0] fraction,
    output logic [23:0] mantissa,
    output logic        is_zero,
    output logic        is_subnormal,
    output logic        is_inf,
    output logic        is_nan
);

assign sign = fp[31];
assign exponent = fp[30:23];
assign fraction = fp[22:0];

assign is_zero = (exponent == 8'd0) && (fraction == 23'd0);
assign is_subnormal = (exponent == 8'd0) && (fraction != 23'd0);
assign is_inf = (exponent == 8'hff) && (fraction == 23'd0);
assign is_nan = (exponent == 8'hff) && (fraction != 23'd0);

always_comb begin
    if (exponent == 8'd0) begin
        mantissa = {1'b0, fraction};
    end else begin
        mantissa = {1'b1, fraction};
    end
end

endmodule

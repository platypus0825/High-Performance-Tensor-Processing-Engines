module fp32_mantissa_7bit_chunk_mul (
    input  logic [23:0] mantissa_a,
    input  logic [23:0] mantissa_b,
    output logic [47:0] product,
    output logic [31:0] a_chunks,
    output logic [31:0] b_chunks,
    output logic [15:0] pair_valid_mask,
    output logic [6:0]  group_valid_mask
);

logic [7:0] a_chunk [0:3];
logic [7:0] b_chunk [0:3];
logic [55:0] acc;
logic [15:0] pair_product;

integer i;
integer j;
integer pair_index;
integer group_index;

always_comb begin
    a_chunk[0] = {1'b0, mantissa_a[6:0]};
    a_chunk[1] = {1'b0, mantissa_a[13:7]};
    a_chunk[2] = {1'b0, mantissa_a[20:14]};
    a_chunk[3] = {5'b0, mantissa_a[23:21]};

    b_chunk[0] = {1'b0, mantissa_b[6:0]};
    b_chunk[1] = {1'b0, mantissa_b[13:7]};
    b_chunk[2] = {1'b0, mantissa_b[20:14]};
    b_chunk[3] = {5'b0, mantissa_b[23:21]};

    a_chunks = {a_chunk[3], a_chunk[2], a_chunk[1], a_chunk[0]};
    b_chunks = {b_chunk[3], b_chunk[2], b_chunk[1], b_chunk[0]};

    acc = 56'd0;
    pair_valid_mask = 16'd0;
    group_valid_mask = 7'd0;

    for (i = 0; i < 4; i = i + 1) begin
        for (j = 0; j < 4; j = j + 1) begin
            pair_index = (i * 4) + j;
            group_index = i + j;
            pair_product = a_chunk[i] * b_chunk[j];
            acc = acc + ({40'd0, pair_product} << (7 * group_index));
            pair_valid_mask[pair_index] = (a_chunk[i] != 8'd0) && (b_chunk[j] != 8'd0);
            group_valid_mask[group_index] = group_valid_mask[group_index] | pair_valid_mask[pair_index];
        end
    end

    product = acc[47:0];
end

endmodule

module fp32_mantissa_7bit_pair_scheduler (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [23:0] mantissa_a,
    input  logic [23:0] mantissa_b,
    input  logic [2:0]  min_group,
    output logic        busy,
    output logic        valid,
    output logic        done,
    output logic [7:0]  a_operand,
    output logic [7:0]  b_operand,
    output logic [1:0]  a_chunk_index,
    output logic [1:0]  b_chunk_index,
    output logic [2:0]  group_index,
    output logic [5:0]  shift_amount,
    output logic [15:0] pair_valid_mask,
    output logic [6:0]  group_valid_mask
);

logic [7:0] a_chunk [0:3];
logic [7:0] b_chunk [0:3];
logic [23:0] mantissa_a_reg;
logic [23:0] mantissa_b_reg;
logic [2:0] min_group_reg;
logic [1:0] slot_index;
logic [2:0] group_next;
logic [1:0] slot_next;
logic [1:0] sel_a_chunk_index;
logic [1:0] sel_b_chunk_index;
logic [5:0] sel_shift_amount;
logic       last_slot;
logic       last_pair;
logic       current_pair_valid;
logic [3:0] current_pair_index;
logic       current_group_enabled;

integer i;
integer j;
integer pair_index;

always_comb begin
    a_chunk[0] = {1'b0, mantissa_a_reg[6:0]};
    a_chunk[1] = {1'b0, mantissa_a_reg[13:7]};
    a_chunk[2] = {1'b0, mantissa_a_reg[20:14]};
    a_chunk[3] = {5'b0, mantissa_a_reg[23:21]};

    b_chunk[0] = {1'b0, mantissa_b_reg[6:0]};
    b_chunk[1] = {1'b0, mantissa_b_reg[13:7]};
    b_chunk[2] = {1'b0, mantissa_b_reg[20:14]};
    b_chunk[3] = {5'b0, mantissa_b_reg[23:21]};
end

always_comb begin
    pair_valid_mask = 16'd0;
    group_valid_mask = 7'd0;

    for (i = 0; i < 4; i = i + 1) begin
        for (j = 0; j < 4; j = j + 1) begin
            pair_index = (i * 4) + j;
            pair_valid_mask[pair_index] = (a_chunk[i] != 8'd0) && (b_chunk[j] != 8'd0) && ((i + j) >= min_group_reg);
            group_valid_mask[i + j] = group_valid_mask[i + j] | pair_valid_mask[pair_index];
        end
    end
end

always_comb begin
    sel_a_chunk_index = 2'd0;
    sel_b_chunk_index = 2'd0;

    case (group_index)
        3'd0: begin
            sel_a_chunk_index = 2'd0;
            sel_b_chunk_index = 2'd0;
        end
        3'd1: begin
            case (slot_index)
                2'd0: begin sel_a_chunk_index = 2'd1; sel_b_chunk_index = 2'd0; end
                default: begin sel_a_chunk_index = 2'd0; sel_b_chunk_index = 2'd1; end
            endcase
        end
        3'd2: begin
            case (slot_index)
                2'd0: begin sel_a_chunk_index = 2'd2; sel_b_chunk_index = 2'd0; end
                2'd1: begin sel_a_chunk_index = 2'd1; sel_b_chunk_index = 2'd1; end
                default: begin sel_a_chunk_index = 2'd0; sel_b_chunk_index = 2'd2; end
            endcase
        end
        3'd3: begin
            case (slot_index)
                2'd0: begin sel_a_chunk_index = 2'd3; sel_b_chunk_index = 2'd0; end
                2'd1: begin sel_a_chunk_index = 2'd2; sel_b_chunk_index = 2'd1; end
                2'd2: begin sel_a_chunk_index = 2'd1; sel_b_chunk_index = 2'd2; end
                default: begin sel_a_chunk_index = 2'd0; sel_b_chunk_index = 2'd3; end
            endcase
        end
        3'd4: begin
            case (slot_index)
                2'd0: begin sel_a_chunk_index = 2'd3; sel_b_chunk_index = 2'd1; end
                2'd1: begin sel_a_chunk_index = 2'd2; sel_b_chunk_index = 2'd2; end
                default: begin sel_a_chunk_index = 2'd1; sel_b_chunk_index = 2'd3; end
            endcase
        end
        3'd5: begin
            case (slot_index)
                2'd0: begin sel_a_chunk_index = 2'd3; sel_b_chunk_index = 2'd2; end
                default: begin sel_a_chunk_index = 2'd2; sel_b_chunk_index = 2'd3; end
            endcase
        end
        default: begin
            sel_a_chunk_index = 2'd3;
            sel_b_chunk_index = 2'd3;
        end
    endcase
end

always_comb begin
    case (group_index)
        3'd0: last_slot = 1'b1;
        3'd1: last_slot = (slot_index == 2'd1);
        3'd2: last_slot = (slot_index == 2'd2);
        3'd3: last_slot = (slot_index == 2'd3);
        3'd4: last_slot = (slot_index == 2'd2);
        3'd5: last_slot = (slot_index == 2'd1);
        default: last_slot = 1'b1;
    endcase

    if (last_slot) begin
        group_next = group_index + 3'd1;
        slot_next = 2'd0;
    end else begin
        group_next = group_index;
        slot_next = slot_index + 2'd1;
    end
end

assign sel_shift_amount = {3'd0, group_index} * 6'd7;
assign current_pair_index = (sel_a_chunk_index * 4) + sel_b_chunk_index;
assign current_group_enabled = (group_index >= min_group_reg);
assign current_pair_valid = current_group_enabled && pair_valid_mask[current_pair_index];
assign last_pair = (group_index == 3'd6) && last_slot;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy <= 1'b0;
        valid <= 1'b0;
        done <= 1'b0;
        group_index <= 3'd0;
        slot_index <= 2'd0;
        min_group_reg <= 3'd0;
        mantissa_a_reg <= 24'd0;
        mantissa_b_reg <= 24'd0;
        a_operand <= 8'd0;
        b_operand <= 8'd0;
        a_chunk_index <= 2'd0;
        b_chunk_index <= 2'd0;
        shift_amount <= 6'd0;
    end else begin
        valid <= 1'b0;
        done <= 1'b0;

        if (start && !busy) begin
            busy <= 1'b1;
            group_index <= (min_group > 3'd6) ? 3'd6 : min_group;
            slot_index <= 2'd0;
            min_group_reg <= (min_group > 3'd6) ? 3'd6 : min_group;
            mantissa_a_reg <= mantissa_a;
            mantissa_b_reg <= mantissa_b;
        end else if (busy) begin
            valid <= current_pair_valid;
            a_operand <= a_chunk[sel_a_chunk_index];
            b_operand <= b_chunk[sel_b_chunk_index];
            a_chunk_index <= sel_a_chunk_index;
            b_chunk_index <= sel_b_chunk_index;
            shift_amount <= sel_shift_amount;
            if (last_pair) begin
                busy <= 1'b0;
                done <= 1'b1;
                group_index <= 3'd0;
                slot_index <= 2'd0;
            end else begin
                group_index <= group_next;
                slot_index <= slot_next;
            end
        end
    end
end

endmodule

`include "defines.sv"

module processing_element(
    input  wire                          clk,
    input  wire                          rst_n,
    input  pe_inst_t                     pe_inst,
    input  logic                         pe_inst_valid,
    input  logic [`PE_INPUT_BITWIDTH-1:0] vector_input,
    input  logic [`PE_INPUT_BITWIDTH-1:0] matrix_input,
    output logic [`PE_OUTPUT_BITWIDTH-1:0] vector_output
);

    localparam int ACC_WIDTH = 64;

    // Encodings from simulator/src/instruction.py.
    localparam int OP_NO_VALUE = 0;
    localparam int OP_RND      = 1;

    localparam int CMD_MAC  = 0;
    localparam int CMD_OUT  = 2;
    localparam int CMD_PASS = 3;
    localparam int CMD_CLR  = 4;

    logic [ACC_WIDTH-1:0] accumulator;
    wire [ACC_WIDTH-1:0] mac_result   [0:2];
    wire [ACC_WIDTH-1:0] pass_result  [0:2];
    wire [ACC_WIDTH-1:0] round_result [0:2];
    wire [`PE_OUTPUT_BITWIDTH-1:0] out_result [0:2];

    wire [31:0] round_shift;
    assign round_shift = $unsigned(pe_inst.value);

    function automatic logic signed [ACC_WIDTH-1:0] round_even(
        input logic signed [ACC_WIDTH-1:0] value,
        input logic [31:0] shift
    );
        logic signed [ACC_WIDTH-1:0] quotient, remainder, halfway;

        if (shift == 0)
            return value;
        if (shift >= ACC_WIDTH)
            return '0;

        // Arithmetic right shift gives the floor quotient for signed values.
        quotient  = value >>> shift;
        remainder = value - (quotient <<< shift);
        halfway   = 64'sd1 <<< (shift - 1);

        if ((remainder > halfway) ||
            ((remainder == halfway) && quotient[0]))
            return quotient + 64'sd1;

        return quotient;
    endfunction

    // Mode 0 is INT8, mode 1 is INT16, and mode 2 is INT32.
    for (genvar mode = 0; mode < 3; mode++) begin : g_mode
        localparam int W = 8 << mode;
        localparam int A = W * (ACC_WIDTH / `PE_INPUT_BITWIDTH);
        localparam logic signed [W-1:0] MIN_OUT = {1'b1, {(W-1){1'b0}}};
        localparam logic signed [W-1:0] MAX_OUT = {1'b0, {(W-1){1'b1}}};

        for (genvar lane = 0; lane < `PE_INPUT_BITWIDTH / W; lane++) begin : g_lane
            wire signed [W-1:0] vector_lane, matrix_lane;
            wire signed [A-1:0] acc_lane, product;

            assign vector_lane = vector_input[lane*W +: W];
            assign matrix_lane = matrix_input[lane*W +: W];
            assign acc_lane    = accumulator[lane*A +: A];

            assign product = vector_lane * matrix_lane;
            assign mac_result[mode][lane*A +: A] = acc_lane + product;
            assign pass_result[mode][lane*A +: A] = A'(vector_lane);
            assign round_result[mode][lane*A +: A] =
                A'(round_even(ACC_WIDTH'(acc_lane), round_shift));

            assign out_result[mode][lane*W +: W] =
                (acc_lane > MAX_OUT) ? MAX_OUT :
                (acc_lane < MIN_OUT) ? MIN_OUT :
                acc_lane[W-1:0];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator   <= '0;
            vector_output <= '0;
        end else if (pe_inst_valid) begin
            if ((pe_inst.opcode == OP_NO_VALUE) &&
                (pe_inst.value == CMD_CLR)) begin
                accumulator   <= '0;
                vector_output <= '0;
            end else if (pe_inst.mode < 3) begin
                case (pe_inst.opcode)
                    OP_NO_VALUE: begin
                        case (pe_inst.value)
                            CMD_MAC:  accumulator   <= mac_result[pe_inst.mode];
                            CMD_OUT:  vector_output <= out_result[pe_inst.mode];
                            CMD_PASS: accumulator   <= pass_result[pe_inst.mode];
                            default: begin end  // NOP holds both registers.
                        endcase
                    end
                    OP_RND: accumulator <= round_result[pe_inst.mode];
                    default: begin end
                endcase
            end
        end
    end

endmodule

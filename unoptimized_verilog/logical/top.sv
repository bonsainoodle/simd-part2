`include "defines.sv"

module top (
    input wire clk,
    input wire rst_n,
    input logic [`IMEM_ADDR_WIDTH-1:0] instruction_count
);

    localparam int NUM_PES = `MEM0_BITWIDTH / `PE_INPUT_BITWIDTH;

    instruction_t inst;
    wire inst_valid;
    wire inst_exec_begins;

    pe_inst_t  pe_inst;
    buf_inst_t buf_inst;
    wire pe_inst_valid;
    wire buf_inst_valid;

    wire [`MEM0_BITWIDTH-1:0] matrix_data;
    wire [`MEM1_BITWIDTH-1:0] vector_data;
    wire [`MEM2_BITWIDTH-1:0] output_data;

    instruction_memory u_instruction_memory (
        .clk(clk),
        .rst_n(rst_n),
        .inst(inst),
        .inst_valid(inst_valid),
        .advance_pointer(inst_exec_begins),
        .instruction_count(instruction_count)
    );

    controller u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .inst(inst),
        .inst_valid(inst_valid),
        .inst_exec_begins(inst_exec_begins),
        .pe_inst(pe_inst),
        .pe_inst_valid(pe_inst_valid),
        .buf_inst(buf_inst),
        .buf_inst_valid(buf_inst_valid)
    );

    buffer u_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .buf_inst(buf_inst),
        .buf_inst_valid(buf_inst_valid),
        .output_data(output_data),
        .matrix_data(matrix_data),
        .vector_data(vector_data)
    );

    for (genvar pe = 0; pe < NUM_PES; pe++) begin : g_pe
        localparam int MATRIX_MSB =
            `MEM0_BITWIDTH - 1 - pe * `PE_INPUT_BITWIDTH;
        localparam int OUTPUT_MSB =
            `MEM2_BITWIDTH - 1 - pe * `PE_OUTPUT_BITWIDTH;

        processing_element u_pe (
            .clk(clk),
            .rst_n(rst_n),
            .pe_inst(pe_inst),
            .pe_inst_valid(pe_inst_valid),
            .vector_input(vector_data),
            .matrix_input(matrix_data[MATRIX_MSB -: `PE_INPUT_BITWIDTH]),
            .vector_output(output_data[OUTPUT_MSB -: `PE_OUTPUT_BITWIDTH])
        );
    end

endmodule

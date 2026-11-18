`include "defines.sv"

module buffer (
    // Clock and Reset
    input wire clk,
    input wire rst_n,

    // Input Instruction
    input buf_inst_t    buf_inst,
    input logic         buf_inst_valid,

    // Input Data (from the PEs)
    input  logic [`MEM2_BITWIDTH-1:0] output_data,

    // Outputs
    output logic [`MEM0_BITWIDTH-1:0] matrix_data,
    output logic [`MEM1_BITWIDTH-1:0] vector_data
);

    logic read_en;
    logic write_en;
    assign read_en  = buf_inst_valid && (buf_inst.opcode == `BUF_READ);
    assign write_en = buf_inst_valid && (buf_inst.opcode == `BUF_WRITE);

    // ---------------- Read ----------------
    // The memories read every cycle. On a READ they get the new address,
    // otherwise they get the address of the last READ again, so the outputs
    // hold their value until the next READ.
    logic [`MEM0_ADDR_WIDTH-1:0] matrix_addr;
    logic [`MEM0_ADDR_WIDTH-1:0] matrix_addr_reg;
    logic [`MEM1_ADDR_WIDTH-1:0] vector_addr;
    logic [`MEM1_ADDR_WIDTH-1:0] vector_addr_reg;
    logic [`MEM1_ADDR_WIDTH-1:0] vector_addr_decoded;
    logic [`MEM1_BITWIDTH-1:0]   vector_word;

    assign matrix_addr = read_en ? buf_inst.mema_offset : matrix_addr_reg;
    assign vector_addr = read_en ? vector_addr_decoded  : vector_addr_reg;

    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == '0) begin
            matrix_addr_reg <= '0;
            vector_addr_reg <= '0;
        end else if (read_en) begin
            matrix_addr_reg <= matrix_addr;
            vector_addr_reg <= vector_addr;
        end
    end

    array #(
        .DW(`MEM0_BITWIDTH),
        .NW(`MEM0_DEPTH),
        .AW(`MEM0_ADDR_WIDTH)
    ) u_matrix_mem (
        .clk(clk),
        .cen('0),
        .wen('1),
        .gwen('1),
        .a(matrix_addr),
        .d('0),
        .q(matrix_data)
    );

    array #(
        .DW(`MEM1_BITWIDTH),
        .NW(`MEM1_DEPTH),
        .AW(`MEM1_ADDR_WIDTH)
    ) u_vector_mem (
        .clk(clk),
        .cen('0),
        .wen('1),
        .gwen('1),
        .a(vector_addr),
        .d('0),
        .q(vector_word)
    );

    // The data comes out one cycle after the address goes in, so we save
    // the mode and offset of the READ to pick the right element later.
    logic [`BUF_MODE_BITWIDTH-1:0]        mode_reg;
    logic [`BUF_MEMB_OFFSET_BITWIDTH-1:0] memb_offset_reg;

    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == '0) begin
            mode_reg        <= '0;
            memb_offset_reg <= '0;
        end else if (read_en) begin
            mode_reg        <= buf_inst.mode;
            memb_offset_reg <= buf_inst.memb_offset;
        end
    end

    // This decoder turns the offset into a memory address
    vector_decoder u_addr_decoder (
        .data_from_mem('0),
        .addr_from_controller(buf_inst.memb_offset),
        .addr_from_controller_reg('0),
        .mode(buf_inst.mode),
        .data_to_pe(),
        .addr_to_mem(vector_addr_decoded)
    );

    // This decoder picks the element out of the word that was read
    vector_decoder u_data_decoder (
        .data_from_mem(vector_word),
        .addr_from_controller('0),
        .addr_from_controller_reg(memb_offset_reg),
        .mode(mode_reg),
        .data_to_pe(vector_data),
        .addr_to_mem()
    );

    // ---------------- Write ----------------
    // The write happens one cycle after the WRITE instruction, so that
    // the PE outputs are ready.
    
    logic                        write_en_reg;
    logic [`MEM2_ADDR_WIDTH-1:0] write_addr_reg;

    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == '0) begin
            write_en_reg   <= '0;
            write_addr_reg <= '0;
        end else begin
            write_en_reg   <= write_en;
            write_addr_reg <= buf_inst.mema_offset;
        end
    end

    logic write_control_n;
    assign write_control_n = ~write_en_reg;

    array #(
        .DW(`MEM2_BITWIDTH),
        .NW(`MEM2_DEPTH),
        .AW(`MEM2_ADDR_WIDTH),
        .INITIALIZE_MEMORY(1)
    ) u_output_mem (
        .clk(clk),
        .cen('0),
        .wen('0),
        .gwen(write_control_n),
        .a(write_addr_reg),
        .d(output_data),
        .q()
    );

    // END IMPLEMENTATION

endmodule

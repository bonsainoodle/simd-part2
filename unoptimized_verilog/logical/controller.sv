`include "defines.sv"

module controller(

    // Clock and Reset
    input wire clk,
    input wire rst_n,

    // Input Instruction
    input  instruction_t inst,
    input  logic         inst_valid,
    output logic         inst_exec_begins,

    // Output Instructions to PEs/Buffer
    output pe_inst_t     pe_inst,
    output logic         pe_inst_valid,
    output buf_inst_t    buf_inst,
    output logic         buf_inst_valid

);

    typedef enum {IDLE, EXECUTING} fsm_t;
    fsm_t state;

    // START IMPLEMENTATION

    // An instruction runs (count + 1) times. "iteration" counts the runs.
    logic [`CONTROLLER_COUNT_BITWIDTH-1:0] iteration;
    logic                                  last_iteration;

    always_comb begin
        if (inst_valid) begin
            state = EXECUTING;
        end else begin
            state = IDLE;
        end
    end

    assign last_iteration = (iteration == inst.count);

    // Move to the next instruction once the current one is on its last run
    assign inst_exec_begins = (state == EXECUTING) && last_iteration;

    // The buffer gets the instruction right away. The offsets move by one
    // on every run if the increment bit is set.
    assign buf_inst_valid = (state == EXECUTING);

    always_comb begin
        buf_inst = inst.buf_instruction;
        if (inst.mema_inc) begin
            buf_inst.mema_offset = inst.buf_instruction.mema_offset + iteration;
        end
        if (inst.memb_inc) begin
            buf_inst.memb_offset = inst.buf_instruction.memb_offset + iteration;
        end
    end

    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == '0) begin
            iteration <= '0;
        end else if (state == EXECUTING) begin
            if (last_iteration) begin
                iteration <= '0;
            end else begin
                iteration <= iteration + 1'b1;
            end
        end
    end

    // The PEs get the instruction one cycle later, because the memories
    // need one cycle to read the data.
    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == '0) begin
            pe_inst       <= '0;
            pe_inst_valid <= '0;
        end else begin
            pe_inst       <= inst.pe_instruction;
            pe_inst_valid <= (state == EXECUTING);
        end
    end

    // END IMPLEMENTATION

endmodule

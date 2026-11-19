`timescale 1ns / 1ps
`include "defines.sv"

`define CLK_PERIOD   10
`define RESET_CYCLES  5
`define INST_MEM dut.u_instruction_memory.u_instruction_memory

`define READ_LOAD_FILE(arg_str, arg_var, arg_arr) \
    initial begin \
        if ($test$plusargs(arg_str)) begin \
            $value$plusargs({arg_str, "=%s"}, arg_var); \
            $display({"[%0t] %m: ", arg_str, " IS %0s."}, $time, arg_var); \
            check_file_exists(arg_var); \
            arg_arr.loadmem(arg_var); \
        end else begin \
            $fatal({"[%0t] %m: ", arg_str, " IS NOT DEFINED."}, $time); \
        end \
    end

`define READ_INT_ARG(arg_str, arg_var) \
    initial begin \
        if ($test$plusargs(arg_str)) begin \
            $value$plusargs({arg_str, "=%d"}, arg_var); \
            $display({"[%0t] %m: ", arg_str, " IS %0d."}, $time, arg_var); \
        end else begin \
            $fatal({"[%0t] %m: ", arg_str, " IS NOT DEFINED."}, $time); \
        end \
    end

module tb_pe;

    reg clk;
    reg rst_n;
    reg [`IMEM_ADDR_WIDTH-1:0] instruction_count;
    string instruction_file;

    top_pe dut (
        .clk(clk),
        .rst_n(rst_n),
        .instruction_count(instruction_count)
    );

    task check_file_exists(input string file_name);
        integer file_id;

        file_id = $fopen(file_name, "r");
        if (!file_id) begin
            $display("%t: ERROR: Cannot open file: %s", $time, file_name);
            $finish;
        end else begin
            $fclose(file_id);
        end
    endtask

    task end_simulation();
        $assertkill();
        #2 $finish;
    endtask

    initial begin
        clk = 0;
        forever #(`CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #(`CLK_PERIOD * `RESET_CYCLES);
        rst_n = 1;
        $display("[%0t] Reset released", $time);
    end

    initial begin
        if ($test$plusargs("NODUMP")) begin
            $display("[%0t] %m: VCD/VPD DUMP OFF.", $time);
        end else begin
            $vcdpluson;
            $vcdplusmemon;
            $display("[%0t] %m: VCD/VPD DUMP ON.", $time);
        end
    end

    `READ_INT_ARG("INST_COUNT", instruction_count)
    `READ_LOAD_FILE("INST_FILE", instruction_file, `INST_MEM)

    logic simulation_complete;
    assign simulation_complete =
        (dut.u_instruction_memory.program_counter == instruction_count) &&
        !dut.pe_inst_valid && !dut.buf_inst_valid;

    always @(posedge simulation_complete) begin
        #(`CLK_PERIOD * 100);
        $display("Computation Complete, Ending Simulation.");
        end_simulation();
    end

    integer TIMEOUT = 0;
    initial begin
        if ($test$plusargs("TIMEOUT")) begin
            $value$plusargs("TIMEOUT=%d", TIMEOUT);
            $display("[%0t] %m: TIMEOUT IS %0d.", $time, TIMEOUT);
            #(TIMEOUT);
            $display("[%0t] ERROR: Timeout!", $time);
            end_simulation();
        end
    end

    initial begin
        wait (rst_n == 1'b1);
        repeat (2) @(posedge clk);
        $display("=== Starting Processing Element Testbench ===");
    end

    // Directed INT8 check using a separate processing element.
    localparam int PE_MAC = 0;
    localparam int PE_OUT = 2;
    localparam int PE_CLR = 4;

    pe_inst_t check_inst;
    logic check_valid = 1'b0;
    logic [`PE_INPUT_BITWIDTH-1:0] check_vector, check_matrix;
    wire [`PE_OUTPUT_BITWIDTH-1:0] check_output;

    processing_element pe_check (
        .clk(clk),
        .rst_n(rst_n),
        .pe_inst(check_inst),
        .pe_inst_valid(check_valid),
        .vector_input(check_vector),
        .matrix_input(check_matrix),
        .vector_output(check_output)
    );

    task automatic issue_int8(input int unsigned command);
        @(negedge clk);

        // Zero selects opcode NO_VALUE and mode INT8.
        check_inst = '0;
        check_inst.value = command;
        check_valid = 1'b1;

        @(posedge clk);
        #1; // Sample after the PE registers update.
    endtask

    initial begin
        wait (rst_n === 1'b1);

        check_vector = 32'h64_9c_03_ff; // 100, -100, 3, -1
        check_matrix = 32'h02_02_02_02;

        issue_int8(PE_CLR);
        issue_int8(PE_MAC);
        issue_int8(PE_OUT);

        // Products 200, -200, 6, -2 become 127, -128, 6, -2.
        if (check_output !== 32'h7f_80_06_fe) begin
            $fatal(1, "INT8 CLR/MAC/OUT: expected 7f8006fe, got %h",
                   check_output);
        end

        $display("PASS: INT8 CLR/MAC/OUT");

        @(negedge clk);
        check_valid = 1'b0;
    end

endmodule

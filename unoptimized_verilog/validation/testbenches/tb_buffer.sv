`timescale 1ns / 1ps
`include "defines.sv"

// Macros for controlling tb params
`define CLK_PERIOD   10
`define RESET_CYCLES  5

// Macros pointing to Memory locations
`define INST_MEM dut.u_instruction_memory.u_instruction_memory
`define MEM0 dut.u_buffer.u_matrix_mem
`define MEM1 dut.u_buffer.u_vector_mem

`define READ_LOAD_FILE(arg_str, arg_var, arg_arr) \
    initial begin \
        if($test$plusargs(arg_str)) begin \
            $value$plusargs({arg_str,"=%s"}, arg_var); \
            $display({"[%0t] %m: ",arg_str," IS %0s."},$time, arg_var); \
            check_file_exists(arg_var); \
            arg_arr.loadmem(arg_var); \
        end else begin \
            $fatal({"[%0t] %m: ",arg_str," IS NOT DEFINED."},$time); \
        end \
    end

`define READ_INT_ARG(arg_str, arg_var) \
    initial begin \
        if($test$plusargs(arg_str)) begin \
            $value$plusargs({arg_str,"=%d"}, arg_var); \
            $display({"[%0t] %m: ",arg_str," IS %0d."},$time, arg_var); \
        end else begin \
            $fatal({"[%0t] %m: ",arg_str," IS NOT DEFINED."},$time); \
        end \
    end

module tb_buffer;

    // Top Level Inputs
    reg clk;
    reg rst_n;
    reg [`IMEM_ADDR_WIDTH-1:0] instruction_count;

    // Misc. Variables for Loading Memory
    string instruction_file;
    string mem0_file;
    string mem1_file;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    top_buffer dut (
        .clk(clk),
        .rst_n(rst_n),
        .instruction_count(instruction_count)
    );

    //---------------------------------------------------------
    // Tasks
    //---------------------------------------------------------
    // Checks if file exists and bombs out if not
    task check_file_exists(input string file_name);
        integer file_id;
        file_id = $fopen(file_name,"r");
        if(!file_id) begin
            $display("%t: ERROR: Cannot open file: %s", $time, file_name);
            $fclose(file_id);
            $finish;
        end
        $fclose(file_id);
    endtask

    // Ends Simulation
    task end_simulation();
        $assertkill();
        #2 $finish;
    endtask

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 0;
        forever #(`CLK_PERIOD/2) clk = ~clk;
    end

    // =========================================================================
    // Reset Generation
    // =========================================================================
    initial begin
        rst_n = 0;
        #(`CLK_PERIOD * `RESET_CYCLES);
        rst_n = 1;
        $display("[%0t] Reset released", $time);
    end

    // =========================================================================
    // Run-Time Flags
    // =========================================================================
    initial begin
        if($test$plusargs("NODUMP")) begin
            $display("[%0t] %m: VCD/VPD DUMP OFF.",$time);
        end else begin
            $vcdpluson;
            $vcdplusmemon;
            $display("[%0t] %m: VCD/VPD DUMP ON.",$time);
        end
    end
    `READ_INT_ARG("INST_COUNT", instruction_count)
    `READ_LOAD_FILE("INST_FILE", instruction_file, `INST_MEM)
    `READ_LOAD_FILE("MEM0_FILE", mem0_file, `MEM0)
    `READ_LOAD_FILE("MEM1_FILE", mem1_file, `MEM1)

    // =========================================================================
    // Checking the Read Data Against the Memory Contents
    // =========================================================================
    logic [`MEM0_BITWIDTH-1:0] exp_matrix_data;
    logic [`MEM1_BITWIDTH-1:0] exp_vector_data;
    logic [`MEM1_BITWIDTH-1:0] vector_word;
    logic [`BUF_MEMB_OFFSET_BITWIDTH-1:0] memb_offset;
    logic         read_seen = 0;
    integer       checks    = 0;
    integer       errors    = 0;

    // Sample just before every rising clock edge
    always @(negedge clk) begin
        #(`CLK_PERIOD/2 - 1);
        if (rst_n) begin

            // The outputs must show the data of the last READ
            if (read_seen) begin
                checks = checks + 1;
                if (dut.matrix_data !== exp_matrix_data) begin
                    $display("[%0t] ERROR: matrix_data is %h, expected %h", $time, dut.matrix_data, exp_matrix_data);
                    errors = errors + 1;
                end
                if (dut.vector_data !== exp_vector_data) begin
                    $display("[%0t] ERROR: vector_data is %h, expected %h", $time, dut.vector_data, exp_vector_data);
                    errors = errors + 1;
                end
            end

            // Work out what the current READ should give next cycle
            if (dut.buf_inst_valid && (dut.buf_inst.opcode == `BUF_READ)) begin
                read_seen       = 1;
                exp_matrix_data = `MEM0.data[dut.buf_inst.mema_offset];
                memb_offset     = dut.buf_inst.memb_offset;
                case (dut.buf_inst.mode)
                    `MODE_INT8: begin
                        vector_word     = `MEM1.data[memb_offset / 4] >> (8 * (memb_offset % 4));
                        exp_vector_data = {4{vector_word[7:0]}};
                    end
                    `MODE_INT16: begin
                        vector_word     = `MEM1.data[memb_offset / 2] >> (16 * (memb_offset % 2));
                        exp_vector_data = {2{vector_word[15:0]}};
                    end
                    default: begin
                        exp_vector_data = `MEM1.data[memb_offset];
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // Determining Whether to End the Simulation
    // =========================================================================
    logic simulation_complete;
    assign simulation_complete = (dut.u_instruction_memory.program_counter == instruction_count) && ~dut.pe_inst_valid && ~dut.buf_inst_valid;
    always @(posedge simulation_complete) begin
        #(`CLK_PERIOD)
        if (checks == 0) begin
            $display("ERROR: No READ was checked");
            errors = errors + 1;
        end
        if (errors == 0) $display("TEST PASSED: %0d cycles checked", checks);
        else             $display("TEST FAILED: %0d errors", errors);
        $display("Computation Complete, Ending Simulation.");
        $assertkill();
        #2 $finish;
    end

    // Timeout to help debug when something locks up
    integer TIMEOUT = 0;
    initial begin
        if($test$plusargs("TIMEOUT")) begin
            $value$plusargs("TIMEOUT=%d", TIMEOUT);
            $display("[%0t] %m: TIMEOUT IS %0d.",$time, TIMEOUT);
            #(TIMEOUT)
            $display("[%0t] ERROR: Timeout!",$time);
            $display("TEST FAILED: the simulation did not complete");
            end_simulation();
        end
    end


    // =========================================================================
    // Starting Test
    // =========================================================================
    initial begin
        wait(rst_n == 1'b1);
        repeat(2) @(posedge clk);
        $display("=== Starting Buffer Testbench ===");
    end

endmodule

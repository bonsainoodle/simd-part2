`timescale 1ns / 1ps
`include "defines.sv"

// Macros for controlling tb params
`define CLK_PERIOD   10
`define RESET_CYCLES  5

// Macros pointing to Memory locations
`define INST_MEM dut.u_instruction_memory.u_instruction_memory
`define MEM0 dut.u_buffer.u_matrix_mem
`define MEM1 dut.u_buffer.u_vector_mem
`define MEM2 dut.u_buffer.u_output_mem

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

module tb_buffer_wb;

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
    top_buffer_wb dut (
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

    // =========================================================================
    // Checking the Output Memory
    // =========================================================================
    // top_buffer_wb drives output_data with a value that changes every
    // cycle, so a write on the wrong cycle or to the wrong address stores
    // the wrong word. The buffer writes one cycle after it gets the WRITE
    // instruction, so that is the cycle where we take the expected data.
    // The expected address comes from the instruction file, not from the
    // controller. Every address that is never written must stay zero.
    logic [`MEM2_BITWIDTH-1:0]   exp_mem [0:`MEM2_DEPTH-1];
    logic [`MEM2_ADDR_WIDTH-1:0] write_addr;
    instruction_t exp_inst;
    logic   write_pending = 0;
    integer inst_index = 0;
    integer iteration  = 0;
    integer writes = 0;
    integer i;
    integer errors = 0;

    initial begin
        for (i = 0; i < `MEM2_DEPTH; i = i + 1) exp_mem[i] = '0;
    end

    // Sample just before every rising clock edge
    always @(negedge clk) begin
        #(`CLK_PERIOD/2 - 1);
        if (rst_n) begin
            if (write_pending) begin
                exp_mem[write_addr] = dut.u_buffer.output_data;
                writes = writes + 1;
            end
            write_pending = 0;
            if (dut.buf_inst_valid) begin
                exp_inst      = `INST_MEM.data[inst_index];
                write_pending = (exp_inst.buf_instruction.opcode == `BUF_WRITE);
                write_addr    = exp_inst.buf_instruction.mema_offset + iteration * exp_inst.mema_inc;

                if (iteration == exp_inst.count) begin
                    inst_index = inst_index + 1;
                    iteration  = 0;
                end else begin
                    iteration = iteration + 1;
                end
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
        for (i = 0; i < `MEM2_DEPTH; i = i + 1) begin
            if (`MEM2.data[i] !== exp_mem[i]) begin
                $display("ERROR: output memory[%0d] is %h, expected %h", i, `MEM2.data[i], exp_mem[i]);
                errors = errors + 1;
            end
        end
        if (writes == 0) begin
            $display("ERROR: No WRITE was checked");
            errors = errors + 1;
        end
        if (errors == 0) $display("TEST PASSED: %0d writes checked", writes);
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

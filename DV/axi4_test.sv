// ============================================================
// AXI4 UVM Tests
// ============================================================

import axi4_pkg::*;

// ------------------------------------------------------------
// Base Test
// ------------------------------------------------------------
class axi4_base_test extends uvm_test;
    `uvm_component_utils(axi4_base_test)

    axi4_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi4_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction

    // Helper: raise/drop objection wrapper
    task run_test_body();
        `uvm_info(get_type_name(), "Base test - override in child", UVM_MEDIUM)
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this, "test running");
        run_test_body();
        #100;
        phase.drop_objection(this, "test done");
    endtask
endclass

// ------------------------------------------------------------
// Smoke Test
// ------------------------------------------------------------
class axi4_smoke_test extends axi4_base_test;
    `uvm_component_utils(axi4_smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_test_body();
        axi4_single_write_seq wr;
        axi4_single_read_seq  rd;

        `uvm_info(get_type_name(), "=== SMOKE TEST ===", UVM_MEDIUM)

        wr          = axi4_single_write_seq::type_id::create("wr");
        wr.wr_addr  = 32'h0000_0000;
        wr.wr_data  = 32'hDEAD_BEEF;
        wr.wr_strb  = 4'hF;
        wr.start(env.agent.sequencer);

        rd          = axi4_single_read_seq::type_id::create("rd");
        rd.rd_addr  = 32'h0000_0000;
        rd.start(env.agent.sequencer);
    endtask
endclass

// ------------------------------------------------------------
// INCR Burst Test
// ------------------------------------------------------------
class axi4_incr_burst_test extends axi4_base_test;
    `uvm_component_utils(axi4_incr_burst_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_test_body();
        axi4_incr_burst_write_seq ibw;
        axi4_incr_burst_read_seq  ibr;

        `uvm_info(get_type_name(), "=== INCR BURST TEST ===", UVM_MEDIUM)

        ibw            = axi4_incr_burst_write_seq::type_id::create("ibw");
        ibw.start_addr = 32'h0000_0000;
        ibw.num_beats  = 16;
        ibw.start(env.agent.sequencer);

        ibr            = axi4_incr_burst_read_seq::type_id::create("ibr");
        ibr.start_addr = 32'h0000_0000;
        ibr.num_beats  = 16;
        ibr.start(env.agent.sequencer);
    endtask
endclass

// ------------------------------------------------------------
// WRAP Burst Test
// ------------------------------------------------------------
class axi4_wrap_test extends axi4_base_test;
    `uvm_component_utils(axi4_wrap_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_test_body();
        axi4_wrap_burst_seq wr, rd;

        `uvm_info(get_type_name(), "=== WRAP BURST TEST ===", UVM_MEDIUM)

        // WRAP4 write at aligned address (4 beats x 4 bytes = 16 bytes = 0x10 alignment)
        wr            = axi4_wrap_burst_seq::type_id::create("wr");
        wr.is_write   = 1'b1;
        wr.wrap_addr  = 32'h0000_0010;
        wr.wrap_beats = 4;
        wr.start(env.agent.sequencer);

        // WRAP4 read back
        rd            = axi4_wrap_burst_seq::type_id::create("rd");
        rd.is_write   = 1'b0;
        rd.wrap_addr  = 32'h0000_0010;
        rd.wrap_beats = 4;
        rd.start(env.agent.sequencer);
    endtask
endclass

// ------------------------------------------------------------
// FIXED Burst Test
// ------------------------------------------------------------
class axi4_fixed_burst_test extends axi4_base_test;
    `uvm_component_utils(axi4_fixed_burst_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_test_body();
        axi4_fixed_burst_seq wr, rd;

        `uvm_info(get_type_name(), "=== FIXED BURST TEST ===", UVM_MEDIUM)

        wr            = axi4_fixed_burst_seq::type_id::create("wr");
        wr.is_write   = 1'b1;
        wr.fixed_addr = 32'h0000_0020;
        wr.num_beats  = 8;
        wr.start(env.agent.sequencer);

        rd            = axi4_fixed_burst_seq::type_id::create("rd");
        rd.is_write   = 1'b0;
        rd.fixed_addr = 32'h0000_0020;
        rd.num_beats  = 8;
        rd.start(env.agent.sequencer);
    endtask
endclass

// ------------------------------------------------------------
// Write-Read Back Test
// ------------------------------------------------------------
class axi4_wr_rd_test extends axi4_base_test;
    `uvm_component_utils(axi4_wr_rd_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_test_body();
        axi4_wr_rd_seq seq;
        `uvm_info(get_type_name(), "=== WRITE-READ TEST ===", UVM_MEDIUM)
        seq          = axi4_wr_rd_seq::type_id::create("seq");
        seq.num_txns = 20;
        seq.start(env.agent.sequencer);
    endtask
endclass

// ------------------------------------------------------------
// Random Test
// ------------------------------------------------------------
class axi4_rand_test extends axi4_base_test;
    `uvm_component_utils(axi4_rand_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_test_body();
        axi4_rand_seq seq;
        `uvm_info(get_type_name(), "=== RANDOM TEST ===", UVM_MEDIUM)
        seq          = axi4_rand_seq::type_id::create("seq");
        seq.num_txns = 200;
        seq.start(env.agent.sequencer);
    endtask
endclass

// ------------------------------------------------------------
// Error/SLVERR Test
// ------------------------------------------------------------
class axi4_error_test extends axi4_base_test;
    `uvm_component_utils(axi4_error_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_test_body();
        axi4_rand_seq  norm;
        axi4_error_seq err;

        `uvm_info(get_type_name(), "=== ERROR TEST ===", UVM_MEDIUM)

        norm = axi4_rand_seq::type_id::create("norm_pre");
        norm.num_txns = 10;
        norm.start(env.agent.sequencer);

        err = axi4_error_seq::type_id::create("err");
        err.start(env.agent.sequencer);

        norm = axi4_rand_seq::type_id::create("norm_post");
        norm.num_txns = 10;
        norm.start(env.agent.sequencer);
    endtask
endclass

// ------------------------------------------------------------
// Full Regression Test
// ------------------------------------------------------------
class axi4_full_test extends axi4_base_test;
    `uvm_component_utils(axi4_full_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_test_body();
        axi4_single_write_seq     wr1;
        axi4_single_read_seq      rd1;
        axi4_incr_burst_write_seq ibw;
        axi4_incr_burst_read_seq  ibr;
        axi4_wrap_burst_seq       ww, wr;
        axi4_fixed_burst_seq      fw, fr;
        axi4_wr_rd_seq            wr_rd;
        axi4_rand_seq             rnd;
        axi4_error_seq            err;

        `uvm_info(get_type_name(), "=== FULL REGRESSION ===", UVM_MEDIUM)

        // 1. Single write/read smoke
        wr1 = axi4_single_write_seq::type_id::create("wr1");
        wr1.wr_addr = 32'h0; wr1.wr_data = 32'hA5A5_A5A5; wr1.wr_strb = 4'hF;
        wr1.start(env.agent.sequencer);
        rd1 = axi4_single_read_seq::type_id::create("rd1");
        rd1.rd_addr = 32'h0;
        rd1.start(env.agent.sequencer);

        // 2. INCR burst
        ibw = axi4_incr_burst_write_seq::type_id::create("ibw");
        ibw.start_addr = 32'h0; ibw.num_beats = 16;
        ibw.start(env.agent.sequencer);
        ibr = axi4_incr_burst_read_seq::type_id::create("ibr");
        ibr.start_addr = 32'h0; ibr.num_beats = 16;
        ibr.start(env.agent.sequencer);

        // 3. WRAP4 burst
        ww = axi4_wrap_burst_seq::type_id::create("ww");
        ww.is_write = 1'b1; ww.wrap_addr = 32'h0000_0040; ww.wrap_beats = 4;
        ww.start(env.agent.sequencer);
        wr = axi4_wrap_burst_seq::type_id::create("wr");
        wr.is_write = 1'b0; wr.wrap_addr = 32'h0000_0040; wr.wrap_beats = 4;
        wr.start(env.agent.sequencer);

        // 4. FIXED burst
        fw = axi4_fixed_burst_seq::type_id::create("fw");
        fw.is_write = 1'b1; fw.fixed_addr = 32'h0000_0080; fw.num_beats = 8;
        fw.start(env.agent.sequencer);
        fr = axi4_fixed_burst_seq::type_id::create("fr");
        fr.is_write = 1'b0; fr.fixed_addr = 32'h0000_0080; fr.num_beats = 8;
        fr.start(env.agent.sequencer);

        // 5. Write-read back
        wr_rd = axi4_wr_rd_seq::type_id::create("wr_rd");
        wr_rd.num_txns = 30;
        wr_rd.start(env.agent.sequencer);

        // 6. Random stress
        rnd = axi4_rand_seq::type_id::create("rnd");
        rnd.num_txns = 500;
        rnd.start(env.agent.sequencer);

        // 7. Error injection
        err = axi4_error_seq::type_id::create("err");
        err.start(env.agent.sequencer);

        `uvm_info(get_type_name(), "=== FULL REGRESSION COMPLETE ===", UVM_MEDIUM)
    endtask
endclass

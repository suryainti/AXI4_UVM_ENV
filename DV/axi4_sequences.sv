// ============================================================
// AXI4 Sequences
// ============================================================

import axi4_pkg::*;

// ------------------------------------------------------------
// Base Sequence
// ------------------------------------------------------------
class axi4_base_seq extends uvm_sequence #(axi4_seq_item);
    `uvm_object_utils(axi4_base_seq)
    function new(string name = "axi4_base_seq");
        super.new(name);
    endfunction
    task body();
        `uvm_info(get_type_name(), "Base sequence - override in child", UVM_MEDIUM)
    endtask
endclass

// ------------------------------------------------------------
// Single Write
// ------------------------------------------------------------
class axi4_single_write_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_single_write_seq)

    rand logic [31:0] wr_addr;
    rand logic [31:0] wr_data;
    rand logic [3:0]  wr_strb;

    constraint c_wr {
        wr_addr[1:0] == 2'b00;
        wr_addr inside {[32'h0:32'h3FC]};
        wr_strb != 4'b0000;
    }

    function new(string name = "axi4_single_write_seq");
        super.new(name);
    endfunction

    task body();
        axi4_seq_item item = axi4_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
            xfer_type  == AXI4_WRITE;
            addr       == local::wr_addr;
            burst_len  == 0;
            burst_size == AXI4_SIZE_4B;
            burst_type == AXI4_BURST_INCR;
            data[0]    == local::wr_data;
            strb[0]    == local::wr_strb;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        finish_item(item);
        `uvm_info(get_type_name(), item.convert2string(), UVM_MEDIUM)
    endtask
endclass

// ------------------------------------------------------------
// Single Read
// ------------------------------------------------------------
class axi4_single_read_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_single_read_seq)

    rand logic [31:0] rd_addr;

    constraint c_rd {
        rd_addr[1:0] == 2'b00;
        rd_addr inside {[32'h0:32'h3FC]};
    }

    function new(string name = "axi4_single_read_seq");
        super.new(name);
    endfunction

    task body();
        axi4_seq_item item = axi4_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
            xfer_type  == AXI4_READ;
            addr       == local::rd_addr;
            burst_len  == 0;
            burst_size == AXI4_SIZE_4B;
            burst_type == AXI4_BURST_INCR;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        finish_item(item);
        `uvm_info(get_type_name(), item.convert2string(), UVM_MEDIUM)
    endtask
endclass

// ------------------------------------------------------------
// INCR Burst Write
// ------------------------------------------------------------
class axi4_incr_burst_write_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_incr_burst_write_seq)

    rand logic [31:0] start_addr;
    rand logic [7:0]  num_beats;     // 1-16

    constraint c_incr {
        start_addr[1:0] == 2'b00;
        start_addr inside {[32'h0:32'h3C0]};
        num_beats  inside {[1:16]};
    }

    function new(string name = "axi4_incr_burst_write_seq");
        super.new(name);
    endfunction

    task body();
        axi4_seq_item item = axi4_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
            xfer_type  == AXI4_WRITE;
            addr       == local::start_addr;
            burst_len  == local::num_beats - 1;
            burst_size == AXI4_SIZE_4B;
            burst_type == AXI4_BURST_INCR;
            foreach (strb[i]) strb[i] == 4'hF;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        finish_item(item);
        `uvm_info(get_type_name(), $sformatf(
            "INCR Burst Write: addr=0x%08h beats=%0d", start_addr, num_beats), UVM_MEDIUM)
    endtask
endclass

// ------------------------------------------------------------
// INCR Burst Read
// ------------------------------------------------------------
class axi4_incr_burst_read_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_incr_burst_read_seq)

    rand logic [31:0] start_addr;
    rand logic [7:0]  num_beats;

    constraint c_incr {
        start_addr[1:0] == 2'b00;
        start_addr inside {[32'h0:32'h3C0]};
        num_beats  inside {[1:16]};
    }

    function new(string name = "axi4_incr_burst_read_seq");
        super.new(name);
    endfunction

    task body();
        axi4_seq_item item = axi4_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
            xfer_type  == AXI4_READ;
            addr       == local::start_addr;
            burst_len  == local::num_beats - 1;
            burst_size == AXI4_SIZE_4B;
            burst_type == AXI4_BURST_INCR;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        finish_item(item);
        `uvm_info(get_type_name(), $sformatf(
            "INCR Burst Read: addr=0x%08h beats=%0d", start_addr, num_beats), UVM_MEDIUM)
    endtask
endclass

// ------------------------------------------------------------
// WRAP Burst Sequence (4-beat)
// ------------------------------------------------------------
class axi4_wrap_burst_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_wrap_burst_seq)

    rand logic         is_write;
    rand logic [31:0]  wrap_addr;
    rand logic [7:0]   wrap_beats;   // Must be 2,4,8,16

    constraint c_wrap {
        wrap_beats inside {2, 4, 8, 16};
        // Address aligned to total burst size
        wrap_addr % (wrap_beats * 4) == 0;
        wrap_addr inside {[32'h0:32'h3C0]};
    }

    function new(string name = "axi4_wrap_burst_seq");
        super.new(name);
    endfunction

    task body();
        axi4_seq_item item = axi4_seq_item::type_id::create("item");
        logic [7:0] wlen = wrap_beats - 1;
        start_item(item);
        if (!item.randomize() with {
            xfer_type  == (local::is_write ? AXI4_WRITE : AXI4_READ);
            addr       == local::wrap_addr;
            burst_len  == local::wlen;
            burst_size == AXI4_SIZE_4B;
            burst_type == AXI4_BURST_WRAP;
            foreach (strb[i]) strb[i] == (local::is_write ? 4'hF : 4'h0);
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        finish_item(item);
        `uvm_info(get_type_name(), $sformatf(
            "WRAP%0d %s: addr=0x%08h",
            wrap_beats, is_write ? "WRITE" : "READ", wrap_addr), UVM_MEDIUM)
    endtask
endclass

// ------------------------------------------------------------
// FIXED Burst Sequence
// ------------------------------------------------------------
class axi4_fixed_burst_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_fixed_burst_seq)

    rand logic         is_write;
    rand logic [31:0]  fixed_addr;
    rand logic [7:0]   num_beats;

    constraint c_fixed {
        fixed_addr[1:0] == 2'b00;
        fixed_addr inside {[32'h0:32'h3FC]};
        num_beats  inside {[1:16]};
    }

    function new(string name = "axi4_fixed_burst_seq");
        super.new(name);
    endfunction

    task body();
        axi4_seq_item item = axi4_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
            xfer_type  == (local::is_write ? AXI4_WRITE : AXI4_READ);
            addr       == local::fixed_addr;
            burst_len  == local::num_beats - 1;
            burst_size == AXI4_SIZE_4B;
            burst_type == AXI4_BURST_FIXED;
            foreach (strb[i]) strb[i] == (local::is_write ? 4'hF : 4'h0);
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        finish_item(item);
        `uvm_info(get_type_name(), $sformatf(
            "FIXED%0d %s: addr=0x%08h",
            num_beats, is_write ? "WRITE" : "READ", fixed_addr), UVM_MEDIUM)
    endtask
endclass

// ------------------------------------------------------------
// Write-then-Read-Back Sequence
// ------------------------------------------------------------
class axi4_wr_rd_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_wr_rd_seq)

    int unsigned num_txns = 10;

    function new(string name = "axi4_wr_rd_seq");
        super.new(name);
    endfunction

    task body();
        axi4_seq_item wr_item, rd_item;
        logic [31:0]  addr_q[$];

        // Phase 1: Write
        repeat(num_txns) begin
            wr_item = axi4_seq_item::type_id::create("wr_item");
            start_item(wr_item);
            if (!wr_item.randomize() with {
                xfer_type  == AXI4_WRITE;
                burst_len  == 0;
                burst_size == AXI4_SIZE_4B;
                burst_type == AXI4_BURST_INCR;
                strb[0]    == 4'hF;
            }) `uvm_fatal(get_type_name(), "Write rand failed")
            addr_q.push_back(wr_item.addr);
            finish_item(wr_item);
        end

        // Phase 2: Read back same addresses
        foreach (addr_q[i]) begin
            rd_item = axi4_seq_item::type_id::create("rd_item");
            start_item(rd_item);
            if (!rd_item.randomize() with {
                xfer_type  == AXI4_READ;
                addr       == local::addr_q[i];
                burst_len  == 0;
                burst_size == AXI4_SIZE_4B;
                burst_type == AXI4_BURST_INCR;
            }) `uvm_fatal(get_type_name(), "Read rand failed")
            finish_item(rd_item);
        end
    endtask
endclass

// ------------------------------------------------------------
// Random Sequence - Mixed transactions
// ------------------------------------------------------------
class axi4_rand_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_rand_seq)

    int unsigned num_txns = 50;

    function new(string name = "axi4_rand_seq");
        super.new(name);
    endfunction

    task body();
        axi4_seq_item item;
        repeat(num_txns) begin
            item = axi4_seq_item::type_id::create("item");
            start_item(item);
            if (!item.randomize())
                `uvm_fatal(get_type_name(), "Randomization failed")
            finish_item(item);
            `uvm_info(get_type_name(), item.convert2string(), UVM_HIGH)
        end
    endtask
endclass

// ------------------------------------------------------------
// Error Sequence - Out-of-range to trigger SLVERR
// The constraint c_addr in seq_item is disabled to allow
// illegal addresses
// ------------------------------------------------------------
class axi4_error_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_error_seq)

    function new(string name = "axi4_error_seq");
        super.new(name);
    endfunction

    task body();
        axi4_seq_item item = axi4_seq_item::type_id::create("item");
        start_item(item);
        // Disable addr constraint to allow out-of-range address
        if (!item.randomize() with {
            xfer_type  == AXI4_WRITE;
            addr       == 32'hDEAD_BEF0;    // Out-of-range
            burst_len  == 0;
            burst_size == AXI4_SIZE_4B;
            burst_type == AXI4_BURST_INCR;
            strb[0]    == 4'hF;
            c_addr     : soft addr == 32'hDEAD_BEF0;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        item.addr = 32'hDEAD_BEF0;          // Force override after randomize
        finish_item(item);
        `uvm_info(get_type_name(), {"Error injection: ", item.convert2string()}, UVM_MEDIUM)
    endtask
endclass

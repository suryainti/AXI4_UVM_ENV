// ============================================================
// AXI4 Functional Coverage Collector
// FIX: BRESP coverpoint now only samples on WRITE transactions
// ============================================================

import axi4_pkg::*;

class axi4_coverage extends uvm_subscriber #(axi4_seq_item);
    `uvm_component_utils(axi4_coverage)

    axi4_seq_item item;

    // ----------------------------------------------------------
    // CG1: AXI4 Transfer Attributes
    // ----------------------------------------------------------
    covergroup cg_transfer;

        cp_xfer: coverpoint item.xfer_type {
            bins WRITE = {AXI4_WRITE};
            bins READ  = {AXI4_READ};
        }

        cp_burst_type: coverpoint item.burst_type {
            bins FIXED = {AXI4_BURST_FIXED};
            bins INCR  = {AXI4_BURST_INCR};
            bins WRAP  = {AXI4_BURST_WRAP};
        }

        cp_burst_size: coverpoint item.burst_size {
            bins BYTE1 = {AXI4_SIZE_1B};
            bins BYTE2 = {AXI4_SIZE_2B};
            bins BYTE4 = {AXI4_SIZE_4B};
        }

        cp_burst_len: coverpoint item.burst_len {
            bins single  = {0};
            bins burst4  = {3};
            bins burst8  = {7};
            bins burst16 = {15};
            bins other   = default;
        }

        cp_addr_region: coverpoint item.addr {
            bins region0 = {[32'h0000_0000 : 32'h0000_00FF]};
            bins region1 = {[32'h0000_0100 : 32'h0000_01FF]};
            bins region2 = {[32'h0000_0200 : 32'h0000_02FF]};
            bins region3 = {[32'h0000_0300 : 32'h0000_03FF]};
            bins illegal = default;
        }

        // BRESP: only valid for WRITE transactions
        cp_bresp: coverpoint item.bresp iff (item.xfer_type == AXI4_WRITE) {
            bins OKAY   = {2'b00};
            bins SLVERR = {2'b10};
            illegal_bins reserved = {2'b01, 2'b11};
        }

        // Crosses
        cx_xfer_burst:  cross cp_xfer, cp_burst_type;
        cx_xfer_len:    cross cp_xfer, cp_burst_len;
        cx_burst_size_type: cross cp_burst_size, cp_burst_type;
        cx_xfer_addr:   cross cp_xfer, cp_addr_region;

    endgroup

    // ----------------------------------------------------------
    // CG2: WRAP-specific coverage
    // ----------------------------------------------------------
    covergroup cg_wrap_burst iff (item.burst_type == AXI4_BURST_WRAP);

        cp_wrap_xfer: coverpoint item.xfer_type {
            bins WRITE = {AXI4_WRITE};
            bins READ  = {AXI4_READ};
        }

        // Valid WRAP lengths: 2,4,8,16 beats = len 1,3,7,15
        cp_wrap_len: coverpoint item.burst_len {
            bins wrap2  = {1};
            bins wrap4  = {3};
            bins wrap8  = {7};
            bins wrap16 = {15};
        }

        cx_wrap_xfer_len: cross cp_wrap_xfer, cp_wrap_len;

    endgroup

    // ----------------------------------------------------------
    // CG3: RRESP per beat (only valid for READ)
    // ----------------------------------------------------------
    covergroup cg_read_resp iff (item.xfer_type == AXI4_READ);

        cp_rresp0: coverpoint (item.rresp.size() > 0 ? item.rresp[0] : 2'bxx) {
            bins OKAY   = {2'b00};
            bins SLVERR = {2'b10};
        }

    endgroup

    // ----------------------------------------------------------
    // CG4: Address Space - every 64-byte region accessed R/W
    // ----------------------------------------------------------
    covergroup cg_addr_space;

        cp_region: coverpoint item.addr[9:6] {
            bins region[16] = {[0:15]};
        }

        cp_rw: coverpoint item.xfer_type {
            bins WRITE = {AXI4_WRITE};
            bins READ  = {AXI4_READ};
        }

        cx_region_rw: cross cp_region, cp_rw;

    endgroup

    // ----------------------------------------------------------
    // CG5: Byte strobe patterns (write only)
    // ----------------------------------------------------------
    covergroup cg_strobe iff (item.xfer_type == AXI4_WRITE && item.strb.size() > 0);

        cp_strb: coverpoint item.strb[0] {
            bins full_word  = {4'b1111};
            bins byte0      = {4'b0001};
            bins byte1      = {4'b0010};
            bins byte2      = {4'b0100};
            bins byte3      = {4'b1000};
            bins low_half   = {4'b0011};
            bins high_half  = {4'b1100};
            bins other      = default;
        }

    endgroup

    // ----------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_transfer  = new();
        cg_wrap_burst = new();
        cg_read_resp  = new();
        cg_addr_space = new();
        cg_strobe     = new();
    endfunction

    // ----------------------------------------------------------
    // write: Sample all covergroups
    // ----------------------------------------------------------
    function void write(axi4_seq_item t);
        item = t;
        cg_transfer.sample();
        cg_wrap_burst.sample();
        cg_read_resp.sample();
        cg_addr_space.sample();
        cg_strobe.sample();
    endfunction

    // ----------------------------------------------------------
    // report_phase
    // ----------------------------------------------------------
    function void report_phase(uvm_phase phase);
        `uvm_info("COV", "============================================", UVM_MEDIUM)
        `uvm_info("COV", "         AXI4 COVERAGE REPORT              ", UVM_MEDIUM)
        `uvm_info("COV", "============================================", UVM_MEDIUM)
        `uvm_info("COV", $sformatf("  Transfer Coverage  : %0.2f%%",
            cg_transfer.get_coverage()),   UVM_MEDIUM)
        `uvm_info("COV", $sformatf("  WRAP Burst Cover   : %0.2f%%",
            cg_wrap_burst.get_coverage()), UVM_MEDIUM)
        `uvm_info("COV", $sformatf("  Read RRESP Cover   : %0.2f%%",
            cg_read_resp.get_coverage()),  UVM_MEDIUM)
        `uvm_info("COV", $sformatf("  Addr Space Cover   : %0.2f%%",
            cg_addr_space.get_coverage()), UVM_MEDIUM)
        `uvm_info("COV", $sformatf("  Strobe Coverage    : %0.2f%%",
            cg_strobe.get_coverage()),     UVM_MEDIUM)
        `uvm_info("COV", "============================================", UVM_MEDIUM)
    endfunction

endclass

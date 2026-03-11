// ============================================================
// AXI4 Sequence Item with Constraints
// ============================================================

import axi4_pkg::*;

class axi4_seq_item extends uvm_sequence_item;
    `uvm_object_utils(axi4_seq_item)

    // ----------------------------------------------------------
    // Randomizable Fields
    // ----------------------------------------------------------
    rand axi4_xfer_t   xfer_type;
    rand logic [3:0]   id;
    rand logic [31:0]  addr;
    rand logic [7:0]   burst_len;     // AWLEN/ARLEN: beats-1
    rand axi4_size_t   burst_size;    // AWSIZE/ARSIZE
    rand axi4_burst_t  burst_type;    // AWBURST/ARBURST

    rand logic [31:0]  data [];       // Write data per beat
    rand logic [3:0]   strb [];       // Byte enables per beat (writes only)

    // ----------------------------------------------------------
    // Response Fields (populated by driver/monitor, not randomized)
    // ----------------------------------------------------------
    logic [ID_WIDTH-1:0] bid;         // BID from B channel
    logic [1:0]          bresp;       // BRESP from B channel
    logic [ID_WIDTH-1:0] rid [];      // RID per beat
    logic [31:0]         rdata [];    // Read data per beat
    logic [1:0]          rresp [];    // RRESP per beat

    localparam int ID_WIDTH = 4;

    // ----------------------------------------------------------
    // Constraints
    // ----------------------------------------------------------

    // C1: Address word-aligned, within 1KB slave range
    constraint c_addr {
        addr inside {[32'h0000_0000 : 32'h0000_03FC]};
        addr[1:0] == 2'b00;
    }

    // C2: No reserved burst type
    constraint c_burst_type {
        burst_type != 2'b11;
    }

    // C3: Burst size <= bus width (4 bytes for 32-bit)
    constraint c_burst_size {
        burst_size inside {AXI4_SIZE_1B, AXI4_SIZE_2B, AXI4_SIZE_4B};
    }

    // C4: Burst length rules per type
    constraint c_burst_len {
        if (burst_type == AXI4_BURST_FIXED)
            burst_len inside {[0:15]};          // FIXED: max 16 beats
        else if (burst_type == AXI4_BURST_WRAP)
            burst_len inside {1, 3, 7, 15};     // WRAP: must be 2,4,8,16 beats
        else
            burst_len inside {[0:15]};          // INCR: cap to 16 for test speed
    }

    // C5: WRAP burst requires aligned start address
    constraint c_wrap_align {
        if (burst_type == AXI4_BURST_WRAP)
            addr % ((burst_len + 1) * (1 << int'(burst_size))) == 0;
    }

    // C6: Data array size = burst_len + 1
    constraint c_data_size {
        data.size() == burst_len + 1;
        strb.size() == burst_len + 1;
    }

    // C7: Byte strobes: non-zero on writes, zero on reads
    constraint c_strb {
        foreach (strb[i]) {
            if (xfer_type == AXI4_WRITE) strb[i] != 4'b0000;
            else                          strb[i] == 4'b0000;
        }
    }

    // C8: Balanced R/W distribution
    constraint c_xfer_dist {
        xfer_type dist { AXI4_WRITE := 50, AXI4_READ := 50 };
    }

    // C9: Prefer INCR burst in random tests
    constraint c_burst_dist {
        burst_type dist {
            AXI4_BURST_FIXED := 10,
            AXI4_BURST_INCR  := 70,
            AXI4_BURST_WRAP  := 20
        };
    }

    // ----------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------
    function new(string name = "axi4_seq_item");
        super.new(name);
    endfunction

    // ----------------------------------------------------------
    // do_copy: Deep copy including dynamic arrays
    // ----------------------------------------------------------
    function void do_copy(uvm_object rhs);
        axi4_seq_item rhs_t;
        super.do_copy(rhs);
        if (!$cast(rhs_t, rhs))
            `uvm_fatal("AXI4_ITEM", "do_copy: cast failed")
        this.xfer_type  = rhs_t.xfer_type;
        this.id         = rhs_t.id;
        this.addr       = rhs_t.addr;
        this.burst_len  = rhs_t.burst_len;
        this.burst_size = rhs_t.burst_size;
        this.burst_type = rhs_t.burst_type;
        // Deep copy dynamic arrays
        this.data  = new[rhs_t.data.size()](rhs_t.data);
        this.strb  = new[rhs_t.strb.size()](rhs_t.strb);
        this.bid   = rhs_t.bid;
        this.bresp = rhs_t.bresp;
        this.rid   = new[rhs_t.rid.size()](rhs_t.rid);
        this.rdata = new[rhs_t.rdata.size()](rhs_t.rdata);
        this.rresp = new[rhs_t.rresp.size()](rhs_t.rresp);
    endfunction

    // ----------------------------------------------------------
    // do_compare: Compare including dynamic arrays
    // ----------------------------------------------------------
    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axi4_seq_item rhs_t;
        if (!$cast(rhs_t, rhs)) return 0;
        if (!super.do_compare(rhs, comparer)) return 0;
        if (this.xfer_type  != rhs_t.xfer_type)  return 0;
        if (this.id         != rhs_t.id)          return 0;
        if (this.addr       != rhs_t.addr)        return 0;
        if (this.burst_len  != rhs_t.burst_len)   return 0;
        if (this.burst_size != rhs_t.burst_size)  return 0;
        if (this.burst_type != rhs_t.burst_type)  return 0;
        if (this.data.size() != rhs_t.data.size()) return 0;
        foreach (this.data[i])
            if (this.data[i] !== rhs_t.data[i]) return 0;
        return 1;
    endfunction

    // ----------------------------------------------------------
    // convert2string
    // ----------------------------------------------------------
    function string convert2string();
        string s;
        s = $sformatf(
            "%s ID=%0h ADDR=0x%08h LEN=%0d SIZE=%0dB BURST=%s",
            xfer_type.name(), id, addr, burst_len + 1,
            1 << int'(burst_size), burst_type.name());
        if (xfer_type == AXI4_WRITE && data.size() > 0)
            s = {s, $sformatf(" WDATA[0]=0x%08h STRB[0]=%04b BRESP=%s",
                 data[0], strb[0], axi4_resp_t'(bresp).name())};
        else if (xfer_type == AXI4_READ && rdata.size() > 0)
            s = {s, $sformatf(" RDATA[0]=0x%08h RRESP=%s",
                 rdata[0], axi4_resp_t'(rresp[0]).name())};
        return s;
    endfunction

    // ----------------------------------------------------------
    // do_print
    // ----------------------------------------------------------
    function void do_print(uvm_printer printer);
        super.do_print(printer);
        printer.print_string("xfer_type",  xfer_type.name());
        printer.print_string("burst_type", burst_type.name());
        printer.print_string("burst_size", burst_size.name());
        printer.print_field_int("id",        id,        4,  UVM_HEX);
        printer.print_field_int("addr",      addr,      32, UVM_HEX);
        printer.print_field_int("burst_len", burst_len, 8,  UVM_DEC);
        printer.print_field_int("bresp",     bresp,     2,  UVM_BIN);
    endfunction

endclass

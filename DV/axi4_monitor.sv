// ============================================================
// AXI4 UVM Monitor
// Observes all 5 channels via monitor clocking block
// Fork-join: write and read monitors run concurrently
//
// BUG FIX: wait_handshake previously passed logic signals as
// task 'input' arguments (value copy — never updates).
// Fixed by polling vif.monitor_cb signals directly inline.
// ============================================================

import axi4_pkg::*;

class axi4_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_monitor)

    virtual axi4_if #(.ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)) vif;

    // Single analysis port — sends complete transactions
    uvm_analysis_port #(axi4_seq_item) ap;

    // Configurable handshake timeout (clock cycles)
    int unsigned handshake_timeout = 10000;

    // Statistics
    int unsigned num_writes;
    int unsigned num_reads;
    int unsigned num_slverr_b;
    int unsigned num_slverr_r;
    int unsigned num_id_mismatches;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "axi4_vif", vif))
            `uvm_fatal("MON", "Could not get axi4_vif from config_db")
        void'(uvm_config_db #(int unsigned)::get(
            this, "", "handshake_timeout", handshake_timeout));
    endfunction

    // ----------------------------------------------------------
    // run_phase: Fork write and read monitors concurrently
    // ----------------------------------------------------------
    task run_phase(uvm_phase phase);
        @(posedge vif.ARESETn);
        `uvm_info("MON", "Reset deasserted - monitoring started", UVM_MEDIUM)
        fork
            monitor_write();
            monitor_read();
        join
    endtask

    // ----------------------------------------------------------
    // monitor_write: Collect AW → W → B transaction
    // ----------------------------------------------------------
    task monitor_write();
        axi4_seq_item item;
        forever begin
            item = axi4_seq_item::type_id::create("wr_mon_item");
            item.xfer_type = AXI4_WRITE;

            // ---- Wait for AW handshake (poll directly - NOT via task arg) ----
            begin : aw_wait
                int cnt = 0;
                do begin
                    @(vif.monitor_cb);
                    if (++cnt >= handshake_timeout)
                        `uvm_fatal("MON", "AW channel handshake timeout")
                end while (!(vif.monitor_cb.AWVALID && vif.monitor_cb.AWREADY));
            end

            // Capture AW fields
            item.id         = vif.monitor_cb.AWID;
            item.addr       = vif.monitor_cb.AWADDR;
            item.burst_len  = vif.monitor_cb.AWLEN;
            item.burst_size = axi4_size_t'(vif.monitor_cb.AWSIZE);
            item.burst_type = axi4_burst_t'(vif.monitor_cb.AWBURST);

            // Allocate data/strobe arrays
            item.data = new[item.burst_len + 1];
            item.strb = new[item.burst_len + 1];

            // ---- Collect W beats ----
            for (int i = 0; i <= item.burst_len; i++) begin : w_collect
                int cnt = 0;
                do begin
                    @(vif.monitor_cb);
                    if (++cnt >= handshake_timeout)
                        `uvm_fatal("MON", $sformatf(
                            "W channel timeout on beat %0d", i))
                end while (!(vif.monitor_cb.WVALID && vif.monitor_cb.WREADY));

                item.data[i] = vif.monitor_cb.WDATA;
                item.strb[i] = vif.monitor_cb.WSTRB;

                // Protocol checks
                if (i < item.burst_len && vif.monitor_cb.WLAST)
                    `uvm_error("MON", $sformatf(
                        "WLAST asserted early at beat %0d of %0d", i, item.burst_len))
                if (i == item.burst_len && !vif.monitor_cb.WLAST)
                    `uvm_error("MON", "WLAST not asserted on last W beat")
            end

            // ---- Wait for B handshake ----
            begin : b_wait
                int cnt = 0;
                do begin
                    @(vif.monitor_cb);
                    if (++cnt >= handshake_timeout)
                        `uvm_fatal("MON", "B channel handshake timeout")
                end while (!(vif.monitor_cb.BVALID && vif.monitor_cb.BREADY));
            end

            // Capture B response
            item.bid   = vif.monitor_cb.BID;
            item.bresp = vif.monitor_cb.BRESP;

            // BID must match AWID
            if (item.bid !== item.id) begin
                `uvm_error("MON", $sformatf(
                    "BID=0x%0h does not match AWID=0x%0h", item.bid, item.id))
                num_id_mismatches++;
            end

            // Stats
            num_writes++;
            if (item.bresp != 2'b00) num_slverr_b++;

            `uvm_info("MON", $sformatf("WRITE captured: %s", item.convert2string()), UVM_HIGH)
            ap.write(item);
        end
    endtask

    // ----------------------------------------------------------
    // monitor_read: Collect AR → R transaction
    // ----------------------------------------------------------
    task monitor_read();
        axi4_seq_item item;
        forever begin
            item = axi4_seq_item::type_id::create("rd_mon_item");
            item.xfer_type = AXI4_READ;

            // ---- Wait for AR handshake ----
            begin : ar_wait
                int cnt = 0;
                do begin
                    @(vif.monitor_cb);
                    if (++cnt >= handshake_timeout)
                        `uvm_fatal("MON", "AR channel handshake timeout")
                end while (!(vif.monitor_cb.ARVALID && vif.monitor_cb.ARREADY));
            end

            // Capture AR fields
            item.id         = vif.monitor_cb.ARID;
            item.addr       = vif.monitor_cb.ARADDR;
            item.burst_len  = vif.monitor_cb.ARLEN;
            item.burst_size = axi4_size_t'(vif.monitor_cb.ARSIZE);
            item.burst_type = axi4_burst_t'(vif.monitor_cb.ARBURST);

            // Allocate response arrays
            item.rdata = new[item.burst_len + 1];
            item.rresp = new[item.burst_len + 1];
            item.rid   = new[item.burst_len + 1];

            // ---- Collect R beats ----
            for (int i = 0; i <= item.burst_len; i++) begin : r_collect
                int cnt = 0;
                do begin
                    @(vif.monitor_cb);
                    if (++cnt >= handshake_timeout)
                        `uvm_fatal("MON", $sformatf(
                            "R channel timeout on beat %0d", i))
                end while (!(vif.monitor_cb.RVALID && vif.monitor_cb.RREADY));

                item.rid[i]   = vif.monitor_cb.RID;
                item.rdata[i] = vif.monitor_cb.RDATA;
                item.rresp[i] = vif.monitor_cb.RRESP;

                // Protocol checks
                if (i < item.burst_len && vif.monitor_cb.RLAST)
                    `uvm_error("MON", $sformatf(
                        "RLAST asserted early at beat %0d of %0d", i, item.burst_len))
                if (i == item.burst_len && !vif.monitor_cb.RLAST)
                    `uvm_error("MON", "RLAST not asserted on last R beat")

                // RID must match ARID on every beat
                if (item.rid[i] !== item.id)
                    `uvm_error("MON", $sformatf(
                        "RID=0x%0h mismatch ARID=0x%0h at beat %0d",
                        item.rid[i], item.id, i))

                if (item.rresp[i] != 2'b00) num_slverr_r++;
            end

            num_reads++;
            `uvm_info("MON", $sformatf("READ captured: %s", item.convert2string()), UVM_HIGH)
            ap.write(item);
        end
    endtask

    // ----------------------------------------------------------
    // report_phase
    // ----------------------------------------------------------
    function void report_phase(uvm_phase phase);
        `uvm_info("MON", $sformatf(
            "Monitor Stats: WRITES=%0d READS=%0d SLVERR_B=%0d SLVERR_R=%0d ID_MISMATCH=%0d",
            num_writes, num_reads, num_slverr_b, num_slverr_r, num_id_mismatches), UVM_MEDIUM)
    endfunction

endclass

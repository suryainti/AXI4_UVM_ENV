// ============================================================
// AXI4 UVM Driver
// Drives all 5 AXI4 channels via master clocking block
// ============================================================

import axi4_pkg::*;

class axi4_driver extends uvm_driver #(axi4_seq_item);
    `uvm_component_utils(axi4_driver)

    virtual axi4_if #(.ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "axi4_vif", vif))
            `uvm_fatal("DRV", "Could not get axi4_vif from config_db")
    endfunction

    task run_phase(uvm_phase phase);
        axi4_seq_item item;
        drive_idle();
        @(posedge vif.ARESETn);
        @(vif.master_cb);
        `uvm_info("DRV", "Reset complete - starting", UVM_MEDIUM)
        forever begin
            seq_item_port.get_next_item(item);
            if (item.xfer_type == AXI4_WRITE)
                drive_write(item);
            else
                drive_read(item);
            // Idle cycle between transfers
            @(vif.master_cb);
            seq_item_port.item_done();
        end
    endtask

    // ----------------------------------------------------------
    // drive_idle: Deassert all VALID signals
    // ----------------------------------------------------------
    task drive_idle();
        vif.master_cb.AWVALID  <= 1'b0;
        vif.master_cb.AWID     <= '0;
        vif.master_cb.AWADDR   <= '0;
        vif.master_cb.AWLEN    <= '0;
        vif.master_cb.AWSIZE   <= '0;
        vif.master_cb.AWBURST  <= 2'b01;
        vif.master_cb.AWLOCK   <= 1'b0;
        vif.master_cb.AWCACHE  <= 4'b0000;
        vif.master_cb.AWPROT   <= 3'b000;
        vif.master_cb.AWQOS    <= 4'b0000;
        vif.master_cb.AWREGION <= 4'b0000;
        vif.master_cb.WVALID   <= 1'b0;
        vif.master_cb.WDATA    <= '0;
        vif.master_cb.WSTRB    <= '0;
        vif.master_cb.WLAST    <= 1'b0;
        vif.master_cb.BREADY   <= 1'b0;
        vif.master_cb.ARVALID  <= 1'b0;
        vif.master_cb.ARID     <= '0;
        vif.master_cb.ARADDR   <= '0;
        vif.master_cb.ARLEN    <= '0;
        vif.master_cb.ARSIZE   <= '0;
        vif.master_cb.ARBURST  <= 2'b01;
        vif.master_cb.ARLOCK   <= 1'b0;
        vif.master_cb.ARCACHE  <= 4'b0000;
        vif.master_cb.ARPROT   <= 3'b000;
        vif.master_cb.ARQOS    <= 4'b0000;
        vif.master_cb.ARREGION <= 4'b0000;
        vif.master_cb.RREADY   <= 1'b0;
    endtask

    // ----------------------------------------------------------
    // drive_write: AW -> W (all beats) -> B response
    // ----------------------------------------------------------
    task drive_write(axi4_seq_item item);
        `uvm_info("DRV", $sformatf("WRITE: %s", item.convert2string()), UVM_HIGH)

        // ---- AW Channel ----
        @(vif.master_cb);
        vif.master_cb.AWVALID  <= 1'b1;
        vif.master_cb.AWID     <= item.id;
        vif.master_cb.AWADDR   <= item.addr;
        vif.master_cb.AWLEN    <= item.burst_len;
        vif.master_cb.AWSIZE   <= logic'(item.burst_size);
        vif.master_cb.AWBURST  <= logic'(item.burst_type);
        vif.master_cb.AWLOCK   <= 1'b0;
        vif.master_cb.AWCACHE  <= 4'b0000;
        vif.master_cb.AWPROT   <= 3'b000;
        vif.master_cb.AWQOS    <= 4'b0000;
        vif.master_cb.AWREGION <= 4'b0000;

        // Wait for AW handshake
        while (!vif.master_cb.AWREADY) @(vif.master_cb);
        @(vif.master_cb);
        vif.master_cb.AWVALID <= 1'b0;

        // ---- W Channel: Drive all beats back-to-back ----
        for (int i = 0; i <= item.burst_len; i++) begin
            vif.master_cb.WVALID <= 1'b1;
            vif.master_cb.WDATA  <= item.data[i];
            vif.master_cb.WSTRB  <= item.strb[i];
            vif.master_cb.WLAST  <= (i == int'(item.burst_len));
            // Wait for WREADY handshake
            while (!vif.master_cb.WREADY) @(vif.master_cb);
            @(vif.master_cb);
        end
        vif.master_cb.WVALID <= 1'b0;
        vif.master_cb.WLAST  <= 1'b0;

        // ---- B Channel: Accept response ----
        vif.master_cb.BREADY <= 1'b1;
        while (!vif.master_cb.BVALID) @(vif.master_cb);
        // Sample response
        item.bid   = vif.master_cb.BID;
        item.bresp = vif.master_cb.BRESP;
        @(vif.master_cb);
        vif.master_cb.BREADY <= 1'b0;

        `uvm_info("DRV", $sformatf(
            "WRITE done: BID=%0h BRESP=%s", item.bid, axi4_resp_t'(item.bresp).name()), UVM_HIGH)
    endtask

    // ----------------------------------------------------------
    // drive_read: AR -> R (collect all beats)
    // ----------------------------------------------------------
    task drive_read(axi4_seq_item item);
        `uvm_info("DRV", $sformatf("READ: %s", item.convert2string()), UVM_HIGH)

        // Allocate response arrays
        item.rdata = new[item.burst_len + 1];
        item.rresp = new[item.burst_len + 1];
        item.rid   = new[item.burst_len + 1];

        // ---- AR Channel ----
        @(vif.master_cb);
        vif.master_cb.ARVALID  <= 1'b1;
        vif.master_cb.ARID     <= item.id;
        vif.master_cb.ARADDR   <= item.addr;
        vif.master_cb.ARLEN    <= item.burst_len;
        vif.master_cb.ARSIZE   <= logic'(item.burst_size);
        vif.master_cb.ARBURST  <= logic'(item.burst_type);
        vif.master_cb.ARLOCK   <= 1'b0;
        vif.master_cb.ARCACHE  <= 4'b0000;
        vif.master_cb.ARPROT   <= 3'b000;
        vif.master_cb.ARQOS    <= 4'b0000;
        vif.master_cb.ARREGION <= 4'b0000;

        // Wait for AR handshake
        while (!vif.master_cb.ARREADY) @(vif.master_cb);
        @(vif.master_cb);
        vif.master_cb.ARVALID <= 1'b0;

        // ---- R Channel: Accept all beats ----
        vif.master_cb.RREADY <= 1'b1;
        for (int i = 0; i <= item.burst_len; i++) begin
            while (!vif.master_cb.RVALID) @(vif.master_cb);
            item.rid[i]   = vif.master_cb.RID;
            item.rdata[i] = vif.master_cb.RDATA;
            item.rresp[i] = vif.master_cb.RRESP;
            @(vif.master_cb);
        end
        vif.master_cb.RREADY <= 1'b0;

        `uvm_info("DRV", $sformatf(
            "READ done: RDATA[0]=0x%08h RRESP=%s",
            item.rdata[0], axi4_resp_t'(item.rresp[0]).name()), UVM_HIGH)
    endtask

endclass

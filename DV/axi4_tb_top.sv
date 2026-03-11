// ============================================================
// AXI4 Testbench Top
// DUT: axi4_slave (UVM driver acts as AXI4 master)
// ============================================================

`include "uvm_macros.svh"
import uvm_pkg::*;

// Shared AXI4 package (must be first)
`include "axi4_pkg.sv"

// DV files
`include "axi4_if.sv"
`include "axi4_seq_item.sv"
`include "axi4_sequences.sv"
`include "axi4_driver.sv"
`include "axi4_monitor.sv"
`include "axi4_sequencer.sv"
`include "axi4_agent.sv"
`include "axi4_scoreboard.sv"
`include "axi4_coverage.sv"
`include "axi4_env.sv"
`include "axi4_test.sv"

// RTL - DUT is the slave; UVM driver acts as AXI4 master
`include "../RTL/axi4_slave.sv"

module axi4_tb_top;

    // ----------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------
    localparam ID_WIDTH   = 4;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam MEM_DEPTH  = 256;
    localparam CLK_PERIOD = 10;  // 100 MHz

    // ----------------------------------------------------------
    // Clock & Reset
    // ----------------------------------------------------------
    logic ACLK;
    logic ARESETn;

    initial  ACLK = 1'b0;
    always  #(CLK_PERIOD/2) ACLK = ~ACLK;

    initial begin
        ARESETn = 1'b0;
        repeat(10) @(posedge ACLK);
        ARESETn = 1'b1;
        `uvm_info("TB_TOP", "ARESETn deasserted", UVM_MEDIUM)
    end

    // ----------------------------------------------------------
    // AXI4 Interface
    // ----------------------------------------------------------
    axi4_if #(
        .ID_WIDTH   (ID_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) axi4_vif (
        .ACLK    (ACLK),
        .ARESETn (ARESETn)
    );

    // ----------------------------------------------------------
    // DUT: AXI4 Slave
    // ----------------------------------------------------------
    axi4_slave #(
        .ID_WIDTH   (ID_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .MEM_DEPTH  (MEM_DEPTH)
    ) dut (
        .ACLK    (ACLK),
        .ARESETn (ARESETn),
        // AW
        .AWID    (axi4_vif.AWID),
        .AWADDR  (axi4_vif.AWADDR),
        .AWLEN   (axi4_vif.AWLEN),
        .AWSIZE  (axi4_vif.AWSIZE),
        .AWBURST (axi4_vif.AWBURST),
        .AWVALID (axi4_vif.AWVALID),
        .AWREADY (axi4_vif.AWREADY),
        // W
        .WDATA   (axi4_vif.WDATA),
        .WSTRB   (axi4_vif.WSTRB),
        .WLAST   (axi4_vif.WLAST),
        .WVALID  (axi4_vif.WVALID),
        .WREADY  (axi4_vif.WREADY),
        // B
        .BID     (axi4_vif.BID),
        .BRESP   (axi4_vif.BRESP),
        .BVALID  (axi4_vif.BVALID),
        .BREADY  (axi4_vif.BREADY),
        // AR
        .ARID    (axi4_vif.ARID),
        .ARADDR  (axi4_vif.ARADDR),
        .ARLEN   (axi4_vif.ARLEN),
        .ARSIZE  (axi4_vif.ARSIZE),
        .ARBURST (axi4_vif.ARBURST),
        .ARVALID (axi4_vif.ARVALID),
        .ARREADY (axi4_vif.ARREADY),
        // R
        .RID     (axi4_vif.RID),
        .RDATA   (axi4_vif.RDATA),
        .RRESP   (axi4_vif.RRESP),
        .RLAST   (axi4_vif.RLAST),
        .RVALID  (axi4_vif.RVALID),
        .RREADY  (axi4_vif.RREADY)
    );

    // ----------------------------------------------------------
    // UVM: Set virtual interface and start test
    // ----------------------------------------------------------
    initial begin
        uvm_config_db #(virtual axi4_if)::set(
            uvm_root::get(), "*", "axi4_vif", axi4_vif);
        run_test();  // Test name from +UVM_TESTNAME=<test>
    end

    // ----------------------------------------------------------
    // Watchdog: Kill simulation if it runs too long
    // ----------------------------------------------------------
    initial begin
        #10_000_000;
        `uvm_fatal("TB_TOP", "SIMULATION WATCHDOG TIMEOUT")
    end

    // ----------------------------------------------------------
    // Waveform Dump
    // ----------------------------------------------------------
    initial begin
        $dumpfile("axi4_tb.vcd");
        $dumpvars(0, axi4_tb_top);
    end

endmodule

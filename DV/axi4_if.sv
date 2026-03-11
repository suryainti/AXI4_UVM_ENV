// ============================================================
// AXI4 Interface - All 5 Channels with Clocking Blocks & SVA
// Compliant with AMBA AXI4 Protocol Specification (IHI0022)
// ============================================================

interface axi4_if #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input logic ACLK,
    input logic ARESETn
);

    // ---- Write Address Channel (AW) ----
    logic [ID_WIDTH-1:0]   AWID;
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [7:0]            AWLEN;
    logic [2:0]            AWSIZE;
    logic [1:0]            AWBURST;
    logic                  AWLOCK;    // AXI4: 1-bit (AXI3 was 2-bit)
    logic [3:0]            AWCACHE;
    logic [2:0]            AWPROT;
    logic [3:0]            AWQOS;
    logic [3:0]            AWREGION;
    logic                  AWVALID;
    logic                  AWREADY;

    // ---- Write Data Channel (W) ----
    logic [DATA_WIDTH-1:0] WDATA;
    logic [STRB_WIDTH-1:0] WSTRB;
    logic                  WLAST;
    logic                  WVALID;
    logic                  WREADY;

    // ---- Write Response Channel (B) ----
    logic [ID_WIDTH-1:0]   BID;
    logic [1:0]            BRESP;
    logic                  BVALID;
    logic                  BREADY;

    // ---- Read Address Channel (AR) ----
    logic [ID_WIDTH-1:0]   ARID;
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic [7:0]            ARLEN;
    logic [2:0]            ARSIZE;
    logic [1:0]            ARBURST;
    logic                  ARLOCK;    // AXI4: 1-bit
    logic [3:0]            ARCACHE;
    logic [2:0]            ARPROT;
    logic [3:0]            ARQOS;
    logic [3:0]            ARREGION;
    logic                  ARVALID;
    logic                  ARREADY;

    // ---- Read Data Channel (R) ----
    logic [ID_WIDTH-1:0]   RID;
    logic [DATA_WIDTH-1:0] RDATA;
    logic [1:0]            RRESP;
    logic                  RLAST;
    logic                  RVALID;
    logic                  RREADY;

    // ==========================================================
    // Clocking Block - Master (Driver perspective)
    // ==========================================================
    clocking master_cb @(posedge ACLK);
        default input #1step output #1;

        output AWID, AWADDR, AWLEN, AWSIZE, AWBURST,
               AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWVALID;
        input  AWREADY;

        output WDATA, WSTRB, WLAST, WVALID;
        input  WREADY;

        input  BID, BRESP, BVALID;
        output BREADY;

        output ARID, ARADDR, ARLEN, ARSIZE, ARBURST,
               ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARVALID;
        input  ARREADY;

        input  RID, RDATA, RRESP, RLAST, RVALID;
        output RREADY;
    endclocking

    // ==========================================================
    // Clocking Block - Monitor (observe all signals)
    // ==========================================================
    clocking monitor_cb @(posedge ACLK);
        default input #1step;
        input AWID, AWADDR, AWLEN, AWSIZE, AWBURST,
              AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWVALID, AWREADY;
        input WDATA, WSTRB, WLAST, WVALID, WREADY;
        input BID, BRESP, BVALID, BREADY;
        input ARID, ARADDR, ARLEN, ARSIZE, ARBURST,
              ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARVALID, ARREADY;
        input RID, RDATA, RRESP, RLAST, RVALID, RREADY;
    endclocking

    // ==========================================================
    // Modports
    // ==========================================================
    modport MASTER  (clocking master_cb,  input ACLK, ARESETn);
    modport MONITOR (clocking monitor_cb, input ACLK, ARESETn);

    // ==========================================================
    // SVA - AXI4 Protocol Assertions
    // ==========================================================

    // ---- AW Channel ----

    // A1: AWVALID must not deassert before AWREADY (handshake stability)
    property p_awvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (AWVALID && !AWREADY) |=> AWVALID;
    endproperty
    A_AWVALID_STABLE: assert property (p_awvalid_stable)
        else $error("[AXI4-SVA] AWVALID deasserted before AWREADY");

    // A2: AWADDR must be stable until handshake completes
    property p_awaddr_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (AWVALID && !AWREADY) |=> $stable(AWADDR);
    endproperty
    A_AWADDR_STABLE: assert property (p_awaddr_stable)
        else $error("[AXI4-SVA] AWADDR changed before AWREADY");

    // A3: AWLEN must be stable until handshake
    property p_awlen_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (AWVALID && !AWREADY) |=> $stable(AWLEN);
    endproperty
    A_AWLEN_STABLE: assert property (p_awlen_stable)
        else $error("[AXI4-SVA] AWLEN changed before AWREADY");

    // A4: AWBURST must not use reserved encoding 2'b11
    property p_awburst_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        AWVALID |-> (AWBURST != 2'b11);
    endproperty
    A_AWBURST_VALID: assert property (p_awburst_valid)
        else $error("[AXI4-SVA] Reserved AWBURST=2'b11 used");

    // A5: AWADDR must not be X/Z when AWVALID
    property p_awaddr_no_x;
        @(posedge ACLK) disable iff (!ARESETn)
        AWVALID |-> !$isunknown(AWADDR);
    endproperty
    A_AWADDR_NO_X: assert property (p_awaddr_no_x)
        else $error("[AXI4-SVA] X/Z on AWADDR when AWVALID");

    // A6: WRAP burst AWLEN must be 1,3,7,15 (2,4,8,16 beats)
    property p_awlen_wrap;
        @(posedge ACLK) disable iff (!ARESETn)
        (AWVALID && AWBURST == 2'b10) |->
            (AWLEN inside {8'd1, 8'd3, 8'd7, 8'd15});
    endproperty
    A_AWLEN_WRAP: assert property (p_awlen_wrap)
        else $error("[AXI4-SVA] Invalid AWLEN for WRAP burst");

    // ---- W Channel ----

    // A7: WVALID must not deassert before WREADY
    property p_wvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (WVALID && !WREADY) |=> WVALID;
    endproperty
    A_WVALID_STABLE: assert property (p_wvalid_stable)
        else $error("[AXI4-SVA] WVALID deasserted before WREADY");

    // A8: WDATA must be stable until handshake
    property p_wdata_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (WVALID && !WREADY) |=> $stable(WDATA);
    endproperty
    A_WDATA_STABLE: assert property (p_wdata_stable)
        else $error("[AXI4-SVA] WDATA changed before WREADY");

    // A9: WLAST must be stable until handshake
    property p_wlast_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (WVALID && !WREADY) |=> $stable(WLAST);
    endproperty
    A_WLAST_STABLE: assert property (p_wlast_stable)
        else $error("[AXI4-SVA] WLAST changed before WREADY");

    // ---- B Channel ----

    // A10: BVALID must not deassert before BREADY
    property p_bvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (BVALID && !BREADY) |=> BVALID;
    endproperty
    A_BVALID_STABLE: assert property (p_bvalid_stable)
        else $error("[AXI4-SVA] BVALID deasserted before BREADY");

    // A11: BRESP must not be X/Z when BVALID
    property p_bresp_no_x;
        @(posedge ACLK) disable iff (!ARESETn)
        BVALID |-> !$isunknown(BRESP);
    endproperty
    A_BRESP_NO_X: assert property (p_bresp_no_x)
        else $error("[AXI4-SVA] X/Z on BRESP when BVALID");

    // A12: BRESP must be stable until BREADY
    property p_bresp_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (BVALID && !BREADY) |=> $stable(BRESP);
    endproperty
    A_BRESP_STABLE: assert property (p_bresp_stable)
        else $error("[AXI4-SVA] BRESP changed before BREADY");

    // ---- AR Channel ----

    // A13: ARVALID must not deassert before ARREADY
    property p_arvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (ARVALID && !ARREADY) |=> ARVALID;
    endproperty
    A_ARVALID_STABLE: assert property (p_arvalid_stable)
        else $error("[AXI4-SVA] ARVALID deasserted before ARREADY");

    // A14: ARADDR must be stable until handshake
    property p_araddr_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (ARVALID && !ARREADY) |=> $stable(ARADDR);
    endproperty
    A_ARADDR_STABLE: assert property (p_araddr_stable)
        else $error("[AXI4-SVA] ARADDR changed before ARREADY");

    // A15: ARBURST must not use reserved encoding 2'b11
    property p_arburst_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        ARVALID |-> (ARBURST != 2'b11);
    endproperty
    A_ARBURST_VALID: assert property (p_arburst_valid)
        else $error("[AXI4-SVA] Reserved ARBURST=2'b11 used");

    // A16: WRAP burst ARLEN must be 1,3,7,15
    property p_arlen_wrap;
        @(posedge ACLK) disable iff (!ARESETn)
        (ARVALID && ARBURST == 2'b10) |->
            (ARLEN inside {8'd1, 8'd3, 8'd7, 8'd15});
    endproperty
    A_ARLEN_WRAP: assert property (p_arlen_wrap)
        else $error("[AXI4-SVA] Invalid ARLEN for WRAP burst");

    // ---- R Channel ----

    // A17: RVALID must not deassert before RREADY (except after RLAST)
    property p_rvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (RVALID && !RREADY && !RLAST) |=> RVALID;
    endproperty
    A_RVALID_STABLE: assert property (p_rvalid_stable)
        else $error("[AXI4-SVA] RVALID deasserted before RREADY");

    // A18: RDATA must be stable until handshake
    property p_rdata_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (RVALID && !RREADY) |=> $stable(RDATA);
    endproperty
    A_RDATA_STABLE: assert property (p_rdata_stable)
        else $error("[AXI4-SVA] RDATA changed before RREADY");

    // ---- Reset Assertions ----

    // A19: All master VALID signals deasserted during reset
    property p_reset_master_valid;
        @(posedge ACLK)
        !ARESETn |-> (!AWVALID && !WVALID && !ARVALID && !BREADY && !RREADY);
    endproperty
    A_RESET_MASTER: assert property (p_reset_master_valid)
        else $error("[AXI4-SVA] Master signals not deasserted during reset");

    // A20: All slave VALID signals deasserted during reset
    property p_reset_slave_valid;
        @(posedge ACLK)
        !ARESETn |-> (!BVALID && !RVALID);
    endproperty
    A_RESET_SLAVE: assert property (p_reset_slave_valid)
        else $error("[AXI4-SVA] Slave BVALID/RVALID not deasserted during reset");

    // ==========================================================
    // Cover Properties
    // ==========================================================
    COV_SINGLE_WRITE:  cover property (@(posedge ACLK) disable iff (!ARESETn)
                           AWVALID && AWREADY && AWLEN == 0);
    COV_BURST_WRITE:   cover property (@(posedge ACLK) disable iff (!ARESETn)
                           AWVALID && AWREADY && AWLEN > 0);
    COV_SINGLE_READ:   cover property (@(posedge ACLK) disable iff (!ARESETn)
                           ARVALID && ARREADY && ARLEN == 0);
    COV_BURST_READ:    cover property (@(posedge ACLK) disable iff (!ARESETn)
                           ARVALID && ARREADY && ARLEN > 0);
    COV_WRITE_SLVERR:  cover property (@(posedge ACLK) disable iff (!ARESETn)
                           BVALID && BREADY && BRESP == 2'b10);
    COV_READ_SLVERR:   cover property (@(posedge ACLK) disable iff (!ARESETn)
                           RVALID && RREADY && RRESP == 2'b10);
    COV_WREADY_WAIT:   cover property (@(posedge ACLK) disable iff (!ARESETn)
                           WVALID && !WREADY);
    COV_RREADY_WAIT:   cover property (@(posedge ACLK) disable iff (!ARESETn)
                           RVALID && !RREADY);
    COV_WRAP_WRITE:    cover property (@(posedge ACLK) disable iff (!ARESETn)
                           AWVALID && AWREADY && AWBURST == 2'b10);
    COV_WRAP_READ:     cover property (@(posedge ACLK) disable iff (!ARESETn)
                           ARVALID && ARREADY && ARBURST == 2'b10);
    COV_FIXED_WRITE:   cover property (@(posedge ACLK) disable iff (!ARESETn)
                           AWVALID && AWREADY && AWBURST == 2'b00);
    COV_FIXED_READ:    cover property (@(posedge ACLK) disable iff (!ARESETn)
                           ARVALID && ARREADY && ARBURST == 2'b00);

endinterface

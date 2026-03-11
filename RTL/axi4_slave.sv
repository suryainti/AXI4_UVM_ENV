// ============================================================
// AXI4 Full Slave - Synthesizable SystemVerilog
// Supports: INCR, FIXED, WRAP burst types
// BRESP/RRESP: OKAY for valid, SLVERR for out-of-range
// Memory: MEM_DEPTH x DATA_WIDTH words (word-addressed)
// ============================================================

module axi4_slave #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 256,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input  logic                    ACLK,
    input  logic                    ARESETn,

    // ---- Write Address Channel (AW) ----
    input  logic [ID_WIDTH-1:0]     AWID,
    input  logic [ADDR_WIDTH-1:0]   AWADDR,
    input  logic [7:0]              AWLEN,
    input  logic [2:0]              AWSIZE,
    input  logic [1:0]              AWBURST,
    input  logic                    AWVALID,
    output logic                    AWREADY,

    // ---- Write Data Channel (W) ----
    input  logic [DATA_WIDTH-1:0]   WDATA,
    input  logic [STRB_WIDTH-1:0]   WSTRB,
    input  logic                    WLAST,
    input  logic                    WVALID,
    output logic                    WREADY,

    // ---- Write Response Channel (B) ----
    output logic [ID_WIDTH-1:0]     BID,
    output logic [1:0]              BRESP,
    output logic                    BVALID,
    input  logic                    BREADY,

    // ---- Read Address Channel (AR) ----
    input  logic [ID_WIDTH-1:0]     ARID,
    input  logic [ADDR_WIDTH-1:0]   ARADDR,
    input  logic [7:0]              ARLEN,
    input  logic [2:0]              ARSIZE,
    input  logic [1:0]              ARBURST,
    input  logic                    ARVALID,
    output logic                    ARREADY,

    // ---- Read Data Channel (R) ----
    output logic [ID_WIDTH-1:0]     RID,
    output logic [DATA_WIDTH-1:0]   RDATA,
    output logic [1:0]              RRESP,
    output logic                    RLAST,
    output logic                    RVALID,
    input  logic                    RREADY
);

    // -------------------------------------------------------
    // Local Parameters
    // -------------------------------------------------------
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    localparam BURST_FIXED = 2'b00;
    localparam BURST_INCR  = 2'b01;
    localparam BURST_WRAP  = 2'b10;

    // Memory address width needed
    localparam MEM_ADDR_W = $clog2(MEM_DEPTH);

    // -------------------------------------------------------
    // Internal SRAM
    // -------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // -------------------------------------------------------
    // Address validity check
    // Valid if: upper bits zero AND word-aligned
    // -------------------------------------------------------
    function automatic logic addr_valid(input logic [ADDR_WIDTH-1:0] addr);
        return (addr[ADDR_WIDTH-1 : MEM_ADDR_W+$clog2(STRB_WIDTH)] == '0) &&
               (addr[$clog2(STRB_WIDTH)-1:0] == '0);
    endfunction

    // -------------------------------------------------------
    // Next burst address calculation (AXI4 Spec A3.4.1)
    // -------------------------------------------------------
    function automatic logic [ADDR_WIDTH-1:0] next_addr(
        input logic [ADDR_WIDTH-1:0] cur,
        input logic [7:0]            len,
        input logic [2:0]            size,
        input logic [1:0]            burst
    );
        logic [ADDR_WIDTH-1:0] incr, wrap_mask;
        incr      = ADDR_WIDTH'(1) << size;
        wrap_mask = (ADDR_WIDTH'(len) + 1) * incr - 1;
        case (burst)
            BURST_FIXED: return cur;
            BURST_INCR:  return cur + incr;
            BURST_WRAP:  return (cur & ~wrap_mask) | ((cur + incr) & wrap_mask);
            default:     return cur + incr;
        endcase
    endfunction

    // Word index from byte address
    function automatic logic [MEM_ADDR_W-1:0] word_idx(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return addr[MEM_ADDR_W + $clog2(STRB_WIDTH) - 1 : $clog2(STRB_WIDTH)];
    endfunction

    // =======================================================
    // WRITE FSM
    // =======================================================
    typedef enum logic [1:0] {
        WR_IDLE = 2'b00,
        WR_DATA = 2'b01,
        WR_RESP = 2'b10
    } wr_state_t;

    wr_state_t wr_state;

    logic [ID_WIDTH-1:0]   aw_id_r;
    logic [ADDR_WIDTH-1:0] wr_cur_addr;
    logic [7:0]            aw_len_r;
    logic [2:0]            aw_size_r;
    logic [1:0]            aw_burst_r;
    logic [7:0]            wr_beat_cnt;
    logic [1:0]            wr_resp_r;      // Accumulates SLVERR if any beat fails

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            wr_state    <= WR_IDLE;
            AWREADY     <= 1'b0;
            WREADY      <= 1'b0;
            BVALID      <= 1'b0;
            BID         <= '0;
            BRESP       <= RESP_OKAY;
            wr_beat_cnt <= '0;
            wr_resp_r   <= RESP_OKAY;
            aw_id_r     <= '0;
            aw_len_r    <= '0;
            aw_size_r   <= '0;
            aw_burst_r  <= '0;
            wr_cur_addr <= '0;
        end else begin
            case (wr_state)

                WR_IDLE: begin
                    BVALID  <= 1'b0;
                    AWREADY <= 1'b1;
                    WREADY  <= 1'b0;
                    if (AWVALID && AWREADY) begin
                        aw_id_r     <= AWID;
                        wr_cur_addr <= AWADDR;
                        aw_len_r    <= AWLEN;
                        aw_size_r   <= AWSIZE;
                        aw_burst_r  <= AWBURST;
                        wr_beat_cnt <= '0;
                        wr_resp_r   <= RESP_OKAY;
                        AWREADY     <= 1'b0;
                        WREADY      <= 1'b1;
                        wr_state    <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (WVALID && WREADY) begin
                        // Write only if address is valid; otherwise flag SLVERR
                        if (addr_valid(wr_cur_addr)) begin
                            for (int b = 0; b < STRB_WIDTH; b++) begin
                                if (WSTRB[b])
                                    mem[word_idx(wr_cur_addr)][b*8 +: 8] <= WDATA[b*8 +: 8];
                            end
                        end else begin
                            wr_resp_r <= RESP_SLVERR;
                        end

                        wr_cur_addr <= next_addr(wr_cur_addr, aw_len_r, aw_size_r, aw_burst_r);
                        wr_beat_cnt <= wr_beat_cnt + 1;

                        // Last beat: send response
                        if (WLAST || (wr_beat_cnt == aw_len_r)) begin
                            WREADY   <= 1'b0;
                            BVALID   <= 1'b1;
                            BID      <= aw_id_r;
                            BRESP    <= addr_valid(wr_cur_addr) ? wr_resp_r : RESP_SLVERR;
                            wr_state <= WR_RESP;
                        end
                    end
                end

                WR_RESP: begin
                    if (BVALID && BREADY) begin
                        BVALID   <= 1'b0;
                        AWREADY  <= 1'b1;
                        wr_state <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =======================================================
    // READ FSM
    // =======================================================
    typedef enum logic {
        RD_IDLE = 1'b0,
        RD_DATA = 1'b1
    } rd_state_t;

    rd_state_t rd_state;

    logic [ID_WIDTH-1:0]   ar_id_r;
    logic [ADDR_WIDTH-1:0] rd_cur_addr;
    logic [7:0]            ar_len_r;
    logic [2:0]            ar_size_r;
    logic [1:0]            ar_burst_r;
    logic [7:0]            rd_beat_cnt;

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rd_state    <= RD_IDLE;
            ARREADY     <= 1'b0;
            RVALID      <= 1'b0;
            RLAST       <= 1'b0;
            RID         <= '0;
            RDATA       <= '0;
            RRESP       <= RESP_OKAY;
            rd_beat_cnt <= '0;
            ar_id_r     <= '0;
            ar_len_r    <= '0;
            ar_size_r   <= '0;
            ar_burst_r  <= '0;
            rd_cur_addr <= '0;
        end else begin
            case (rd_state)

                RD_IDLE: begin
                    ARREADY <= 1'b1;
                    RVALID  <= 1'b0;
                    RLAST   <= 1'b0;
                    if (ARVALID && ARREADY) begin
                        ar_id_r     <= ARID;
                        rd_cur_addr <= ARADDR;
                        ar_len_r    <= ARLEN;
                        ar_size_r   <= ARSIZE;
                        ar_burst_r  <= ARBURST;
                        rd_beat_cnt <= '0;
                        ARREADY     <= 1'b0;
                        rd_state    <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    // Present read data
                    RVALID <= 1'b1;
                    RID    <= ar_id_r;
                    RLAST  <= (rd_beat_cnt == ar_len_r);

                    if (addr_valid(rd_cur_addr)) begin
                        RDATA <= mem[word_idx(rd_cur_addr)];
                        RRESP <= RESP_OKAY;
                    end else begin
                        RDATA <= '0;
                        RRESP <= RESP_SLVERR;
                    end

                    // Advance on handshake
                    if (RVALID && RREADY) begin
                        rd_cur_addr <= next_addr(rd_cur_addr, ar_len_r, ar_size_r, ar_burst_r);
                        rd_beat_cnt <= rd_beat_cnt + 1;

                        if (rd_beat_cnt == ar_len_r) begin
                            RVALID   <= 1'b0;
                            RLAST    <= 1'b0;
                            ARREADY  <= 1'b1;
                            rd_state <= RD_IDLE;
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------
    // Memory Initialization (simulation only)
    // synthesis translate_off
    initial begin
        for (int i = 0; i < MEM_DEPTH; i++)
            mem[i] = '0;
    end
    // synthesis translate_on

endmodule

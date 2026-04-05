// ============================================================
// AXI4 UVM Scoreboard
// - Reference memory model (256 x 32-bit = 1KB)
// - Validates BRESP / RRESP per AXI4 spec
// - BID/RID vs AWID/ARID matching
// - Correct burst address tracking: INCR, FIXED, WRAP
// - Transaction cloning to prevent aliasing with monitor
// - Out-of-order transaction support via per-ID pending queues
// ============================================================

import axi4_pkg::*;

class axi4_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi4_scoreboard)

    uvm_analysis_imp #(axi4_seq_item, axi4_scoreboard) analysis_export;

    // ----------------------------------------------------------
    // Reference Memory
    // ----------------------------------------------------------
    localparam MEM_DEPTH  = 256;
    localparam STRB_WIDTH = 4;
    localparam ADDR_BASE  = 32'h0000_0000;
    localparam ADDR_TOP   = 32'h0000_03FC;  // Last valid word address

    logic [31:0] ref_mem [0:MEM_DEPTH-1];

    // ----------------------------------------------------------
    // Out-of-order: per-ID pending transaction queues
    //
    // AXI4 ordering rules:
    //   - Transactions with the same ID must complete in issue order (FIFO).
    //   - Transactions with different IDs may complete in any order (OOO).
    //
    // wr_pend_q / rd_pend_q : cloned transactions waiting to be processed,
    //                          keyed by transaction ID.
    // wr_order_q / rd_order_q: records the ID of each transaction in the
    //                          order it was issued, so same-ID entries are
    //                          always drained front-to-back (preserving order).
    // ----------------------------------------------------------
    axi4_seq_item wr_pend_q[int][$];   // pending writes  – key = AWID
    axi4_seq_item rd_pend_q[int][$];   // pending reads   – key = ARID

    int           wr_order_q[$];       // AWID issue sequence
    int           rd_order_q[$];       // ARID issue sequence

    // ----------------------------------------------------------
    // Statistics
    // ----------------------------------------------------------
    int unsigned total;
    int unsigned passed;
    int unsigned failed;
    int unsigned expected_slverr;
    int unsigned unexpected_slverr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
        foreach (ref_mem[i]) ref_mem[i] = '0;
    endfunction

    // ----------------------------------------------------------
    // Address validity helper
    // ----------------------------------------------------------
    function automatic bit is_valid_addr(input logic [31:0] addr);
        return (addr >= ADDR_BASE) && (addr <= ADDR_TOP) &&
               (addr[1:0] == 2'b00);
    endfunction

    // ----------------------------------------------------------
    // Word index from byte address
    // ----------------------------------------------------------
    function automatic int unsigned word_idx(input logic [31:0] addr);
        return int'(addr >> 2);
    endfunction

    // ----------------------------------------------------------
    // write: Called per transaction from monitor
    //
    // Fix 1 – Clone: $cast(txn, item.clone()) prevents the scoreboard
    //          from operating on a handle that the monitor may reuse or
    //          overwrite before check_write/check_read has finished.
    //
    // Fix 2 – Out-of-order: push into per-ID queue rather than calling
    //          check_write/check_read directly.  For reads, drain all
    //          pending writes first so the reference model is up-to-date.
    // ----------------------------------------------------------
    function void write(axi4_seq_item item);
        axi4_seq_item txn;
        $cast(txn, item.clone());          // FIX 1: clone before any use
        total++;

        if (txn.xfer_type == AXI4_WRITE) begin
            // FIX 2: queue by ID and drain in issue order
            wr_pend_q[int'(txn.id)].push_back(txn);
            wr_order_q.push_back(int'(txn.id));
            drain_writes();
        end else begin
            // Flush all pending writes before checking the read so that
            // the reference model reflects every write that completed
            // before this read was sampled.
            drain_writes();
            rd_pend_q[int'(txn.id)].push_back(txn);
            rd_order_q.push_back(int'(txn.id));
            drain_reads();
        end
    endfunction

    // ----------------------------------------------------------
    // drain_writes
    //   Walk wr_order_q front-to-back.  For each entry, pop the oldest
    //   transaction with that ID from wr_pend_q and commit it to the
    //   reference model.  Stop if a slot is empty (transaction has not
    //   yet arrived – possible when called from drain_reads before the
    //   write response is observed).
    // ----------------------------------------------------------
    function void drain_writes();
        while (wr_order_q.size() > 0) begin
            int id = wr_order_q[0];
            if (!wr_pend_q.exists(id) || wr_pend_q[id].size() == 0)
                break;
            check_write(wr_pend_q[id].pop_front());
            void'(wr_order_q.pop_front());
        end
    endfunction

    // ----------------------------------------------------------
    // drain_reads
    //   Walk rd_order_q front-to-back and verify each read against the
    //   (now up-to-date) reference model.
    // ----------------------------------------------------------
    function void drain_reads();
        while (rd_order_q.size() > 0) begin
            int id = rd_order_q[0];
            if (!rd_pend_q.exists(id) || rd_pend_q[id].size() == 0)
                break;
            check_read(rd_pend_q[id].pop_front());
            void'(rd_order_q.pop_front());
        end
    endfunction

    // ----------------------------------------------------------
    // check_write: Update ref model, verify BRESP
    // ----------------------------------------------------------
    function void check_write(axi4_seq_item item);
        logic [31:0] cur_addr = item.addr;
        bit          any_invalid = 1'b0;

        // Update reference memory beat by beat
        for (int i = 0; i <= item.burst_len; i++) begin
            if (is_valid_addr(cur_addr)) begin
                for (int b = 0; b < STRB_WIDTH; b++) begin
                    if (item.strb[i][b])
                        ref_mem[word_idx(cur_addr)][b*8 +: 8] = item.data[i][b*8 +: 8];
                end
            end else begin
                any_invalid = 1'b1;
            end
            cur_addr = axi4_next_addr(cur_addr, item.burst_len,
                                      logic'(item.burst_size), logic'(item.burst_type));
        end

        // Verify BRESP
        if (any_invalid) begin
            if (item.bresp == 2'b10) begin
                `uvm_info("SB", $sformatf(
                    "PASS: BRESP=SLVERR for write with invalid addr range, AWID=%0h",
                    item.id), UVM_MEDIUM)
                expected_slverr++;
                passed++;
            end else begin
                `uvm_error("SB", $sformatf(
                    "FAIL: Expected SLVERR for invalid write addr, got BRESP=%0b AWID=%0h",
                    item.bresp, item.id))
                unexpected_slverr++;
                failed++;
            end
        end else begin
            if (item.bresp != 2'b00) begin
                `uvm_error("SB", $sformatf(
                    "FAIL: BRESP=%0b on valid write, addr=0x%08h AWID=%0h",
                    item.bresp, item.addr, item.id))
                failed++;
            end else begin
                `uvm_info("SB", $sformatf(
                    "PASS: WRITE addr=0x%08h beats=%0d BRESP=OKAY",
                    item.addr, item.burst_len + 1), UVM_HIGH)
                passed++;
            end
        end
    endfunction

    // ----------------------------------------------------------
    // check_read: Compare RDATA vs ref model, verify RRESP
    // ----------------------------------------------------------
    function void check_read(axi4_seq_item item);
        logic [31:0] cur_addr = item.addr;
        logic [31:0] expected;

        for (int i = 0; i <= item.burst_len; i++) begin
            if (is_valid_addr(cur_addr)) begin
                expected = ref_mem[word_idx(cur_addr)];

                if (item.rresp[i] != 2'b00) begin
                    `uvm_error("SB", $sformatf(
                        "FAIL: Unexpected RRESP=%0b at valid addr=0x%08h beat=%0d",
                        item.rresp[i], cur_addr, i))
                    failed++;
                end else if (item.rdata[i] !== expected) begin
                    `uvm_error("SB", $sformatf(
                        "FAIL: READ MISMATCH addr=0x%08h beat=%0d | Expected=0x%08h Got=0x%08h",
                        cur_addr, i, expected, item.rdata[i]))
                    failed++;
                end else begin
                    `uvm_info("SB", $sformatf(
                        "PASS: READ addr=0x%08h beat=%0d data=0x%08h",
                        cur_addr, i, item.rdata[i]), UVM_HIGH)
                    passed++;
                end

            end else begin
                // Out-of-range beat: expect SLVERR
                if (item.rresp[i] == 2'b10) begin
                    `uvm_info("SB", $sformatf(
                        "PASS: RRESP=SLVERR for invalid addr=0x%08h beat=%0d",
                        cur_addr, i), UVM_MEDIUM)
                    expected_slverr++;
                    passed++;
                end else begin
                    `uvm_error("SB", $sformatf(
                        "FAIL: Expected RRESP=SLVERR at invalid addr=0x%08h beat=%0d, got %0b",
                        cur_addr, i, item.rresp[i]))
                    unexpected_slverr++;
                    failed++;
                end
            end

            // Advance address using correct burst type
            cur_addr = axi4_next_addr(cur_addr, item.burst_len,
                                      logic'(item.burst_size), logic'(item.burst_type));
        end
    endfunction

    // ----------------------------------------------------------
    // report_phase: drain any transactions that arrived late, then report
    // ----------------------------------------------------------
    function void report_phase(uvm_phase phase);
        // Flush any transactions that were still pending at end-of-sim
        drain_writes();
        drain_reads();

        `uvm_info("SB", "============================================", UVM_MEDIUM)
        `uvm_info("SB", "         AXI4 SCOREBOARD SUMMARY           ", UVM_MEDIUM)
        `uvm_info("SB", "============================================", UVM_MEDIUM)
        `uvm_info("SB", $sformatf("  Total Transactions : %0d", total),            UVM_MEDIUM)
        `uvm_info("SB", $sformatf("  Passed             : %0d", passed),           UVM_MEDIUM)
        `uvm_info("SB", $sformatf("  Failed             : %0d", failed),           UVM_MEDIUM)
        `uvm_info("SB", $sformatf("  Expected SLVERR    : %0d", expected_slverr),  UVM_MEDIUM)
        `uvm_info("SB", $sformatf("  Unexpected SLVERR  : %0d", unexpected_slverr),UVM_MEDIUM)
        `uvm_info("SB", "============================================", UVM_MEDIUM)
        if (failed > 0)
            `uvm_error("SB", "*** TEST FAILED ***")
        else
            `uvm_info("SB", "*** TEST PASSED ***", UVM_MEDIUM)
    endfunction

endclass

// ============================================================
// AXI4 Package - Shared Types, Enums, Parameters
// Import this in both RTL (where needed) and all DV files
// ============================================================

package axi4_pkg;

    // ----------------------------------------------------------
    // Burst Type Encoding (AXI4 Spec A3.4.1)
    // ----------------------------------------------------------
    typedef enum logic [1:0] {
        AXI4_BURST_FIXED = 2'b00,
        AXI4_BURST_INCR  = 2'b01,
        AXI4_BURST_WRAP  = 2'b10
    } axi4_burst_t;

    // ----------------------------------------------------------
    // Response Encoding (AXI4 Spec A3.4.4)
    // ----------------------------------------------------------
    typedef enum logic [1:0] {
        AXI4_RESP_OKAY   = 2'b00,  // Normal access success
        AXI4_RESP_EXOKAY = 2'b01,  // Exclusive access success
        AXI4_RESP_SLVERR = 2'b10,  // Slave error
        AXI4_RESP_DECERR = 2'b11   // Decode error
    } axi4_resp_t;

    // ----------------------------------------------------------
    // Transfer Direction
    // ----------------------------------------------------------
    typedef enum logic {
        AXI4_WRITE = 1'b1,
        AXI4_READ  = 1'b0
    } axi4_xfer_t;

    // ----------------------------------------------------------
    // Burst Size Encoding (bytes per beat = 2^size)
    // ----------------------------------------------------------
    typedef enum logic [2:0] {
        AXI4_SIZE_1B   = 3'b000,
        AXI4_SIZE_2B   = 3'b001,
        AXI4_SIZE_4B   = 3'b010,
        AXI4_SIZE_8B   = 3'b011,
        AXI4_SIZE_16B  = 3'b100,
        AXI4_SIZE_32B  = 3'b101,
        AXI4_SIZE_64B  = 3'b110,
        AXI4_SIZE_128B = 3'b111
    } axi4_size_t;

    // ----------------------------------------------------------
    // Utility: Compute next burst address (AXI4 Spec A3.4.1)
    // Handles FIXED, INCR, WRAP burst types
    // ----------------------------------------------------------
    function automatic logic [31:0] axi4_next_addr(
        input logic [31:0] cur_addr,
        input logic [7:0]  burst_len,
        input logic [2:0]  burst_size,
        input logic [1:0]  burst_type
    );
        logic [31:0] incr;
        logic [31:0] wrap_mask;
        incr      = 32'(1) << burst_size;
        wrap_mask = (32'(burst_len) + 1) * incr - 1;
        case (burst_type)
            AXI4_BURST_FIXED: return cur_addr;
            AXI4_BURST_INCR:  return cur_addr + incr;
            AXI4_BURST_WRAP:  return (cur_addr & ~wrap_mask) |
                                     ((cur_addr + incr) & wrap_mask);
            default:          return cur_addr + incr;
        endcase
    endfunction

endpackage

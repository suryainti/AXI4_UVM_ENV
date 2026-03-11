// ============================================================
// AXI4 UVM Sequencer
// ============================================================

class axi4_sequencer extends uvm_sequencer #(axi4_seq_item);
    `uvm_component_utils(axi4_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass

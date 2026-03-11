// ============================================================
// AXI4 UVM Agent - ACTIVE / PASSIVE configurable
// ============================================================

class axi4_agent extends uvm_agent;
    `uvm_component_utils(axi4_agent)

    axi4_driver    driver;
    axi4_monitor   monitor;
    axi4_sequencer sequencer;

    uvm_analysis_port #(axi4_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = axi4_monitor::type_id::create("monitor", this);
        if (is_active == UVM_ACTIVE) begin
            driver    = axi4_driver::type_id::create("driver",     this);
            sequencer = axi4_sequencer::type_id::create("sequencer", this);
        end
        ap = new("ap", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        if (is_active == UVM_ACTIVE)
            driver.seq_item_port.connect(sequencer.seq_item_export);
        monitor.ap.connect(ap);
    endfunction

endclass

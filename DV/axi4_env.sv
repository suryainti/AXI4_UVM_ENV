// ============================================================
// AXI4 UVM Environment
// ============================================================

class axi4_env extends uvm_env;
    `uvm_component_utils(axi4_env)

    axi4_agent      agent;
    axi4_scoreboard scoreboard;
    axi4_coverage   coverage;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        int unsigned timeout_val;
        super.build_phase(phase);

        agent      = axi4_agent::type_id::create("agent",      this);
        scoreboard = axi4_scoreboard::type_id::create("scoreboard", this);
        coverage   = axi4_coverage::type_id::create("coverage",   this);

        // Configure agent as ACTIVE (drives + monitors)
        uvm_config_db #(uvm_active_passive_enum)::set(
            this, "agent", "is_active", UVM_ACTIVE);

        // Forward timeout config to monitor if set at test level
        if (uvm_config_db #(int unsigned)::get(this, "", "handshake_timeout", timeout_val))
            uvm_config_db #(int unsigned)::set(
                this, "agent.monitor", "handshake_timeout", timeout_val);
    endfunction

    function void connect_phase(uvm_phase phase);
        // Single analysis port → scoreboard and coverage
        agent.ap.connect(scoreboard.analysis_export);
        agent.ap.connect(coverage.analysis_export);
    endfunction

endclass

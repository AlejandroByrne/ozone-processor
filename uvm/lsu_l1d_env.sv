class lsu_l1d_env extends uvm_env;
  `uvm_component_utils(lsu_l1d_env)

  lsu_agent       agent;
  llc_responder   llc;
  lsu_scoreboard  scb;
  lsu_coverage    cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = lsu_agent::type_id::create("agent", this);
    llc   = llc_responder::type_id::create("llc", this);
    scb   = lsu_scoreboard::type_id::create("scb", this);
    cov   = lsu_coverage::type_id::create("cov", this);
  endfunction

  // ── TLM connections ──
  //
  //  monitor.req_ap   ──→  scoreboard.req_export   (stores update ref model, loads record expected)
  //  monitor.req_ap   ──→  coverage.analysis_export (sample covergroups)
  //  monitor.comp_ap  ──→  scoreboard.comp_export   (check load results)
  //
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.req_ap.connect(scb.req_export);
    agent.mon.req_ap.connect(cov.analysis_export);
    agent.mon.comp_ap.connect(scb.comp_export);
  endfunction

endclass

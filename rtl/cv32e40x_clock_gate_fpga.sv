// Copyright 2025
// FPGA-specific clock gate implementation for CV32E40X
// This file is suitable for FPGA synthesis (Xilinx/Intel)

// FPGA Implementation Notes:
// - Most modern FPGAs don't support traditional clock gating (latch-based)
// - For Xilinx FPGAs: Use BUFGCE (clock buffer with enable)
// - For power optimization: Vivado will automatically insert clock enables
// - This implementation provides a simple clock enable for FPGA synthesis

module cv32e40x_clock_gate
#(
  parameter LIB = 0
  )
(
    input  logic clk_i,
    input  logic en_i,
    input  logic scan_cg_en_i,
    output logic clk_o
  );

  // For FPGA synthesis, we have several options:
  
  `ifdef XILINX_FPGA
    // Option 1: Use Xilinx BUFGCE primitive (recommended for Xilinx FPGAs)
    // This is a clock buffer with enable, suitable for global clock gating
    
    (* dont_touch = "true" *) logic clk_en;
    
    // Register the enable signal on negative edge (safe clock gating)
    always_ff @(negedge clk_i) begin
      clk_en <= en_i | scan_cg_en_i;
    end
    
    // Instantiate Xilinx BUFGCE primitive
    BUFGCE bufgce_inst (
      .I  (clk_i),
      .CE (clk_en),
      .O  (clk_o)
    );
    
  `elsif INTEL_FPGA
    // Option 2: For Intel (Altera) FPGAs, use ALTCLKCTRL
    // Register enable on negative edge
    (* dont_touch = "true" *) logic clk_en;
    
    always_ff @(negedge clk_i) begin
      clk_en <= en_i | scan_cg_en_i;
    end
    
    // Simple AND gate for Intel FPGAs
    // Intel synthesis tools will infer appropriate clock control
    assign clk_o = clk_i & clk_en;
    
  `else
    // Option 3: Generic FPGA implementation (no specific vendor)
    // This is the safest option for portability
    // Synthesis tools will optimize this appropriately
    
    // For most FPGAs, the best approach is to NOT gate the clock
    // Instead, pass through the clock and let the enable signal
    // control flip-flops via their clock-enable pins
    
    // Simple pass-through (recommended for generic FPGA)
    assign clk_o = clk_i;
    
    // Note: The enable signal (en_i) will be used by the downstream
    // logic as a clock enable on flip-flops, which is the proper
    // way to handle clock gating in FPGAs
    
  `endif

endmodule // cv32e40x_clock_gate


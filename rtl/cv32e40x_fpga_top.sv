// Copyright 2025 - FPGA Top Level Wrapper for CV32E40X
// Simplified top-level module for FPGA implementation
// This wrapper reduces I/O count by embedding memory and simplifying interfaces

module cv32e40x_fpga_top
  import cv32e40x_pkg::*;
(
  // Minimal external I/O
  input  logic        clk_i,           // System clock
  input  logic        rst_ni,          // Active-low reset
  
  // Optional debug interface (can be removed if not needed)
  input  logic        debug_req_i,     // Debug request
  
  // Optional external interrupt
  input  logic [7:0]  irq_i,           // 8 external interrupts
  
  // Status outputs
  output logic        core_sleep_o,    // Core sleep status
  output logic [7:0]  status_leds_o    // Status LEDs for debugging
);

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam int unsigned MEM_SIZE = 65536;  // 64KB memory
  localparam int unsigned MEM_WORDS = MEM_SIZE / 4;  // Number of 32-bit words
  localparam int unsigned MEM_ADDR_WIDTH = $clog2(MEM_SIZE);
  
  // =========================================================================
  // Internal signals - Core interfaces
  // =========================================================================
  
  // Instruction memory interface
  logic                instr_req;
  logic                instr_gnt;
  logic                instr_rvalid;
  logic [31:0]         instr_addr;
  logic [1:0]          instr_memtype;
  logic [2:0]          instr_prot;
  logic                instr_dbg;
  logic [31:0]         instr_rdata;
  logic                instr_err;
  
  // Data memory interface
  logic                data_req;
  logic                data_gnt;
  logic                data_rvalid;
  logic [31:0]         data_addr;
  logic [3:0]          data_be;
  logic                data_we;
  logic [31:0]         data_wdata;
  logic [1:0]          data_memtype;
  logic [2:0]          data_prot;
  logic                data_dbg;
  logic [5:0]          data_atop;
  logic [31:0]         data_rdata;
  logic                data_err;
  logic                data_exokay;
  
  // Core static configuration
  logic [31:0]         boot_addr;
  logic [31:0]         dm_exception_addr;
  logic [31:0]         dm_halt_addr;
  logic [31:0]         mhartid;
  logic [3:0]          mimpid_patch;
  logic [31:0]         mtvec_addr;
  
  // Other core signals
  logic [63:0]         mcycle;
  logic [63:0]         time_signal;
  logic                fencei_flush_req;
  logic                fencei_flush_ack;
  logic                debug_havereset;
  logic                debug_running;
  logic                debug_halted;
  logic                debug_pc_valid;
  logic [31:0]         debug_pc;
  logic                fetch_enable;
  
  // Extended interrupt signals (padded to 32-bit)
  logic [31:0]         irq_extended;
  
  // =========================================================================
  // Configuration values
  // =========================================================================
  assign boot_addr           = 32'h00000080;  // Boot from address 0x80
  assign dm_exception_addr   = 32'h00000000;  // Debug exception address
  assign dm_halt_addr        = 32'h00000000;  // Debug halt address
  assign mhartid             = 32'h00000000;  // Hart ID
  assign mimpid_patch        = 4'h0;          // Implementation patch
  assign mtvec_addr          = 32'h00000100;  // Trap vector base
  
  assign fetch_enable        = 1'b1;          // Always enable fetch
  assign fencei_flush_ack    = fencei_flush_req; // Immediate ack for fence.i
  
  // Extend 8-bit IRQ to 32-bit
  assign irq_extended        = {24'h0, irq_i};
  
  // =========================================================================
  // Time counter (for time CSR)
  // =========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      time_signal <= 64'h0;
    end else begin
      time_signal <= time_signal + 64'h1;
    end
  end
  
  // =========================================================================
  // Status LED assignment (for debugging)
  // =========================================================================
  assign status_leds_o = {
    core_sleep_o,        // LED 7: Core sleep
    debug_halted,        // LED 6: Debug halted
    debug_running,       // LED 5: Debug running
    data_req,            // LED 4: Data request
    instr_req,           // LED 3: Instruction request
    irq_i[2:0]           // LED 2-0: IRQ status
  };
  
  // =========================================================================
  // XIF interface (tied off when not used)
  // =========================================================================
  cv32e40x_if_xif #(
    .X_NUM_RS    ( 2  ),
    .X_ID_WIDTH  ( 4  ),
    .X_MEM_WIDTH ( 32 ),
    .X_RFR_WIDTH ( 32 ),
    .X_RFW_WIDTH ( 32 ),
    .X_MISA      ( 32'h00000000 ),
    .X_ECS_XS    ( 2'b00 )
  ) xif_compressed_if();
  
  cv32e40x_if_xif #(
    .X_NUM_RS    ( 2  ),
    .X_ID_WIDTH  ( 4  ),
    .X_MEM_WIDTH ( 32 ),
    .X_RFR_WIDTH ( 32 ),
    .X_RFW_WIDTH ( 32 ),
    .X_MISA      ( 32'h00000000 ),
    .X_ECS_XS    ( 2'b00 )
  ) xif_issue_if();
  
  cv32e40x_if_xif #(
    .X_NUM_RS    ( 2  ),
    .X_ID_WIDTH  ( 4  ),
    .X_MEM_WIDTH ( 32 ),
    .X_RFR_WIDTH ( 32 ),
    .X_RFW_WIDTH ( 32 ),
    .X_MISA      ( 32'h00000000 ),
    .X_ECS_XS    ( 2'b00 )
  ) xif_commit_if();
  
  cv32e40x_if_xif #(
    .X_NUM_RS    ( 2  ),
    .X_ID_WIDTH  ( 4  ),
    .X_MEM_WIDTH ( 32 ),
    .X_RFR_WIDTH ( 32 ),
    .X_RFW_WIDTH ( 32 ),
    .X_MISA      ( 32'h00000000 ),
    .X_ECS_XS    ( 2'b00 )
  ) xif_mem_if();
  
  cv32e40x_if_xif #(
    .X_NUM_RS    ( 2  ),
    .X_ID_WIDTH  ( 4  ),
    .X_MEM_WIDTH ( 32 ),
    .X_RFR_WIDTH ( 32 ),
    .X_RFW_WIDTH ( 32 ),
    .X_MISA      ( 32'h00000000 ),
    .X_ECS_XS    ( 2'b00 )
  ) xif_mem_result_if();
  
  cv32e40x_if_xif #(
    .X_NUM_RS    ( 2  ),
    .X_ID_WIDTH  ( 4  ),
    .X_MEM_WIDTH ( 32 ),
    .X_RFR_WIDTH ( 32 ),
    .X_RFW_WIDTH ( 32 ),
    .X_MISA      ( 32'h00000000 ),
    .X_ECS_XS    ( 2'b00 )
  ) xif_result_if();
  
  // Tie off XIF interfaces (not used in this simple configuration)
  // These are inputs to the core from the coprocessor side
  assign xif_compressed_if.compressed_ready = 1'b0;
  assign xif_compressed_if.compressed_resp  = '0;
  
  assign xif_issue_if.issue_ready           = 1'b0;
  assign xif_issue_if.issue_resp            = '0;
  
  assign xif_mem_if.mem_ready               = 1'b0;
  assign xif_mem_if.mem_resp                = '0;
  
  assign xif_result_if.result_valid         = 1'b0;
  assign xif_result_if.result               = '0;
  
  // =========================================================================
  // CV32E40X Core instantiation
  // =========================================================================
  cv32e40x_core #(
    .LIB                  ( 0            ),
    .RV32                 ( RV32I        ),
    .A_EXT                ( A_NONE       ),
    .B_EXT                ( B_NONE       ),
    .M_EXT                ( M            ),
    .ZC_EXT               ( ZC_ZCA_ZCMP      ),  // Adjust as needed
    .DEBUG                ( 1            ),
    .DM_REGION_START      ( 32'hF0000000 ),
    .DM_REGION_END        ( 32'hF0003FFF ),
    .DBG_NUM_TRIGGERS     ( 1            ),
    .PMA_NUM_REGIONS      ( 0            ),
    .PMA_CFG              ( '{default:PMA_R_DEFAULT} ),
    .CLIC                 ( 0            ),
    .CLIC_ID_WIDTH        ( 5            ),
    .X_EXT                ( 0            ),
    .X_NUM_RS             ( 2            ),
    .X_ID_WIDTH           ( 4            ),
    .X_MEM_WIDTH          ( 32           ),
    .X_RFR_WIDTH          ( 32           ),
    .X_RFW_WIDTH          ( 32           ),
    .X_MISA               ( 32'h00000000 ),
    .X_ECS_XS             ( 2'b00        ),
    .NUM_MHPMCOUNTERS     ( 1            )
  ) u_core (
    // Clock and reset
    .clk_i                ( clk_i               ),
    .rst_ni               ( rst_ni              ),
    .scan_cg_en_i         ( 1'b0                ),
    
    // Static configuration
    .boot_addr_i          ( boot_addr           ),
    .dm_exception_addr_i  ( dm_exception_addr   ),
    .dm_halt_addr_i       ( dm_halt_addr        ),
    .mhartid_i            ( mhartid             ),
    .mimpid_patch_i       ( mimpid_patch        ),
    .mtvec_addr_i         ( mtvec_addr          ),
    
    // Instruction memory interface
    .instr_req_o          ( instr_req           ),
    .instr_gnt_i          ( instr_gnt           ),
    .instr_rvalid_i       ( instr_rvalid        ),
    .instr_addr_o         ( instr_addr          ),
    .instr_memtype_o      ( instr_memtype       ),
    .instr_prot_o         ( instr_prot          ),
    .instr_dbg_o          ( instr_dbg           ),
    .instr_rdata_i        ( instr_rdata         ),
    .instr_err_i          ( instr_err           ),
    
    // Data memory interface
    .data_req_o           ( data_req            ),
    .data_gnt_i           ( data_gnt            ),
    .data_rvalid_i        ( data_rvalid         ),
    .data_addr_o          ( data_addr           ),
    .data_be_o            ( data_be             ),
    .data_we_o            ( data_we             ),
    .data_wdata_o         ( data_wdata          ),
    .data_memtype_o       ( data_memtype        ),
    .data_prot_o          ( data_prot           ),
    .data_dbg_o           ( data_dbg            ),
    .data_atop_o          ( data_atop           ),
    .data_rdata_i         ( data_rdata          ),
    .data_err_i           ( data_err            ),
    .data_exokay_i        ( data_exokay         ),
    
    // Cycle count
    .mcycle_o             ( mcycle              ),
    
    // Time input
    .time_i               ( time_signal         ),
    
    // eXtension interface
    .xif_compressed_if    ( xif_compressed_if   ),
    .xif_issue_if         ( xif_issue_if        ),
    .xif_commit_if        ( xif_commit_if       ),
    .xif_mem_if           ( xif_mem_if          ),
    .xif_mem_result_if    ( xif_mem_result_if   ),
    .xif_result_if        ( xif_result_if       ),
    
    // Basic interrupt architecture
    .irq_i                ( irq_extended        ),
    
    // Event wakeup signals
    .wu_wfe_i             ( 1'b0                ),
    
    // CLIC interrupt architecture (not used)
    .clic_irq_i           ( 1'b0                ),
    .clic_irq_id_i        ( '0                  ),
    .clic_irq_level_i     ( '0                  ),
    .clic_irq_priv_i      ( '0                  ),
    .clic_irq_shv_i       ( 1'b0                ),
    
    // Fence.i flush handshake
    .fencei_flush_req_o   ( fencei_flush_req    ),
    .fencei_flush_ack_i   ( fencei_flush_ack    ),
    
    // Debug interface
    .debug_req_i          ( debug_req_i         ),
    .debug_havereset_o    ( debug_havereset     ),
    .debug_running_o      ( debug_running       ),
    .debug_halted_o       ( debug_halted        ),
    .debug_pc_valid_o     ( debug_pc_valid      ),
    .debug_pc_o           ( debug_pc            ),
    
    // CPU control signals
    .fetch_enable_i       ( fetch_enable        ),
    .core_sleep_o         ( core_sleep_o        )
  );
  
  // =========================================================================
  // Instruction Memory (BRAM)
  // =========================================================================
  logic [MEM_ADDR_WIDTH-1:0] instr_mem_addr;
  logic                      instr_mem_valid;
  logic [31:0]               instr_mem_rdata;
  
  assign instr_mem_addr  = instr_addr[MEM_ADDR_WIDTH-1:0];
  assign instr_gnt       = instr_req;  // Always grant immediately
  assign instr_err       = 1'b0;       // No errors
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_mem_valid <= 1'b0;
    end else begin
      instr_mem_valid <= instr_req;
    end
  end
  
  assign instr_rvalid = instr_mem_valid;
  assign instr_rdata = instr_mem_rdata;
  
  // Instruction memory instance - 32-bit word array (BRAM-friendly)
  (* ram_style = "block" *) logic [31:0] instr_mem [0:MEM_WORDS-1];
  
  // BRAM inference pattern
  always_ff @(posedge clk_i) begin
    if (instr_req) begin
      instr_mem_rdata <= instr_mem[instr_mem_addr[MEM_ADDR_WIDTH-1:2]];
    end
  end
  
  // Initialize instruction memory with a simple program
  initial begin
    integer i;
    // Simple test program: infinite loop
    // 0x80: addi x1, x0, 1    (li x1, 1)
    // 0x84: addi x2, x1, 2    (addi x2, x1, 2)
    // 0x88: jal x0, -8        (j -8, infinite loop)
    instr_mem[32'h20] = 32'h00100093;  // addi x1, x0, 1
    instr_mem[32'h21] = 32'h00208113;  // addi x2, x1, 2
    instr_mem[32'h22] = 32'hFF9FF06F;  // jal x0, -8
    
    // Fill rest with NOPs
    for (i = 0; i < MEM_WORDS; i = i + 1) begin
      if (i < 32'h20 || i > 32'h22) begin
        instr_mem[i] = 32'h00000013;   // nop (addi x0, x0, 0)
      end
    end
  end
  
  // =========================================================================
  // Data Memory (BRAM with byte enable support)
  // =========================================================================
  logic [MEM_ADDR_WIDTH-1:0] data_mem_addr;
  logic                      data_mem_valid;
  logic [31:0]               data_mem_rdata;
  logic [31:0]               data_mem_rdata_word;
  
  assign data_mem_addr = data_addr[MEM_ADDR_WIDTH-1:0];
  assign data_gnt      = data_req;   // Always grant immediately
  assign data_err      = 1'b0;       // No errors
  assign data_exokay   = 1'b1;       // Exclusive access always OK
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_mem_valid <= 1'b0;
    end else begin
      data_mem_valid <= data_req;
    end
  end
  
  assign data_rvalid = data_mem_valid;
  assign data_rdata = data_mem_rdata;
  
  // Data memory instance - 32-bit word array (BRAM-friendly)
  // Use 4 separate byte-wide BRAMs for byte-enable support
  (* ram_style = "block" *) logic [7:0] data_mem_byte0 [0:MEM_WORDS-1];
  (* ram_style = "block" *) logic [7:0] data_mem_byte1 [0:MEM_WORDS-1];
  (* ram_style = "block" *) logic [7:0] data_mem_byte2 [0:MEM_WORDS-1];
  (* ram_style = "block" *) logic [7:0] data_mem_byte3 [0:MEM_WORDS-1];
  
  logic [MEM_ADDR_WIDTH-3:0] data_word_addr;
  assign data_word_addr = data_mem_addr[MEM_ADDR_WIDTH-1:2];
  
  // Read operation - BRAM inference pattern
  always_ff @(posedge clk_i) begin
    if (data_req && !data_we) begin
      data_mem_rdata_word[7:0]   <= data_mem_byte0[data_word_addr];
      data_mem_rdata_word[15:8]  <= data_mem_byte1[data_word_addr];
      data_mem_rdata_word[23:16] <= data_mem_byte2[data_word_addr];
      data_mem_rdata_word[31:24] <= data_mem_byte3[data_word_addr];
    end
  end
  
  assign data_mem_rdata = data_mem_rdata_word;
  
  // Write operation - BRAM inference pattern with byte enables
  always_ff @(posedge clk_i) begin
    if (data_req && data_we) begin
      if (data_be[0]) data_mem_byte0[data_word_addr] <= data_wdata[7:0];
      if (data_be[1]) data_mem_byte1[data_word_addr] <= data_wdata[15:8];
      if (data_be[2]) data_mem_byte2[data_word_addr] <= data_wdata[23:16];
      if (data_be[3]) data_mem_byte3[data_word_addr] <= data_wdata[31:24];
    end
  end
  
  // Initialize data memory
  initial begin
    integer i;
    for (i = 0; i < MEM_WORDS; i = i + 1) begin
      data_mem_byte0[i] = 8'h00;
      data_mem_byte1[i] = 8'h00;
      data_mem_byte2[i] = 8'h00;
      data_mem_byte3[i] = 8'h00;
    end
  end

endmodule


# Controller FSM 和 PC Target 模块的 Zc 扩展优化方案

## 模块功能说明

### 1. cv32e40x_controller_fsm（控制器状态机）

**功能**: 处理器的核心控制器，负责：
- 流水线控制（halt, kill, stall）
- PC 跳转控制（异常、中断、跳转、分支）
- 调试模式控制
- 中断和异常处理

**与 Zcmt 相关的功能**:
表跳转需要**两阶段跳转**：
1. **阶段 1**: 从 `JVT_BASE + (index << 2)` 位置取指针 (使用 `PC_TBLJUMP`)
2. **阶段 2**: 跳转到取到的指针地址 (使用 `PC_POINTER`)

```systemverilog
// rtl/cv32e40x_controller_fsm.sv (第1015-1018行)
ctrl_fsm_o.pc_mux = if_id_pipe_i.instr_meta.tbljmp && !if_id_pipe_i.last_op ? PC_TBLJUMP :
                    if_id_pipe_i.instr_meta.tbljmp && if_id_pipe_i.last_op  ? PC_POINTER : 
                    PC_JUMP;
ctrl_fsm_o.pc_set_tbljmp = if_id_pipe_i.instr_meta.tbljmp && !if_id_pipe_i.last_op;
```

### 2. cv32e40x_pc_target（PC 目标计算）

**功能**: 计算跳转/分支的目标地址，支持：
- **JAL**: `PC + UJ_immediate`
- **JALR**: `rs1 + I_immediate`
- **Branch**: `PC + SB_immediate`
- **Table Jump (Zcmt)**: `JVT_BASE + (index << 2)` ← **Zcmt 特有**

```systemverilog
// rtl/cv32e40x_pc_target.sv (第45-53行)
always_comb begin : pc_target_mux
  unique case (bch_jmp_mux_sel_i)
    CT_TBLJMP: pc_target = {jvt_addr_i, {(32-JVT_ADDR_WIDTH){1'b0}}} + {22'd0, jvt_index_i, 2'b00};
    CT_JAL:    pc_target = pc_id_i   + imm_uj_type_i;
    CT_BCH:    pc_target = pc_id_i   + imm_sb_type_i;
    CT_JALR:   pc_target = jalr_fw_i + imm_i_type_i;
    default:   pc_target = jalr_fw_i + imm_i_type_i;
  endcase
end
```

## PC Mux 枚举类型说明

```systemverilog
// rtl/include/cv32e40x_pkg.sv (第921-936行)
typedef enum logic[3:0] {
  PC_BOOT       = 4'b0000,  // 启动地址
  PC_MRET       = 4'b0001,  // 从异常/中断返回
  PC_DRET       = 4'b0010,  // 从调试模式返回
  PC_JUMP       = 4'b0100,  // JAL/JALR 跳转
  PC_BRANCH     = 4'b0101,  // 分支指令
  PC_WB_PLUS4   = 4'b0110,  // WB 阶段 PC+4
  PC_TRAP_EXC   = 4'b1000,  // 异常陷入
  PC_TRAP_IRQ   = 4'b1001,  // 中断陷入
  PC_TRAP_DBD   = 4'b1010,  // 调试陷入
  PC_TRAP_DBE   = 4'b1011,  // 调试异常
  PC_TRAP_NMI   = 4'b1100,  // NMI 陷入
  PC_TRAP_CLICV = 4'b1101,  // CLIC 向量化中断
  PC_POINTER    = 4'b1110,  // 指针跳转 (CLIC + Zcmt)
  PC_TBLJUMP    = 4'b1111   // 表跳转第一阶段 (Zcmt)
} pc_mux_e;
```

**关键点**:
- `PC_POINTER` 用于 **CLIC 和 Zcmt**（共享）
- `PC_TBLJUMP` **仅用于 Zcmt**

## 表跳转流程详解

### Zcmt 表跳转 (cm.jt / cm.jalt) 的完整流程

```
指令: cm.jt index

第一周期 (第一阶段):
├─ Sequencer 检测到表跳转指令
├─ 设置 instr_meta.tbljmp = 1
├─ last_op = 0 (第一操作)
├─ Controller FSM 设置:
│  ├─ pc_mux = PC_TBLJUMP
│  ├─ pc_set = 1
│  └─ pc_set_tbljmp = 1
├─ IF Stage 使用 PC_TBLJUMP:
│  └─ branch_addr_n = jump_target_id_i
│      └─ 来自 ID Stage 的 pc_target 模块
│          └─ CT_TBLJMP: JVT_BASE + (index << 2)
└─ 结果: 从 JVT 表中取出 32-bit 指针

第二周期 (第二阶段):
├─ 取到的数据作为指针 (ptr)
├─ last_op = 1 (最后操作)
├─ Controller FSM 设置:
│  ├─ pc_mux = PC_POINTER
│  └─ pc_set = 1
├─ IF Stage 使用 PC_POINTER:
│  └─ branch_addr_n = if_id_pipe_o.ptr
└─ 结果: 跳转到指针指向的地址
```

## Zc 扩展优化策略

### 问题分析

1. **PC_POINTER 不能移除**: 
   - CLIC 功能也需要 `PC_POINTER`
   - 即使禁用 Zcmt，CLIC 仍可能启用

2. **PC_TBLJUMP 可以条件化**:
   - **仅 Zcmt 使用**
   - 禁用 Zcmt 时可完全移除

3. **CT_TBLJMP 可以条件化**:
   - PC target 计算中的表跳转分支
   - 包含一个 32-bit 加法器

### 优化方案 1: Controller FSM 条件化（推荐）

```systemverilog
// rtl/cv32e40x_controller_fsm.sv
module cv32e40x_controller_fsm #(
  parameter bit          X_EXT         = 0,
  parameter bit          DEBUG         = 1,
  parameter bit          CLIC          = 0,
  parameter int unsigned CLIC_ID_WIDTH = 5,
  parameter rv32_e       RV32          = RV32I,
  parameter zc_ext_e     ZC_EXT        = ZC_NONE  // 新增参数
)
(
  // ... 端口声明
);

  // 在跳转/分支处理逻辑中
  always_comb begin
    // ... 其他逻辑
    
    if (jump_in_id || branch_in_id) begin
      if (!debug_mode_q && !ctrl_fsm_o.debug_mode) begin
        
        // 表跳转处理 - 条件化
        if (`ZC_HAS_ZCMT(ZC_EXT)) begin
          // Zcmt 启用: 支持两阶段表跳转
          ctrl_fsm_o.pc_mux = if_id_pipe_i.instr_meta.tbljmp && !if_id_pipe_i.last_op ? PC_TBLJUMP :
                              if_id_pipe_i.instr_meta.tbljmp && if_id_pipe_i.last_op  ? PC_POINTER : 
                              PC_JUMP;
          ctrl_fsm_o.pc_set        = 1'b1;
          ctrl_fsm_o.pc_set_tbljmp = if_id_pipe_i.instr_meta.tbljmp && !if_id_pipe_i.last_op;
        end else begin
          // Zcmt 禁用: 只有常规跳转
          // 注意: instr_meta.tbljmp 应该永远为 0（sequencer 已禁用）
          ctrl_fsm_o.pc_mux = PC_JUMP;
          ctrl_fsm_o.pc_set = 1'b1;
          ctrl_fsm_o.pc_set_tbljmp = 1'b0;
        end
        
        branch_taken_n = 1'b1;
      end
    end
    
    // ... 其他逻辑
  end

endmodule
```

**优化效果**: 
- 减少 2-3 个 MUX
- 消除 `pc_set_tbljmp` 信号生成逻辑
- 约 **10-20 gates**

### 优化方案 2: PC Target 模块条件化（可选，收益较大）

#### 方案 2A: 条件化加法器逻辑

```systemverilog
// rtl/cv32e40x_pc_target.sv
module cv32e40x_pc_target import cv32e40x_pkg::*;
#(
  parameter zc_ext_e ZC_EXT = ZC_NONE  // 新增参数
)
(
  input  bch_jmp_mux_e               bch_jmp_mux_sel_i,
  input  logic [31:0]                pc_id_i,
  input  logic [31:0]                imm_uj_type_i,
  input  logic [31:0]                imm_sb_type_i,
  input  logic [31:0]                imm_i_type_i,
  input  logic [31:0]                jalr_fw_i,
  input  logic [JVT_ADDR_WIDTH-1:0]  jvt_addr_i,
  input  logic [7:0]                 jvt_index_i,
  output logic [31:0]                bch_target_o,
  output logic [31:0]                jmp_target_o
);

  logic [31:0] pc_target;

  assign bch_target_o = pc_target;
  assign jmp_target_o = pc_target;

  always_comb begin : pc_target_mux
    unique case (bch_jmp_mux_sel_i)
      CT_TBLJMP: begin
        if (`ZC_HAS_ZCMT(ZC_EXT)) begin
          // 表跳转地址计算: JVT_BASE + (index << 2)
          pc_target = {jvt_addr_i, {(32-JVT_ADDR_WIDTH){1'b0}}} + {22'd0, jvt_index_i, 2'b00};
        end else begin
          // 不应到达此分支（sequencer 已禁用）
          pc_target = '0;
        end
      end
      CT_JAL:    pc_target = pc_id_i   + imm_uj_type_i;
      CT_BCH:    pc_target = pc_id_i   + imm_sb_type_i;
      CT_JALR:   pc_target = jalr_fw_i + imm_i_type_i;
      default:   pc_target = jalr_fw_i + imm_i_type_i;
    endcase
  end

endmodule
```

**优化效果**: 
- 综合工具可能优化掉未使用的加法器逻辑
- 约 **5-10 gates**（取决于综合工具）

#### 方案 2B: 完全移除 CT_TBLJMP 分支（激进）

```systemverilog
// rtl/cv32e40x_pc_target.sv
module cv32e40x_pc_target import cv32e40x_pkg::*;
#(
  parameter zc_ext_e ZC_EXT = ZC_NONE
)
(
  // ... 端口
);

  logic [31:0] pc_target;
  
  generate
    if (`ZC_HAS_ZCMT(ZC_EXT)) begin : gen_with_tbljmp
      // 支持表跳转
      always_comb begin : pc_target_mux
        unique case (bch_jmp_mux_sel_i)
          CT_TBLJMP: pc_target = {jvt_addr_i, {(32-JVT_ADDR_WIDTH){1'b0}}} + {22'd0, jvt_index_i, 2'b00};
          CT_JAL:    pc_target = pc_id_i   + imm_uj_type_i;
          CT_BCH:    pc_target = pc_id_i   + imm_sb_type_i;
          CT_JALR:   pc_target = jalr_fw_i + imm_i_type_i;
          default:   pc_target = jalr_fw_i + imm_i_type_i;
        endcase
      end
    end else begin : gen_no_tbljmp
      // 无表跳转支持
      always_comb begin : pc_target_mux
        unique case (bch_jmp_mux_sel_i)
          // CT_TBLJMP 分支不存在
          CT_JAL:    pc_target = pc_id_i   + imm_uj_type_i;
          CT_BCH:    pc_target = pc_id_i   + imm_sb_type_i;
          CT_JALR:   pc_target = jalr_fw_i + imm_i_type_i;
          default:   pc_target = jalr_fw_i + imm_i_type_i;
        endcase
      end
    end
  endgenerate

  assign bch_target_o = pc_target;
  assign jmp_target_o = pc_target;

endmodule
```

**优化效果**: 
- 完全移除表跳转加法器和 MUX 分支
- 约 **20-40 gates**（32-bit 加法器 + MUX）

**注意**: 需要确保 `bch_jmp_mux_sel_i` 永远不会是 `CT_TBLJMP`（通过 decoder 保证）

### 优化方案 3: IF Stage PC MUX 条件化（可选）

```systemverilog
// rtl/cv32e40x_if_stage.sv
module cv32e40x_if_stage #(
  parameter zc_ext_e ZC_EXT = ZC_NONE,
  // ... 其他参数
)
(
  // ... 端口
);

  always_comb begin
    branch_addr_n = {boot_addr_i[31:2], 2'b0};

    unique case (ctrl_fsm_i.pc_mux)
      PC_BOOT:       branch_addr_n = {boot_addr_i[31:2], 2'b0};
      PC_JUMP:       branch_addr_n = jump_target_id_i;
      PC_BRANCH:     branch_addr_n = branch_target_ex_i;
      PC_MRET:       branch_addr_n = {mepc_i[31:2], (mepc_i[1] & !ctrl_fsm_i.pc_set_clicv), mepc_i[0]};
      PC_DRET:       branch_addr_n = dpc_i;
      PC_WB_PLUS4:   branch_addr_n = ctrl_fsm_i.pipe_pc;
      PC_TRAP_EXC:   branch_addr_n = {mtvec_addr_i, 7'h0};
      PC_TRAP_IRQ:   branch_addr_n = {mtvec_addr_i, ctrl_fsm_i.mtvec_pc_mux, 2'b00};
      PC_TRAP_DBD:   branch_addr_n = {dm_halt_addr_i[31:2], 2'b0};
      PC_TRAP_DBE:   branch_addr_n = {dm_exception_addr_i[31:2], 2'b0};
      PC_TRAP_NMI:   branch_addr_n = {mtvec_addr_i, ctrl_fsm_i.nmi_mtvec_index, 2'b00};
      PC_TRAP_CLICV: branch_addr_n = {mtvt_addr_i, ctrl_fsm_i.mtvt_pc_mux[CLIC_MUX_WIDTH-1:0], 2'b00};
      PC_POINTER:    branch_addr_n = if_id_pipe_o.ptr;  // CLIC + Zcmt 共用
      
      PC_TBLJUMP: begin
        if (`ZC_HAS_ZCMT(ZC_EXT)) begin
          branch_addr_n = jump_target_id_i;  // 表跳转复用 jump_target
        end else begin
          branch_addr_n = '0;  // 不应到达
        end
      end
      
      default:;
    endcase
  end

endmodule
```

**优化效果**: 
- 可能减少 1 个 MUX 输入
- 约 **2-5 gates**

## ID Decoder 中的条件化

```systemverilog
// rtl/cv32e40x_i_decoder.sv
module cv32e40x_i_decoder #(
  parameter zc_ext_e ZC_EXT = ZC_NONE,
  // ...
)
(
  // ...
  input  logic tbljmp_i,  // 来自 sequencer
  // ...
);

  always_comb begin
    // JAL 指令解码
    OPCODE_JAL: begin
      // ...
      
      if (`ZC_HAS_ZCMT(ZC_EXT) && tbljmp_i) begin
        // 表跳转: 使用 CT_TBLJMP 选择器
        decoder_ctrl_o.bch_jmp_mux_sel = CT_TBLJMP;
      end else begin
        // 常规 JAL
        decoder_ctrl_o.bch_jmp_mux_sel = CT_JAL;
      end
    end
  end

endmodule
```

## 完整优化流程图

```
禁用 Zcmt (ZC_EXT[3] = 0):
  
  ┌─────────────────────────────────────┐
  │ Sequencer (不实例化)                │
  │ - seq_tbljmp = 0                    │
  │ - instr_meta.tbljmp = 0             │
  └─────────────────────────────────────┘
                  ↓
  ┌─────────────────────────────────────┐
  │ ID Decoder                          │
  │ - tbljmp_i = 0                      │
  │ - bch_jmp_mux_sel != CT_TBLJMP      │
  └─────────────────────────────────────┘
                  ↓
  ┌─────────────────────────────────────┐
  │ PC Target                           │
  │ - CT_TBLJMP 分支不执行 (或移除)    │
  │ - 表跳转加法器被优化掉              │
  └─────────────────────────────────────┘
                  ↓
  ┌─────────────────────────────────────┐
  │ Controller FSM                      │
  │ - PC_TBLJUMP 不被设置               │
  │ - pc_set_tbljmp = 0                 │
  └─────────────────────────────────────┘
                  ↓
  ┌─────────────────────────────────────┐
  │ IF Stage                            │
  │ - PC_TBLJUMP 分支不执行             │
  └─────────────────────────────────────┘
```

## 信号依赖分析

### Zcmt 相关信号流

```
JVT CSR (cs_registers)
  ├─ jvt_addr[JVT_ADDR_WIDTH-1:0] ──→ PC Target 模块
  └─ jvt_mode[5:0] ──→ Sequencer

Sequencer
  ├─ seq_tbljmp ──→ IF Stage (instr_meta.tbljmp)
  └─ (处理 cm.jt/cm.jalt 指令)

IF Stage
  └─ instr_meta.tbljmp ──→ ID Stage

ID Stage
  ├─ tbljmp_first = instr_meta.tbljmp && !last_op
  ├─ jvt_index[7:0] = instr[19:12]
  └─ bch_jmp_mux_sel = CT_TBLJMP (if tbljmp)

PC Target
  └─ CT_TBLJMP: JVT_BASE + (index << 2)

Controller FSM
  └─ PC_TBLJUMP / PC_POINTER 选择
```

### 禁用 Zcmt 后的信号处理

```systemverilog
// 方案 A: 提供默认值
if (!`ZC_HAS_ZCMT(ZC_EXT)) begin
  assign jvt_addr_o = '0;
  assign jvt_mode_o = '0;
end

// 方案 B: 使用 generate 块（推荐）
generate
  if (`ZC_HAS_ZCMT(ZC_EXT)) begin
    // 正常实例化 JVT CSR
  end else begin
    assign jvt_addr_o = '0;
    assign jvt_mode_o = '0;
  end
endgenerate
```

## 参数传递链

```
cv32e40x_core (ZC_EXT)
  ├─→ cv32e40x_if_stage (ZC_EXT)
  │    ├─→ cv32e40x_sequencer (ZC_EXT)
  │    └─→ cv32e40x_compressed_decoder (ZC_EXT)
  │
  ├─→ cv32e40x_id_stage (ZC_EXT)
  │    ├─→ cv32e40x_decoder (ZC_EXT)
  │    │    ├─→ cv32e40x_i_decoder (ZC_EXT)
  │    │    └─→ (其他 decoder)
  │    └─→ cv32e40x_pc_target (ZC_EXT)
  │
  ├─→ cv32e40x_controller (ZC_EXT)
  │    └─→ cv32e40x_controller_fsm (ZC_EXT)
  │
  └─→ cv32e40x_cs_registers (ZC_EXT)
```

## 实施优先级

### 第一优先级（必须）
1. ✅ Sequencer 条件实例化（已存在 generate 块）
2. ✅ JVT CSR 条件实例化
3. ✅ Controller FSM 表跳转逻辑条件化
4. ✅ ID Decoder 条件化 CT_TBLJMP

### 第二优先级（推荐）
5. ⚠️ PC Target 模块条件化（方案 2A 或 2B）

### 第三优先级（可选）
6. ⚪ IF Stage PC MUX 条件化

## 资源节省估算

| 优化项 | 硬件节省 | 实施难度 |
|--------|---------|---------|
| Sequencer 不实例化 | ~300-400 gates | 低（已存在） |
| JVT CSR 不实例化 | ~40-50 gates | 低 |
| Controller FSM 逻辑简化 | ~10-20 gates | 低 |
| PC Target 条件化（方案2A） | ~5-10 gates | 低 |
| PC Target 完全移除（方案2B） | ~20-40 gates | 中 |
| ID Decoder 条件化 | ~5 gates | 低 |
| **总计** | **~380-525 gates** | - |

## 测试要点

1. **参数化测试**:
   ```systemverilog
   // 测试 ZC_EXT = ZC_ZCA（无 Zcmt）
   // 验证：
   // - cm.jt/cm.jalt 产生非法指令异常
   // - JVT CSR 访问产生非法指令异常
   // - PC_TBLJUMP 永远不被设置
   ```

2. **断言检查**:
   ```systemverilog
   // 当 Zcmt 禁用时
   assert property (@(posedge clk) 
     !`ZC_HAS_ZCMT(ZC_EXT) |-> (ctrl_fsm_o.pc_mux != PC_TBLJUMP))
     else $error("PC_TBLJUMP set when Zcmt disabled");
   ```

3. **综合检查**:
   - 确认 CT_TBLJMP 分支被优化
   - 确认表跳转加法器不存在

## 总结

### Controller FSM 处理建议
- ✅ 添加 `ZC_EXT` 参数
- ✅ 条件化表跳转逻辑（第 1015-1018 行）
- ✅ 使用 `if (`ZC_HAS_ZCMT(ZC_EXT))` 包裹

### PC Target 处理建议
- ✅ 添加 `ZC_EXT` 参数
- ✅ 推荐方案 2A（条件化逻辑，简单安全）
- ⚠️ 可选方案 2B（完全移除分支，收益更大但需仔细测试）

### 关键点
1. **PC_POINTER 不能移除**（CLIC 也用）
2. **PC_TBLJUMP 可以条件化**（仅 Zcmt 用）
3. **优化收益约 15-60 gates**（相比 Sequencer 的 300+ gates 较小）
4. **实施难度低**，风险小

这两个模块的优化属于"锦上添花"，主要收益来自 Sequencer 和 JVT CSR 的条件实例化。


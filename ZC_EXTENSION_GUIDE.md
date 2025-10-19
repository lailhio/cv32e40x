# CV32E40X Zc 扩展可配置化指南

## 概述

当前 CV32E40X 处理器核心中，**Zc 扩展（包括 Zca、Zcb、Zcmp、Zcmt）是始终启用的**（always enabled），通过硬编码参数 `ZC_EXT = 1`。本指南将帮助你实现对 Zc 扩展各个部分的可配置支持，以便根据需求选择性地启用或禁用特定子扩展和指令。

## Zc 扩展组成及依赖关系

### 1. **Zca** (基础压缩指令子集)
- **功能**: C 扩展的子集，移除了浮点加载/存储指令
- **依赖**: 无（但依赖基础 C 扩展框架）
- **关键文件**: `cv32e40x_compressed_decoder.sv`
- **包含指令**: 大部分标准压缩指令（c.addi, c.li, c.lui, c.mv, c.add 等）

### 2. **Zcb** (简单操作扩展)
- **功能**: 代码尺寸优化的简单操作指令
- **依赖**: Zca
- **关键文件**: `cv32e40x_compressed_decoder.sv`
- **包含指令**:
  - `c.zext.b` (零扩展字节)
  - `c.sext.b` (符号扩展字节，需要 B_EXT)
  - `c.zext.h` (零扩展半字，需要 B_EXT)
  - `c.sext.h` (符号扩展半字，需要 B_EXT)
  - `c.not` (按位取反)
  - `c.mul` (乘法，需要 M_EXT)
  - `c.lbu`, `c.lhu`, `c.lh`, `c.sb`, `c.sh` (额外的加载/存储指令)

### 3. **Zcmp** (Push/Pop 和双移动扩展)
- **功能**: 函数序言/尾声优化，push/pop 多个寄存器
- **依赖**: Zca
- **关键文件**: 
  - `cv32e40x_sequencer.sv` (序列化器，将指令展开为微操作序列)
  - `cv32e40x_compressed_decoder.sv`
  - `cv32e40x_controller_fsm.sv`
- **包含指令**:
  - `cm.push` (压栈多个寄存器)
  - `cm.pop` (弹栈多个寄存器)
  - `cm.popret` (弹栈并返回)
  - `cm.popretz` (弹栈、清零 a0 并返回)
  - `cm.mva01s` (双寄存器移动 a0,a1 ← s0,s1)
  - `cm.mvsa01` (双寄存器移动 s0,s1 ← a0,a1)

### 4. **Zcmt** (表跳转扩展)
- **功能**: 通过查表实现间接跳转，用于优化 switch 语句
- **依赖**: Zca
- **关键文件**:
  - `cv32e40x_sequencer.sv`
  - `cv32e40x_pc_target.sv`
  - `cv32e40x_cs_registers.sv` (JVT CSR 寄存器)
  - `cv32e40x_if_stage.sv`
  - `cv32e40x_controller_fsm.sv`
- **包含指令**:
  - `cm.jt` (表跳转)
  - `cm.jalt` (表跳转并链接)
- **相关 CSR**: `JVT` (Jump Vector Table 基地址寄存器)

## 当前实现架构

### 核心参数位置
```systemverilog
// rtl/cv32e40x_core.sv (第147行)
localparam bit ZC_EXT = 1;  // 硬编码为始终启用
```

### 关键模块及 Zc 扩展使用位置

1. **压缩指令解码器** (`cv32e40x_compressed_decoder.sv`)
   - 参数: `ZC_EXT`, `B_EXT`, `M_EXT`
   - 实现所有 Zcb 指令的解码
   - 位置: 86-103行 (Zcb 加载/存储), 227-262行 (Zcb 算术操作)

2. **序列化器** (`cv32e40x_sequencer.sv`)
   - 实现 Zcmp 和 Zcmt 指令的多周期序列
   - 关键状态机: `S_IDLE`, `S_PUSH`, `S_POP`, `S_DMOVE`, `S_RA`, `S_SP`, `S_A0`, `S_RET`
   - 指令检测: 160-225行

3. **CSR 寄存器** (`cv32e40x_cs_registers.sv`)
   - JVT 寄存器实现 (Zcmt)
   - 读取逻辑: 352-359行
   - 写入逻辑: 859-863行
   - CSR 实例: 1216-1229行

4. **PC 目标计算** (`cv32e40x_pc_target.sv`)
   - 表跳转地址计算: 47行
   - `CT_TBLJMP`: `pc_target = {jvt_addr_i, ...} + {index, 2'b00}`

5. **控制器 FSM** (`cv32e40x_controller_fsm.sv`)
   - 表跳转的两阶段处理: 1015-1018行
   - 阶段1: 从 JVT 表获取指针
   - 阶段2: 跳转到指针地址

## 实现可配置化的步骤

### 第一步: 定义细粒度配置参数

建议在 `cv32e40x_pkg.sv` 中定义枚举类型：

```systemverilog
// 新增到 cv32e40x_pkg.sv
typedef struct packed {
  logic zca;   // 基础压缩指令
  logic zcb;   // 简单操作
  logic zcmp;  // Push/Pop 和双移动
  logic zcmt;  // 表跳转
} zc_ext_t;

// 或者使用位域参数
typedef enum logic [3:0] {
  ZC_NONE     = 4'b0000,
  ZC_ZCA      = 4'b0001,
  ZC_ZCA_ZCB  = 4'b0011,  // Zcb 依赖 Zca
  ZC_ZCA_ZCMP = 4'b0101,  // Zcmp 依赖 Zca
  ZC_ZCA_ZCMT = 4'b1001,  // Zcmt 依赖 Zca
  ZC_FULL     = 4'b1111   // 全部启用
} zc_ext_e;
```

### 第二步: 修改顶层模块参数

```systemverilog
// rtl/cv32e40x_core.sv
module cv32e40x_core #(
  // ... 其他参数 ...
  parameter zc_ext_e ZC_EXT = ZC_FULL  // 替换硬编码的 localparam
)
```

### 第三步: 各模块适配

#### 3.1 压缩指令解码器 (Zcb)

```systemverilog
// rtl/cv32e40x_compressed_decoder.sv
module cv32e40x_compressed_decoder #(
    parameter zc_ext_e ZC_EXT = ZC_NONE,
    // ...
)

// 在解码逻辑中添加检查
3'b100: begin
  if (ZC_EXT.zcb || (ZC_EXT & 4'b0010)) begin  // 根据参数类型调整
    // Zcb 加载/存储指令
    unique case (instr[12:10])
      3'b000: begin
        // c.lbu
        instr_o.bus_resp.rdata = {...};
      end
      // ...
    endcase
  end else begin
    illegal_instr_o = 1'b1;
  end
end

// c.mul 指令检查
3'b110: begin
  if ((ZC_EXT.zcb) && (M_EXT != M_NONE)) begin
    // c.mul 指令
  end else begin
    illegal_instr_o = 1'b1;
  end
end
```

#### 3.2 序列化器 (Zcmp & Zcmt)

```systemverilog
// rtl/cv32e40x_sequencer.sv
module cv32e40x_sequencer #(
  parameter zc_ext_e ZC_EXT = ZC_NONE,
  // ...
)

// 在指令解码中添加条件
3'b000: begin
  if ((ZC_EXT.zcmt) && !(|jvt_mode_i)) begin
    seq_tbljmp_o = 1'b1;
    seq_instr = TBLJMP;
  end
end

3'b011: begin
  if (ZC_EXT.zcmp) begin
    if (instr[6:5] == 2'b11) begin
      // cm.mva01s
      if (dmove_legal_dest_s2a) begin
        seq_instr = MVA01S;
        seq_move_s2a = 1'b1;
      end
    end
    // ...
  end
end

3'b110: begin
  if (ZC_EXT.zcmp) begin
    if (instr[9:8] == 2'b00) begin
      // cm.push
      // ...
    end
  end
end
```

#### 3.3 CSR 寄存器 (Zcmt - JVT)

```systemverilog
// rtl/cv32e40x_cs_registers.sv
module cv32e40x_cs_registers #(
  parameter zc_ext_e ZC_EXT = ZC_NONE,
  // ...
)

// 读取逻辑
CSR_JVT: begin
  if (ZC_EXT.zcmt) begin
    csr_rdata_int = jvt_rdata;
  end else begin
    csr_rdata_int = '0;
    illegal_csr_read = 1'b1;
  end
end

// 写入逻辑
CSR_JVT: begin
  if (ZC_EXT.zcmt) begin
    jvt_we = 1'b1;
  end
end

// JVT CSR 实例化 - 可以添加 generate 块
generate
  if (ZC_EXT.zcmt) begin : gen_jvt_csr
    cv32e40x_csr #(
      .WIDTH(32),
      .MASK(CSR_JVT_MASK),
      .RESETVALUE(JVT_RESET_VAL)
    ) jvt_csr_i (
      .clk(clk),
      .rst_n(rst_n),
      .wr_data_i(jvt_n),
      .wr_en_i(jvt_we),
      .rd_data_o(jvt_q)
    );
  end else begin : gen_no_jvt
    assign jvt_q = '0;
  end
endgenerate
```

#### 3.4 其他需要修改的文件

1. **`cv32e40x_pc_target.sv`**: 表跳转目标计算
   ```systemverilog
   // 如果 Zcmt 未启用，CT_TBLJMP 分支不应被执行
   // 添加参数检查或在控制逻辑中防止进入此分支
   ```

2. **`cv32e40x_controller_fsm.sv`**: 控制流处理
   ```systemverilog
   // 表跳转相关的 PC 设置逻辑
   // 需要基于 ZC_EXT.zcmt 参数进行条件化
   ```

3. **`cv32e40x_if_stage.sv`**: PC 多路选择器
   ```systemverilog
   // PC_TBLJUMP 和 PC_POINTER 的处理
   ```

### 第四步: 参数验证

在 `cv32e40x_core.sv` 或专门的参数检查模块中添加：

```systemverilog
// 依赖关系检查
initial begin
  if (ZC_EXT.zcb && !ZC_EXT.zca) begin
    $fatal(1, "Zcb 扩展依赖于 Zca，但 Zca 未启用");
  end
  if (ZC_EXT.zcmp && !ZC_EXT.zca) begin
    $fatal(1, "Zcmp 扩展依赖于 Zca，但 Zca 未启用");
  end
  if (ZC_EXT.zcmt && !ZC_EXT.zca) begin
    $fatal(1, "Zcmt 扩展依赖于 Zca，但 Zca 未启用");
  end
end
```

### 第五步: 硬件优化（可选）

对于未启用的扩展，通过 `generate` 块移除不必要的硬件：

```systemverilog
// 序列化器实例化
generate
  if (ZC_EXT.zcmp || ZC_EXT.zcmt) begin : gen_sequencer
    cv32e40x_sequencer #(
      .ZC_EXT(ZC_EXT)
    ) sequencer_i (
      // ...
    );
  end else begin : gen_no_sequencer
    // 提供默认值
    assign seq_valid = 1'b0;
    assign seq_ready = 1'b1;
    // ...
  end
endgenerate

// JVT 相关的加法器和多路选择器
generate
  if (ZC_EXT.zcmt) begin : gen_tbljmp_logic
    // 表跳转地址计算硬件
  end
endgenerate
```

## 指令级别的细粒度控制

如果需要更细粒度的控制（禁用单个指令），可以：

1. **定义指令位掩码**:
```systemverilog
typedef struct packed {
  // Zcb 指令
  logic c_lbu;
  logic c_lhu;
  logic c_lh;
  logic c_sb;
  logic c_sh;
  logic c_zext_b;
  logic c_sext_b;
  logic c_zext_h;
  logic c_sext_h;
  logic c_not;
  logic c_mul;
  
  // Zcmp 指令
  logic cm_push;
  logic cm_pop;
  logic cm_popret;
  logic cm_popretz;
  logic cm_mva01s;
  logic cm_mvsa01;
  
  // Zcmt 指令
  logic cm_jt;
  logic cm_jalt;
} zc_instr_mask_t;
```

2. **在解码器中使用**:
```systemverilog
parameter zc_instr_mask_t ZC_INSTR_MASK = '1;  // 默认全部启用

// 解码逻辑
3'b000: begin
  if (ZC_INSTR_MASK.c_lbu) begin
    // c.lbu 指令
  end else begin
    illegal_instr_o = 1'b1;
  end
end
```

## 需要修改的文件清单

### 核心功能文件 (必须修改)
1. ✅ `rtl/include/cv32e40x_pkg.sv` - 添加新的参数类型定义
2. ✅ `rtl/cv32e40x_core.sv` - 将 ZC_EXT 改为可配置参数
3. ✅ `rtl/cv32e40x_compressed_decoder.sv` - Zcb 指令条件化
4. ✅ `rtl/cv32e40x_sequencer.sv` - Zcmp/Zcmt 指令条件化
5. ✅ `rtl/cv32e40x_cs_registers.sv` - JVT CSR 条件化
6. ✅ `rtl/cv32e40x_pc_target.sv` - 表跳转地址计算条件化
7. ✅ `rtl/cv32e40x_controller_fsm.sv` - 表跳转控制流条件化
8. ✅ `rtl/cv32e40x_if_stage.sv` - PC 选择逻辑条件化
9. ✅ `rtl/cv32e40x_id_stage.sv` - 表跳转相关信号处理

### 验证和测试文件 (建议修改)
10. ⚠️ `sva/cv32e40x_sequencer_sva.sv` - 序列化器断言
11. ⚠️ `sva/cv32e40x_parameter_sva.sv` - 参数合法性检查
12. ⚠️ `bhv/cv32e40x_rvfi.sv` - RVFI 追踪接口 (JVT CSR)

### 文档文件 (需更新)
13. 📄 `docs/user_manual/source/intro.rst` - 更新配置说明
14. 📄 `docs/user_manual/source/integration.rst` - 更新集成参数表
15. 📄 `docs/user_manual/source/control_status_registers.rst` - JVT CSR 文档

## 测试策略

1. **参数组合测试**:
   - `ZC_NONE`: 完全禁用，所有 Zc 指令应报非法指令
   - `ZC_ZCA`: 仅 Zca，Zcb/Zcmp/Zcmt 指令应报非法
   - `ZC_ZCA_ZCB`: Zca + Zcb
   - `ZC_ZCA_ZCMP`: Zca + Zcmp
   - `ZC_ZCA_ZCMT`: Zca + Zcmt
   - `ZC_FULL`: 全部启用

2. **面积和时序分析**:
   - 综合各配置，对比资源使用
   - 确认未使用的硬件被正确优化掉

3. **功能回归测试**:
   - 确保现有测试在 `ZC_FULL` 配置下通过
   - 添加针对各配置的专门测试

## 推荐实施顺序

1. **阶段 1**: 定义参数和基础框架
   - 在 `cv32e40x_pkg.sv` 中定义 `zc_ext_e` 类型
   - 修改 `cv32e40x_core.sv` 将 `ZC_EXT` 改为参数
   - 添加参数验证逻辑

2. **阶段 2**: Zcmt 可配置化（相对独立）
   - 修改 JVT CSR 相关逻辑
   - 修改表跳转相关的 PC 计算和控制流
   - 在序列化器中条件化 `cm.jt`/`cm.jalt`

3. **阶段 3**: Zcmp 可配置化
   - 在序列化器中条件化 push/pop/move 指令
   - 可选：用 generate 块移除序列化器硬件

4. **阶段 4**: Zcb 可配置化
   - 在压缩解码器中条件化 Zcb 指令

5. **阶段 5**: 硬件优化
   - 添加 generate 块移除未使用的硬件
   - 综合和面积分析

6. **阶段 6**: 测试和文档
   - 完整的回归测试
   - 更新用户手册

## 示例：Zcmt 独立禁用

如果你只想禁用 Zcmt（表跳转），最小化修改如下：

```systemverilog
// 1. cv32e40x_core.sv
parameter bit ZCMT_EXT = 1;  // 新增参数
localparam bit ZC_EXT = 1;   // 保持现有

// 2. cv32e40x_sequencer.sv
3'b000: begin
  if (ZCMT_EXT && !(|jvt_mode_i)) begin
    seq_tbljmp_o = 1'b1;
    // ...
  end
end

// 3. cv32e40x_cs_registers.sv
CSR_JVT: begin
  if (ZCMT_EXT) begin
    csr_rdata_int = jvt_rdata;
  end else begin
    illegal_csr_read = 1'b1;
  end
end
```

## 潜在问题和注意事项

1. **信号未定义**: 禁用某个扩展后，相关信号可能未定义，需要提供默认值
2. **控制流死锁**: 确保禁用的指令不会进入相关的控制流状态
3. **CSR 访问**: 禁用 Zcmt 后，JVT CSR 访问应触发非法指令异常
4. **序列化器复杂性**: Zcmp 和 Zcmt 共享序列化器，需仔细处理状态机
5. **工具链兼容性**: 确保编译器/汇编器知道哪些扩展被启用/禁用

## 参考资料

- **Zc 规范**: `docs/user_manual/source/intro.rst` 第54行引用的规范文档
- **当前实现状态**: 第123-137行说明 Zca/Zcb/Zcmp/Zcmt "always enabled"
- **序列化器实现**: `rtl/cv32e40x_sequencer.sv` 完整实现
- **包定义**: `rtl/include/cv32e40x_pkg.sv` 第1565-1667行 Zc 相关定义

---

## 快速参考：关键代码位置

| 功能 | 文件 | 行号 |
|------|------|------|
| ZC_EXT 参数定义 | `cv32e40x_core.sv` | 147 |
| Zcb 加载/存储解码 | `cv32e40x_compressed_decoder.sv` | 86-103 |
| Zcb 算术操作解码 | `cv32e40x_compressed_decoder.sv` | 227-262 |
| Zcmp push/pop 解码 | `cv32e40x_sequencer.sv` | 186-217 |
| Zcmt 表跳转解码 | `cv32e40x_sequencer.sv` | 163-167 |
| JVT CSR 读取 | `cv32e40x_cs_registers.sv` | 352-359 |
| JVT CSR 写入 | `cv32e40x_cs_registers.sv` | 859-863 |
| 表跳转地址计算 | `cv32e40x_pc_target.sv` | 47 |
| 表跳转控制流 | `cv32e40x_controller_fsm.sv` | 1015-1018 |
| Zc 类型定义 | `cv32e40x_pkg.sv` | 1565-1667 |

---

*本指南基于 CV32E40X 代码库的当前状态编写。实施时请根据具体需求调整。*


# CV32E40X Vivado 项目创建指南

本指南说明如何使用 TCL 脚本一键创建 CV32E40X RISC-V 核的 Vivado 项目。

## 📋 前提条件

- 已安装 Vivado (推荐 2020.1 或更高版本)
- Vivado 已添加到系统 PATH

## 🚀 快速开始

### 方法 1：使用 TCL 脚本（推荐）

```bash
# 在项目根目录下执行
vivado -mode batch -source create_vivado_project.tcl
```

或者在 Vivado TCL Shell 中执行：

```bash
vivado -mode tcl -source create_vivado_project.tcl
```

### 方法 2：使用快速启动脚本

```bash
# 赋予执行权限
chmod +x vivado_quick_start.sh

# 运行脚本
./vivado_quick_start.sh
```

## 🎯 目标 FPGA 配置

默认目标器件是 **Artix-7 (xc7a35ticsg324-1L)**。

如需更改目标器件，编辑 `create_vivado_project.tcl` 中的以下行：

```tcl
set fpga_part "xc7a35ticsg324-1L"
```

常用 FPGA 型号：

| FPGA 系列 | 器件型号 | 说明 |
|-----------|---------|------|
| Artix-7 | `xc7a35ticsg324-1L` | 小型低功耗 FPGA |
| Artix-7 | `xc7a100tcsg324-1` | 中等规模 FPGA |
| Kintex-7 | `xc7k325tffg900-2` | 高性能 FPGA |
| Zynq-7000 | `xc7z020clg400-1` | SoC (ARM + FPGA) |
| Zynq UltraScale+ | `xczu9eg-ffvb1156-2-e` | 高端 SoC |

## 📌 重要说明：FPGA 顶层模块

**默认顶层模块：`cv32e40x_fpga_top`**

本项目提供了一个 FPGA 友好的顶层包装器模块 `cv32e40x_fpga_top.sv`，该模块：
- ✅ 集成了片上 BRAM 用于指令和数据存储（64KB）
- ✅ 简化了外部接口，仅需 **约20个I/O引脚**（适合小封装FPGA）
- ✅ 内置简单测试程序
- ✅ 提供状态LED输出用于调试

**I/O引脚数量对比：**
- `cv32e40x_core`（CPU核心）：~723个信号（不适合直接作为顶层）
- `cv32e40x_fpga_top`（FPGA包装器）：20个信号（适合小型FPGA）

如果您遇到 **"IO Placement failed due to overutilization"** 错误，说明使用了错误的顶层模块。请确保：
1. 使用 `cv32e40x_fpga_top` 作为顶层模块（脚本已默认配置）
2. 根据您的开发板修改 `constraints/cv32e40x_fpga_top.xdc` 中的引脚定义

## 📁 项目结构

脚本会创建以下项目结构：

```
cv32e40x/
├── create_vivado_project.tcl    # Vivado 项目创建脚本
├── vivado_quick_start.sh         # 快速启动脚本
├── vivado_project/               # Vivado 项目目录（脚本生成）
│   ├── cv32e40x_project.xpr     # Vivado 项目文件
│   ├── cv32e40x_project.cache/
│   ├── cv32e40x_project.hw/
│   ├── cv32e40x_project.sim/
│   └── cv32e40x_project.srcs/
├── rtl/                          # RTL 源文件
│   ├── include/
│   │   └── cv32e40x_pkg.sv      # Package 定义
│   ├── cv32e40x_core.sv         # 顶层模块
│   └── *.sv                      # 其他 RTL 文件
└── constraints/                  # 约束文件
    └── cv32e40x_core.sdc        # 时序约束
```

## ⚙️ 核心参数配置

CV32E40X 核支持多种可配置参数。在 TCL 脚本中可以设置这些参数：

```tcl
set_property generic {
    RV32=1              # RV32I 或 RV32E
    A_EXT=0             # Atomic 扩展
    B_EXT=0             # Bit manipulation 扩展
    M_EXT=1             # Multiply/Divide 扩展
    ZC_EXT=1            # Compressed 扩展 (Zca/Zcb/Zcmp/Zcmt)
} [current_fileset]
```

### ZC_EXT 压缩指令扩展配置

根据你的需求选择：

| 值 | 配置 | 说明 |
|----|------|------|
| `ZC_NONE` (0) | 无压缩指令 | 节省硬件资源 |
| `ZC_ZCA` (1) | 基础 Zca | 标准 16-bit 压缩指令 |
| `ZC_ZCA_ZCB` (3) | Zca + Zcb | 增加位操作压缩指令 |
| `ZC_ZCA_ZCMP` (5) | Zca + Zcmp | 增加 push/pop 指令 |
| `ZC_FULL` (15) | 全部启用 | Zca+Zcb+Zcmp+Zcmt |

详细信息请参考 `ZCA_EXTENSION_CONTROL_GUIDE.md`。

## 🔧 项目创建后的操作

### 1. 打开项目

```bash
vivado vivado_project/cv32e40x_project.xpr &
```

### 2. 运行综合

在 Vivado GUI 中：
- Flow Navigator → Synthesis → Run Synthesis

或使用 TCL 命令：
```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
```

### 3. 运行实现

```tcl
launch_runs impl_1 -jobs 4
wait_on_run impl_1
```

### 4. 生成比特流

```tcl
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
```

## 📊 资源估计

CV32E40X 核的资源使用（参考值，依配置而异）：

| 配置 | LUTs | FFs | BRAM | DSP |
|------|------|-----|------|-----|
| 最小配置 (无 M/Zc) | ~5K | ~2K | 0 | 0 |
| 标准配置 (M+Zca) | ~8K | ~2.5K | 0 | 0-3 |
| 完整配置 (全部扩展) | ~12K | ~3K | 0 | 0-3 |

## 🐛 常见问题

### 1. 找不到 SystemVerilog 文件

**问题**：`ERROR: File not found`

**解决**：确保在项目根目录（包含 `rtl/` 和 `constraints/` 目录）运行脚本。

### 2. 编译顺序错误

**问题**：`ERROR: Package 'cv32e40x_pkg' not found`

**解决**：脚本已自动处理编译顺序，确保 `cv32e40x_pkg.sv` 最先编译。如仍有问题：

```tcl
update_compile_order -fileset sources_1
```

### 3. 约束文件未加载

**问题**：时序约束未生效

**解决**：
- 检查 `constraints/cv32e40x_core.sdc` 文件是否存在
- 在 Vivado 中手动添加：Flow Navigator → Constraints → Add Sources

### 4. 综合失败

**问题**：综合时出现错误

**解决**：
1. 检查目标 FPGA 是否支持所需资源
2. 查看具体错误信息，可能是参数配置问题
3. 尝试使用更大的 FPGA 器件

## 📝 自定义脚本

### 添加额外的 RTL 文件

在 TCL 脚本中添加：

```tcl
add_files -norecurse -fileset [get_filesets sources_1] /path/to/your/file.sv
set_property file_type "SystemVerilog" [get_files your_file.sv]
```

### 添加 IP 核

```tcl
create_ip -name your_ip_name -vendor xilinx.com -library ip -version 1.0 -module_name your_ip_inst
```

### 修改综合策略

```tcl
set_property strategy "Flow_PerfOptimized_high" [get_runs synth_1]
```

## 🔗 相关文档

- [CV32E40X 用户手册](docs/)
- [Zca 扩展控制指南](ZCA_EXTENSION_CONTROL_GUIDE.md)
- [Zca 控制总结](ZCA_CONTROL_SUMMARY.md)
- [Xilinx Vivado 文档](https://www.xilinx.com/support/documentation/)

## 📧 技术支持

如有问题或建议，请查看：
- GitHub Issues: [cv32e40x repository](https://github.com/openhwgroup/cv32e40x)
- OpenHW Group: https://www.openhwgroup.org/

## 📄 许可证

本项目遵循 Solderpad Hardware License v2.1。详见 [LICENSE](LICENSE) 文件。

---

**祝你使用愉快！🎉**


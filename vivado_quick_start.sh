#!/bin/bash

################################################################################
# Vivado Quick Start Script for CV32E40X
# 
# This script provides an interactive way to create and manage Vivado projects
# for the CV32E40X RISC-V core.
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TCL_SCRIPT="${SCRIPT_DIR}/create_vivado_project.tcl"
PROJECT_DIR="${SCRIPT_DIR}/vivado_project"

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${CYAN}  CV32E40X Vivado 项目快速启动工具${NC}"
    echo -e "${CYAN}=======================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_vivado() {
    if ! command -v vivado &> /dev/null; then
        print_error "未找到 Vivado！"
        echo ""
        echo "请确保："
        echo "  1. Vivado 已安装"
        echo "  2. 已执行 settings64.sh 或 settings64.csh"
        echo "  3. vivado 命令在 PATH 中"
        echo ""
        echo "例如："
        echo "  source /opt/Xilinx/Vivado/2021.2/settings64.sh"
        exit 1
    fi
    
    VIVADO_VERSION=$(vivado -version | head -n 1)
    print_success "找到 Vivado: ${VIVADO_VERSION}"
}

check_files() {
    if [ ! -f "${TCL_SCRIPT}" ]; then
        print_error "未找到 TCL 脚本: ${TCL_SCRIPT}"
        exit 1
    fi
    
    if [ ! -d "${SCRIPT_DIR}/rtl" ]; then
        print_error "未找到 RTL 目录: ${SCRIPT_DIR}/rtl"
        exit 1
    fi
    
    print_success "项目文件检查通过"
}

show_menu() {
    echo ""
    echo -e "${CYAN}请选择操作：${NC}"
    echo "  1) 创建新的 Vivado 项目"
    echo "  2) 创建项目并自动运行综合"
    echo "  3) 打开已有项目"
    echo "  4) 清理项目文件"
    echo "  5) 查看项目信息"
    echo "  6) 配置 FPGA 目标器件"
    echo "  0) 退出"
    echo ""
    echo -n "请输入选项 [0-6]: "
}

create_project() {
    echo ""
    print_info "开始创建 Vivado 项目..."
    echo ""
    
    if [ -d "${PROJECT_DIR}" ]; then
        print_warning "项目目录已存在: ${PROJECT_DIR}"
        echo -n "是否删除并重新创建? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "取消操作"
            return
        fi
    fi
    
    vivado -mode batch -source "${TCL_SCRIPT}"
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "项目创建成功！"
        echo ""
        print_info "项目位置: ${PROJECT_DIR}"
        print_info "打开项目: vivado ${PROJECT_DIR}/cv32e40x_project.xpr"
    else
        print_error "项目创建失败！"
    fi
}

create_and_synthesize() {
    echo ""
    print_info "创建项目并运行综合..."
    echo ""
    
    # Create a modified TCL script that includes synthesis
    TMP_TCL="${SCRIPT_DIR}/create_and_synth.tcl"
    
    cat "${TCL_SCRIPT}" > "${TMP_TCL}"
    cat >> "${TMP_TCL}" << 'EOF'

################################################################################
# Auto-launch synthesis
################################################################################
puts "\n=========================================="
puts "Launching synthesis..."
puts "=========================================="

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
} else {
    puts "\n✓ Synthesis completed successfully!"
    open_run synth_1
    
    # Report utilization
    report_utilization -file ${project_dir}/utilization_synth.txt
    puts "\nUtilization report saved to: ${project_dir}/utilization_synth.txt"
}
EOF
    
    vivado -mode batch -source "${TMP_TCL}"
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "综合完成！"
        print_info "查看报告: ${PROJECT_DIR}/utilization_synth.txt"
    else
        print_error "综合失败！"
    fi
    
    rm -f "${TMP_TCL}"
}

open_project() {
    if [ ! -d "${PROJECT_DIR}" ]; then
        print_error "项目不存在！请先创建项目。"
        return
    fi
    
    PROJECT_FILE="${PROJECT_DIR}/cv32e40x_project.xpr"
    if [ ! -f "${PROJECT_FILE}" ]; then
        print_error "未找到项目文件: ${PROJECT_FILE}"
        return
    fi
    
    print_info "打开 Vivado 项目..."
    vivado "${PROJECT_FILE}" &
    print_success "Vivado 已启动"
}

clean_project() {
    echo ""
    if [ ! -d "${PROJECT_DIR}" ]; then
        print_warning "项目目录不存在"
        return
    fi
    
    print_warning "这将删除整个项目目录！"
    echo -e "目录: ${YELLOW}${PROJECT_DIR}${NC}"
    echo -n "确认删除? [y/N]: "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "${PROJECT_DIR}"
        print_success "项目已清理"
    else
        print_info "取消操作"
    fi
}

show_info() {
    echo ""
    print_info "项目信息"
    echo -e "${CYAN}========================================${NC}"
    echo -e "项目名称:     cv32e40x_project"
    echo -e "项目路径:     ${PROJECT_DIR}"
    echo -e "TCL 脚本:     ${TCL_SCRIPT}"
    echo -e "RTL 目录:     ${SCRIPT_DIR}/rtl"
    echo -e "约束目录:     ${SCRIPT_DIR}/constraints"
    
    if [ -d "${PROJECT_DIR}" ]; then
        print_success "项目状态: 已创建"
        
        # Count files
        RTL_COUNT=$(find "${SCRIPT_DIR}/rtl" -name "*.sv" | wc -l)
        echo -e "RTL 文件数:   ${RTL_COUNT}"
        
        if [ -f "${PROJECT_DIR}/cv32e40x_project.xpr" ]; then
            PROJECT_SIZE=$(du -sh "${PROJECT_DIR}" | cut -f1)
            echo -e "项目大小:     ${PROJECT_SIZE}"
        fi
    else
        print_warning "项目状态: 未创建"
    fi
    echo -e "${CYAN}========================================${NC}"
}

configure_fpga() {
    echo ""
    print_info "配置目标 FPGA 器件"
    echo ""
    echo "常用 FPGA 型号："
    echo "  1) xc7a35ticsg324-1L   (Artix-7 小型)"
    echo "  2) xc7a100tcsg324-1    (Artix-7 中型)"
    echo "  3) xc7k325tffg900-2    (Kintex-7)"
    echo "  4) xc7z020clg400-1     (Zynq-7000)"
    echo "  5) xczu9eg-ffvb1156-2-e (Zynq UltraScale+)"
    echo "  6) 自定义"
    echo ""
    echo -n "请选择 [1-6]: "
    read -r choice
    
    case $choice in
        1) FPGA_PART="xc7a35ticsg324-1L" ;;
        2) FPGA_PART="xc7a100tcsg324-1" ;;
        3) FPGA_PART="xc7k325tffg900-2" ;;
        4) FPGA_PART="xc7z020clg400-1" ;;
        5) FPGA_PART="xczu9eg-ffvb1156-2-e" ;;
        6) 
            echo -n "请输入 FPGA 型号: "
            read -r FPGA_PART
            ;;
        *)
            print_error "无效选项"
            return
            ;;
    esac
    
    print_info "将 FPGA 目标设置为: ${FPGA_PART}"
    
    # Update TCL script
    sed -i.bak "s/^set fpga_part \".*\"/set fpga_part \"${FPGA_PART}\"/" "${TCL_SCRIPT}"
    
    print_success "配置已更新"
    print_warning "请重新创建项目以应用更改"
}

################################################################################
# Main
################################################################################

print_header

# Check prerequisites
check_vivado
check_files

# Main loop
while true; do
    show_menu
    read -r option
    
    case $option in
        1) create_project ;;
        2) create_and_synthesize ;;
        3) open_project ;;
        4) clean_project ;;
        5) show_info ;;
        6) configure_fpga ;;
        0) 
            echo ""
            print_info "退出程序"
            exit 0
            ;;
        *)
            print_error "无效选项，请重新选择"
            ;;
    esac
    
    echo ""
    echo -n "按回车键继续..."
    read -r
done


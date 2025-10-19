#!/bin/bash
# 脚本：将 Zca 扩展控制修改推送到你的 fork

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  CV32E40X Zca 扩展控制分支推送脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. 检查是否在正确的目录
if [ ! -f "rtl/cv32e40x_core.sv" ]; then
    echo -e "${YELLOW}错误：请在 cv32e40x 仓库根目录运行此脚本${NC}"
    exit 1
fi

# 2. 获取用户 GitHub 用户名
echo -e "${GREEN}步骤 1:${NC} 请输入你的 GitHub 用户名："
read GITHUB_USERNAME

if [ -z "$GITHUB_USERNAME" ]; then
    echo -e "${YELLOW}错误：用户名不能为空${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}步骤 2:${NC} 添加你的 fork 作为远程仓库..."
git remote add myfork https://github.com/$GITHUB_USERNAME/cv32e40x.git 2>/dev/null || \
git remote set-url myfork https://github.com/$GITHUB_USERNAME/cv32e40x.git

echo ""
echo -e "${GREEN}步骤 3:${NC} 创建新分支 'feature/zca-extension-control'..."
git checkout -b feature/zca-extension-control

echo ""
echo -e "${GREEN}步骤 4:${NC} 添加所有修改的文件..."
git add rtl/cv32e40x_compressed_decoder.sv
git add rtl/cv32e40x_core.sv
git add rtl/cv32e40x_cs_registers.sv
git add rtl/cv32e40x_if_stage.sv
git add rtl/include/cv32e40x_pkg.sv
git add ZCA_CONTROL_SUMMARY.md
git add ZCA_EXTENSION_CONTROL_GUIDE.md
git add ZC_CONTROLLER_PC_OPTIMIZATION.md
git add ZC_EXTENSION_GUIDE.md

echo ""
echo -e "${GREEN}步骤 5:${NC} 提交修改..."
git commit -m "feat: Add configurable Zca extension control with optional decoder instantiation

- Add ZC_EXT parameter to cv32e40x_core for Zca/Zcb/Zcmp/Zcmt control
- Implement conditional instantiation of compressed decoder in IF stage
- Update MISA.C bit to reflect ZC_EXT configuration dynamically
- Add zc_ext_e enumeration type and control macros
- Create comprehensive documentation for Zca extension control

Key Features:
- When ZC_EXT = ZC_NONE, compressed decoder is not instantiated (saves hardware)
- When ZC_EXT != ZC_NONE, decoder is instantiated with full functionality
- MISA.C bit correctly reports compressed instruction support to software
- Design consistent with sequencer (Zcmp/Zcmt) conditional instantiation

Hardware Savings:
- ZC_NONE: Maximum savings (~400 lines of decoder logic eliminated)
- Optimized timing with direct pass-through path when disabled
- Zero overhead when compression is not needed

Documentation:
- ZCA_EXTENSION_CONTROL_GUIDE.md: Complete design guide
- ZCA_CONTROL_SUMMARY.md: Quick reference and usage examples"

echo ""
echo -e "${GREEN}步骤 6:${NC} 推送到你的 fork..."
echo -e "${YELLOW}注意：你可能需要输入 GitHub 用户名和个人访问令牌（PAT）${NC}"
git push -u myfork feature/zca-extension-control

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ 完成！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "你的分支已推送到："
echo -e "${BLUE}https://github.com/lailhio/cv32e40x/tree/feature/zca-extension-control${NC}"
echo ""
echo -e "接下来你可以："
echo -e "1. 在浏览器中打开上面的链接查看你的分支"
echo -e "2. 如果需要，可以创建 Pull Request 到上游仓库"
echo ""
echo -e "如果要回到 master 分支："
echo -e "  ${YELLOW}git checkout master${NC}"
echo ""


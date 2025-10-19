#!/bin/bash

################################################################################
# Git 代理配置脚本
# 
# 用于快速配置或取消 Git 的代理设置
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PROXY_HTTP="http://10.156.112.157:7890"
PROXY_SOCKS="socks5://10.156.112.157:7890"

show_menu() {
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}  Git 代理配置工具${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo ""
    echo "请选择操作："
    echo "  1) 配置 HTTP/HTTPS 代理"
    echo "  2) 配置 SSH 代理（通过 HTTP）"
    echo "  3) 配置 SSH 代理（通过 SOCKS5）"
    echo "  4) 查看当前代理配置"
    echo "  5) 取消所有代理"
    echo "  6) 测试 GitHub 连接"
    echo "  0) 退出"
    echo ""
    echo -n "请选择 [0-6]: "
}

config_http_proxy() {
    echo ""
    echo -e "${BLUE}配置 HTTP/HTTPS 代理...${NC}"
    echo "代理地址: ${PROXY_HTTP}"
    
    git config --global http.proxy "${PROXY_HTTP}"
    git config --global https.proxy "${PROXY_HTTP}"
    
    echo -e "${GREEN}✓ HTTP/HTTPS 代理已配置${NC}"
    echo ""
    echo "当前配置："
    git config --global --get http.proxy
    git config --global --get https.proxy
}

config_ssh_proxy_http() {
    echo ""
    echo -e "${BLUE}配置 SSH 代理（HTTP CONNECT）...${NC}"
    echo "代理地址: ${PROXY_HTTP}"
    
    mkdir -p ~/.ssh
    
    # 备份原有配置
    if [ -f ~/.ssh/config ]; then
        cp ~/.ssh/config ~/.ssh/config.backup.$(date +%Y%m%d_%H%M%S)
        echo -e "${YELLOW}原配置已备份${NC}"
    fi
    
    # 检查是否安装了 nc (netcat)
    if ! command -v nc &> /dev/null; then
        echo -e "${RED}✗ 未找到 nc (netcat) 命令${NC}"
        echo "请安装: sudo apt-get install netcat-openbsd"
        return 1
    fi
    
    # 添加或更新 GitHub SSH 配置
    cat > ~/.ssh/config << EOF
# GitHub SSH Configuration with HTTP Proxy
Host github.com
    HostName github.com
    User git
    Port 22
    ProxyCommand nc -X connect -x 10.156.112.157:7890 %h %p
EOF
    
    chmod 600 ~/.ssh/config
    echo -e "${GREEN}✓ SSH 代理已配置（HTTP CONNECT）${NC}"
}

config_ssh_proxy_socks() {
    echo ""
    echo -e "${BLUE}配置 SSH 代理（SOCKS5）...${NC}"
    echo "代理地址: ${PROXY_SOCKS}"
    
    mkdir -p ~/.ssh
    
    # 备份原有配置
    if [ -f ~/.ssh/config ]; then
        cp ~/.ssh/config ~/.ssh/config.backup.$(date +%Y%m%d_%H%M%S)
        echo -e "${YELLOW}原配置已备份${NC}"
    fi
    
    # 检查是否安装了 nc
    if ! command -v nc &> /dev/null; then
        echo -e "${RED}✗ 未找到 nc (netcat) 命令${NC}"
        echo "请安装: sudo apt-get install netcat-openbsd"
        return 1
    fi
    
    # 添加或更新 GitHub SSH 配置
    cat > ~/.ssh/config << EOF
# GitHub SSH Configuration with SOCKS5 Proxy
Host github.com
    HostName github.com
    User git
    Port 22
    ProxyCommand nc -X 5 -x 10.156.112.157:7890 %h %p
EOF
    
    chmod 600 ~/.ssh/config
    echo -e "${GREEN}✓ SSH 代理已配置（SOCKS5）${NC}"
}

show_config() {
    echo ""
    echo -e "${BLUE}=== 当前代理配置 ===${NC}"
    echo ""
    
    echo -e "${CYAN}HTTP/HTTPS 代理：${NC}"
    HTTP_PROXY=$(git config --global --get http.proxy)
    HTTPS_PROXY=$(git config --global --get https.proxy)
    
    if [ -n "$HTTP_PROXY" ]; then
        echo "  http.proxy  = $HTTP_PROXY"
    else
        echo "  未配置"
    fi
    
    if [ -n "$HTTPS_PROXY" ]; then
        echo "  https.proxy = $HTTPS_PROXY"
    else
        echo "  未配置"
    fi
    
    echo ""
    echo -e "${CYAN}SSH 代理：${NC}"
    if [ -f ~/.ssh/config ]; then
        if grep -q "ProxyCommand" ~/.ssh/config; then
            echo "  已配置（查看 ~/.ssh/config）"
            grep -A2 "Host github.com" ~/.ssh/config | grep "ProxyCommand"
        else
            echo "  未配置"
        fi
    else
        echo "  未配置"
    fi
}

remove_proxy() {
    echo ""
    echo -e "${YELLOW}取消所有代理配置...${NC}"
    
    git config --global --unset http.proxy 2>/dev/null
    git config --global --unset https.proxy 2>/dev/null
    
    if [ -f ~/.ssh/config ]; then
        if grep -q "ProxyCommand" ~/.ssh/config; then
            cp ~/.ssh/config ~/.ssh/config.backup.$(date +%Y%m%d_%H%M%S)
            sed -i '/ProxyCommand/d' ~/.ssh/config
        fi
    fi
    
    echo -e "${GREEN}✓ 所有代理配置已取消${NC}"
}

test_connection() {
    echo ""
    echo -e "${BLUE}=== 测试 GitHub 连接 ===${NC}"
    echo ""
    
    echo -e "${CYAN}测试 HTTPS 连接...${NC}"
    if git ls-remote https://github.com/lailhio/cv32e40x.git HEAD &>/dev/null; then
        echo -e "${GREEN}✓ HTTPS 连接成功${NC}"
    else
        echo -e "${RED}✗ HTTPS 连接失败${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}测试 SSH 连接...${NC}"
    SSH_OUTPUT=$(ssh -T git@github.com 2>&1)
    if echo "$SSH_OUTPUT" | grep -q "successfully authenticated\|Hi"; then
        echo -e "${GREEN}✓ SSH 连接成功${NC}"
        echo "$SSH_OUTPUT"
    else
        echo -e "${RED}✗ SSH 连接失败${NC}"
        echo "$SSH_OUTPUT"
    fi
}

# 主循环
while true; do
    show_menu
    read -r option
    
    case $option in
        1) config_http_proxy ;;
        2) config_ssh_proxy_http ;;
        3) config_ssh_proxy_socks ;;
        4) show_config ;;
        5) remove_proxy ;;
        6) test_connection ;;
        0)
            echo ""
            echo -e "${GREEN}退出${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项${NC}"
            ;;
    esac
    
    echo ""
    echo -n "按回车继续..."
    read
    echo ""
done


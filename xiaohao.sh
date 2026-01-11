#!/bin/bash

# =========================================================
# 脚本名称: Traffic Wizard Pro (流量消耗交互脚本 - 增强版)
# 适用环境: Alpine, Debian, Ubuntu (256M内存 NAT VPS)
# 功能: 交互式菜单、后台静默运行、定时任务管理、全配置面板
# =========================================================

# 当前脚本版本
CURRENT_VERSION="1.2.0"

# --- 全局配置 ---
# 配置文件路径 (配置与脚本分离，确保更新脚本不丢配置)
CONFIG_FILE="$HOME/.traffic_wizard.conf"
LOG_FILE="/tmp/traffic_usage.log"

# 默认下载链接 (如果配置文件没有定义自定义链接，则使用这些)
DEFAULT_URLS=(
    "https://speed.cloudflare.com/__down?bytes=52428800"  # Cloudflare 50MB
    "http://speedtest.tele2.net/100MB.zip"               # Tele2 100MB
    "http://ping.online.net/100Mo.dat"                   # Online.net 100MB
    "http://cachefly.cachefly.net/100mb.test"            # Cachefly 100MB
)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本的绝对路径
SCRIPT_PATH=$(readlink -f "$0")

# --- 核心功能函数 ---

# 0. 加载/保存配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    # 如果没有加载到URL，使用默认
    if [ -z "$URLS" ]; then
        URLS=("${DEFAULT_URLS[@]}")
    fi
}

save_config() {
    echo "TELEGRAM_TOKEN=\"$TELEGRAM_TOKEN\"" > "$CONFIG_FILE"
    echo "TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"" >> "$CONFIG_FILE"
    # 这里可以扩展保存更多设置
}

# 1. 检查更新功能
check_update() {
    echo -e "${CYAN}正在检查 GitHub 最新版本...${NC}"
    # 获取 GitHub 上的脚本内容
    REMOTE_SCRIPT=$(curl -s https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh)
    
    # 使用 sed 提取版本号
    REMOTE_VERSION=$(echo "$REMOTE_SCRIPT" | sed -n 's/.*CURRENT_VERSION="\([0-9\.]*\)".*/\1/p')

    if [ -z "$REMOTE_VERSION" ]; then
        echo -e "${RED}无法从 GitHub 获取最新版本号！可能是网络问题。${NC}"
        return
    fi

    if [ "$CURRENT_VERSION" != "$REMOTE_VERSION" ]; then
        echo -e "${YELLOW}发现新版本！当前: $CURRENT_VERSION -> 最新: $REMOTE_VERSION${NC}"
        echo -e "是否更新脚本? (y/n): "
        read -r update_choice
        if [ "$update_choice" == "y" ]; then
            curl -s -o "$SCRIPT_PATH" https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh
            chmod +x "$SCRIPT_PATH"
            echo -e "${GREEN}脚本已更新！请重新运行。${NC}"
            exit 0
        else
            echo -e "${CYAN}跳过更新。${NC}"
        fi
    else
        echo -e "${GREEN}当前已经是最新版本 ($CURRENT_VERSION)！${NC}"
    fi
}

# 2. 下载核心逻辑
run_traffic() {
    load_config # 确保运行时加载最新配置
    local target_mb=$1
    local total_downloaded=0
    local count=0

    # 获取已消耗的流量
    if [ -f "$LOG_FILE" ]; then
        total_downloaded=$(cat "$LOG_FILE")
    fi

    if [ -z "$target_mb" ]; then target_mb=100; fi

    echo -e "${YELLOW}[运行中] 目标消耗: ${target_mb} MB (不占硬盘)${NC}"

    while [ $total_downloaded -lt $target_mb ]; do
        local url=${URLS[$RANDOM % ${#URLS[@]}]}
        
        # 显示当前使用的 User-Agent (调试用，可选)
        local ua=$(random_user_agent)

        curl -L -s -o /dev/null "$url" --connect-timeout 5 --max-time 120 --limit-rate 5M --user-agent "$ua"

        if [ $? -eq 0 ]; then
            total_downloaded=$((total_downloaded + 50))
            count=$((count + 1))
            echo -e " -> ${GREEN}成功下载第 $count 块 (累计约 ${total_downloaded} MB)${NC}"
        else
            echo -e " -> ${RED}下载超时或失败，更换链接重试...${NC}"
        fi

        sleep $((RANDOM % 3 + 1))
    done

    echo "$total_downloaded" > "$LOG_FILE"
    echo -e "${GREEN}任务完成！${NC}"
    send_telegram_notification "流量消耗任务完成，本次运行已达到目标，累计记录: $total_downloaded MB"
}

# 3. 获取随机 User-Agent
random_user_agent() {
    local agents=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/91.0.4472.124"
        "Mozilla/5.0 (X11; Linux x86_64) Firefox/89.0"
        "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15"
    )
    echo "${agents[$RANDOM % ${#agents[@]}]}"
}

# 4. 发送 Telegram 通知 (增强版)
send_telegram_notification() {
    local message=$1
    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        # 如果是手动运行，提示未配置；如果是后台运行，静默失败
        if [ "$2" == "manual" ]; then
            echo -e "${RED}错误：未配置 Telegram Bot Token 或 Chat ID。请先在菜单中设置。${NC}"
        fi
        return
    fi

    echo -e "${CYAN}正在发送 Telegram 通知...${NC}"
    res=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message")
    
    if [[ "$res" == *"\"ok\":true"* ]]; then
        echo -e "${GREEN}通知发送成功！${NC}"
    else
        echo -e "${RED}发送失败，请检查 Token 和 ID 是否正确。API返回: $res${NC}"
    fi
}

# 5. 配置 Telegram 菜单
config_telegram() {
    echo -e "${CYAN}--- Telegram 配置向导 ---${NC}"
    echo -e "当前 Token: ${GREEN}${TELEGRAM_TOKEN:-未设置}${NC}"
    echo -e "当前 Chat ID: ${GREEN}${TELEGRAM_CHAT_ID:-未设置}${NC}"
    echo -e "---------------------------"
    echo -e "1. 修改配置"
    echo -e "2. 发送测试消息"
    echo -e "0. 返回主菜单"
    read -p "请选择: " tg_choice

    case $tg_choice in
        1)
            read -p "请输入 Bot Token: " input_token
            read -p "请输入 Chat ID: " input_chatid
            if [ -n "$input_token" ] && [ -n "$input_chatid" ]; then
                TELEGRAM_TOKEN=$input_token
                TELEGRAM_CHAT_ID=$input_chatid
                save_config
                echo -e "${GREEN}配置已保存到 $CONFIG_FILE${NC}"
            else
                echo -e "${RED}输入不能为空！${NC}"
            fi
            sleep 1
            config_telegram
            ;;
        2)
            send_telegram_notification "Traffic Wizard: 这是一条测试消息。" "manual"
            read -p "按回车键继续..."
            config_telegram
            ;;
        *)
            show_menu
            ;;
    esac
}

# 6. 定时任务管理
add_cron() {
    echo -e "${CYAN}--- 设置定时任务 ---${NC}"
    echo -e "请输入每天消耗的流量 (MB):"
    read -r daily_mb
    echo -e "请输入每天几点开始运行 (0-23):"
    read -r start_hour

    if [[ ! "$daily_mb" =~ ^[0-9]+$ ]] || [[ ! "$start_hour" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}输入错误，请输入纯数字。${NC}"
        return
    fi

    # 清理旧任务并添加新任务
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    (crontab -l 2>/dev/null; echo "0 $start_hour * * * /bin/bash $SCRIPT_PATH auto $daily_mb >> /dev/null 2>&1") | crontab -

    echo -e "${GREEN}已设置：每天 $start_hour 点自动跑 $daily_mb MB。${NC}"
}

del_cron() {
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    echo -e "${GREEN}定时任务已清除。${NC}"
}

# 7. 主菜单
show_menu() {
    clear
    load_config # 每次显示菜单都重新加载配置
    echo -e "${BLUE}=======================================${NC}"
    echo -e "   Traffic Wizard Pro (流量保号助手)   "
    echo -e "${BLUE}=======================================${NC}"
    echo -e "脚本版本: ${GREEN}$CURRENT_VERSION${NC}"
    echo -e "TG 推送 : $(if [ -n "$TELEGRAM_TOKEN" ]; then echo -e "${GREEN}已配置${NC}"; else echo -e "${RED}未配置${NC}"; fi)"
    echo -e "---------------------------------------"
    echo -e "${YELLOW}>> 流量任务${NC}"
    echo -e " 1. ${GREEN}立即运行${NC} (手动跑流量)"
    echo -e " 2. ${GREEN}添加计划${NC} (定时自动跑)"
    echo -e " 3. ${GREEN}查看计划${NC} (Crontab)"
    echo -e " 4. ${RED}停止计划${NC} (删除任务)"
    echo -e "---------------------------------------"
    echo -e "${YELLOW}>> 高级设置${NC}"
    echo -e " 5. ${CYAN}通知设置${NC} (配置 Telegram Bot)"
    echo -e " 6. ${CYAN}检查更新${NC} (更新脚本版本)"
    echo -e " 0. 退出"
    echo -e "---------------------------------------"
    echo -n "请输入选项: "
    read -r choice

    case $choice in
        1)
            echo -n "请输入要消耗的流量(MB): "
            read -r mb
            run_traffic "$mb"
            read -p "按回车键返回..."
            show_menu
            ;;
        2)
            add_cron
            read -p "按回车键返回..."
            show_menu
            ;;
        3)
            echo -e "${YELLOW}当前任务列表:${NC}"
            crontab -l | grep "$SCRIPT_PATH" || echo "暂无任务"
            read -p "按回车键返回..."
            show_menu
            ;;
        4)
            del_cron
            read -p "按回车键返回..."
            show_menu
            ;;
        5)
            config_telegram
            ;;
        6)
            check_update
            read -p "按回车键返回..."
            show_menu
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "无效输入"
            sleep 1
            show_menu
            ;;
    esac
}

# --- 脚本入口 ---
# 如果有参数 'auto'，则直接进入后台运行模式，不加载菜单
if [ "$1" == "auto" ]; then
    load_config
    run_traffic "$2"
else
    show_menu
fi

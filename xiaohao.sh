#!/bin/bash

# =========================================================
# 脚本名称: Traffic Wizard (流量消耗交互脚本)
# 适用环境: Alpine, Debian, Ubuntu (256M内存 NAT VPS)
# 功能: 交互式菜单、后台静默运行、定时任务管理
# =========================================================

# 当前脚本版本
CURRENT_VERSION="1.0.0"

# --- 全局配置 ---
# 测速文件列表
URLS=(
    "https://speed.cloudflare.com/__down?bytes=52428800"  # Cloudflare 50MB
    "http://speedtest.tele2.net/100MB.zip"               # Tele2 100MB
    "http://ping.online.net/100Mo.dat"                   # Online.net 100MB
    "http://cachefly.cachefly.net/100mb.test"            # Cachefly 100MB
)

# Telegram Bot 配置
TELEGRAM_TOKEN="YOUR_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取脚本的绝对路径
SCRIPT_PATH=$(readlink -f "$0")
LOG_FILE="/tmp/traffic_usage.log"

# --- 核心功能函数 ---

# 1. 检查更新功能
check_update() {
    # 获取 GitHub 上的脚本内容
    REMOTE_SCRIPT=$(curl -s https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh)
    
    # 使用 sed 提取版本号
    REMOTE_VERSION=$(echo "$REMOTE_SCRIPT" | sed -n 's/.*CURRENT_VERSION="\([0-9\.]*\)".*/\1/p')

    if [ -z "$REMOTE_VERSION" ]; then
        echo -e "${RED}无法从 GitHub 获取最新版本号！${NC}"
        return
    fi

    if [ "$CURRENT_VERSION" != "$REMOTE_VERSION" ]; then
        echo -e "${YELLOW}发现新版本！当前版本: $CURRENT_VERSION，最新版本: $REMOTE_VERSION${NC}"
        echo -e "是否更新脚本? (y/n): "
        read -r update_choice
        if [ "$update_choice" == "y" ]; then
            curl -s -o "$SCRIPT_PATH" https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh
            echo -e "${GREEN}脚本已更新到最新版本！${NC}"
        else
            echo -e "${CYAN}跳过更新，继续使用当前版本。${NC}"
        fi
    else
        echo -e "${GREEN}当前已经是最新版本！${NC}"
    fi
}

# 2. 下载核心逻辑 (直接消耗流量)
# 参数 $1: 目标流量(MB)
run_traffic() {
    local target_mb=$1
    local total_downloaded=0
    local count=0

    # 获取已消耗的流量
    if [ -f "$LOG_FILE" ]; then
        total_downloaded=$(cat "$LOG_FILE")
    fi

    # 简单的防止并发导致卡死
    if [ -z "$target_mb" ]; then target_mb=100; fi

    echo -e "${YELLOW}[运行中] 目标消耗: ${target_mb} MB (不占硬盘)${NC}"

    while [ $total_downloaded -lt $target_mb ]; do
        # 随机取链接
        local url=${URLS[$RANDOM % ${#URLS[@]}]}

        # 估算每个文件大小(MB)，假设每次下载约 50MB
        # 使用curl下载到 /dev/null，限制下载速度为 2MB/s
        curl -L -s -o /dev/null "$url" --connect-timeout 5 --max-time 120 --limit-rate 2M --user-agent "$(random_user_agent)"

        if [ $? -eq 0 ]; then
            # 成功下载，累积流量
            total_downloaded=$((total_downloaded + 50))
            count=$((count + 1))
            echo -e " -> ${GREEN}成功下载第 $count 块 (累计约 ${total_downloaded} MB)${NC}"
        else
            echo -e " -> ${RED}下载超时或失败，重试中...${NC}"
        fi

        # 随机休眠 1-3秒
        sleep $((RANDOM % 3 + 1))
    done

    # 更新日志
    echo "$total_downloaded" > "$LOG_FILE"
    echo -e "${GREEN}任务完成！${NC}"

    # 发送 Telegram 通知
    send_telegram_notification "流量消耗任务完成，已消耗 $total_downloaded MB"
}

# 3. 获取随机 User-Agent
random_user_agent() {
    local agents=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (X11; Ubuntu; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Firefox/89.0"
        "Mozilla/5.0 (Linux; Android 10; Pixel 4 XL) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"
    )
    echo "${agents[$RANDOM % ${#agents[@]}]}"
}

# 4. 发送 Telegram 通知
send_telegram_notification() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message"
}

# 5. 添加定时任务
add_cron() {
    echo -e "${CYAN}--- 设置定时任务 ---${NC}"
    echo -e "请输入每天消耗的流量 (单位MB，例如 500):"
    read -r daily_mb
    echo -e "请输入每天几点开始运行 (0-23，例如 3 代表凌晨3点):"
    read -r start_hour

    if [[ ! "$daily_mb" =~ ^[0-9]+$ ]] || [[ ! "$start_hour" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}输入错误，请输入数字。${NC}"
        return
    fi

    # 清理旧的相同任务
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -

    # 添加新任务
    (crontab -l 2>/dev/null; echo "0 $start_hour * * * /bin/bash $SCRIPT_PATH auto $daily_mb >> /dev/null 2>&1") | crontab -

    echo -e "${GREEN}成功设置！每天 $start_hour 点将自动消耗 $daily_mb MB 流量。${NC}"
    echo -e "${YELLOW}提示: 请确保 cron 服务正在运行 (Alpine: rc-service crond start)${NC}"
}

# 6. 删除定时任务
del_cron() {
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    echo -e "${GREEN}已清除本脚本的所有定时任务。${NC}"
}

# 7. 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}=======================================${NC}"
    echo -e "    Traffic Wizard (流量保号助手)    "
    echo -e "${CYAN}=======================================${NC}"
    echo -e "当前系统: $(uname -s) / 内存可用: $(free -m | awk 'NR==2{print $7}')MB"
    echo -e "脚本路径: $SCRIPT_PATH"
    echo -e "---------------------------------------"
    echo -e " 1. ${GREEN}立即运行${NC} (手动输入流量并执行)"
    echo -e " 2. ${GREEN}添加计划${NC} (每天定时自动跑)"
    echo -e " 3. ${GREEN}查看计划${NC} (检查当前的Crontab)"
    echo -e " 4. ${RED}停止计划${NC} (删除定时任务)"
    echo -e " 0. 退出"
    echo -e "---------------------------------------"
    echo -n "请输入选项数字: "
    read -r choice

    case $choice in
        1)
            echo -n "请输入要消耗的流量(MB): "
            read -r mb
            run_traffic "$mb"
            read -p "按回车键返回菜单..."
            show_menu
            ;;
        2)
            add_cron
            read -p "按回车键返回菜单..."
            show_menu
            ;;
        3)
            echo -e "${YELLOW}当前 Crontab 列表:${NC}"
            crontab -l | grep "$SCRIPT_PATH"
            if [ $? -ne 0 ]; then echo "暂无本脚本的任务"; fi
            read -p "按回车键返回菜单..."
            show_menu
            ;;
        4)
            del_cron
            read -p "按回车键返回菜单..."
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
check_update
if [ "$1" == "auto" ]; then
    run_traffic "$2"
else
    show_menu
fi

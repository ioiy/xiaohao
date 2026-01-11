#!/bin/bash

# =========================================================
# 脚本名称: Traffic Wizard Ultimate (流量保号助手 - 稳定版)
# 版本: 2.2.0 (修复菜单返回、恢复更新检测、增强下载稳定性)
# =========================================================

# --- 全局配置 ---
CONFIG_FILE="$HOME/.traffic_wizard.conf"
SCRIPT_LOG="$HOME/.traffic_wizard.log"
SCRIPT_PATH=$(readlink -f "$0")

# 默认下载链接 (移除了一些不稳定的链接，保留大厂CDN)
DEFAULT_URLS=(
    "https://speed.cloudflare.com/__down?bytes=52428800"
    "http://speedtest.tele2.net/100MB.zip"
    "http://ping.online.net/100Mo.dat"
    "http://cachefly.cachefly.net/100mb.test"
    "http://speedtest.belgium.webhosting.be/100MB.bin"
    "http://speedtest-ny.turnkeyinternet.net/100mb.bin"
)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 当前版本
CURRENT_VERSION="2.2.0"

# --- 0. 初始化与配置加载 ---

# 默认变量
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
LIMIT_RATE="0"        
IP_VERSION="auto"     
SMART_MODE="false"    
MONTHLY_GOAL_GB="10" 

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    # 确保链接列表不为空
    if [ -z "${URLS+x}" ] || [ ${#URLS[@]} -eq 0 ]; then
        URLS=("${DEFAULT_URLS[@]}")
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
LIMIT_RATE="$LIMIT_RATE"
IP_VERSION="$IP_VERSION"
SMART_MODE="$SMART_MODE"
MONTHLY_GOAL_GB="$MONTHLY_GOAL_GB"
EOF
}

# --- 1. 核心工具函数 ---

check_vnstat() {
    if ! command -v vnstat &> /dev/null; then return 1; else return 0; fi
}

get_system_monthly_traffic() {
    if check_vnstat; then
        local traffic_output
        traffic_output=$(vnstat -m --oneline 2>/dev/null | awk -F';' '{print $11}') 
        if [ -z "$traffic_output" ]; then echo "0"; else
            echo | awk -v bytes="$traffic_output" '{printf "%.2f", bytes/1024/1024/1024}'
        fi
    else
        echo "0"
    fi
}

log_traffic_usage() {
    echo "$(date +%s)|$1" >> "$SCRIPT_LOG"
}

get_script_monthly_usage() {
    if [ ! -f "$SCRIPT_LOG" ]; then echo "0"; return; fi
    local current_month_start=$(date -d "$(date +%Y-%m-01)" +%s)
    local total_bytes=0
    while IFS='|' read -r timestamp bytes; do
        if [ "$timestamp" -ge "$current_month_start" ]; then
            total_bytes=$(awk -v t="$total_bytes" -v b="$bytes" 'BEGIN {print t + b}')
        fi
    done < "$SCRIPT_LOG"
    awk -v b="$total_bytes" 'BEGIN {printf "%.2f", b/1024/1024/1024}'
}

send_telegram() {
    local msg=$1
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" -d text="$msg" > /dev/null
    fi
}

random_user_agent() {
    local agents=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15"
        "Mozilla/5.0 (X11; Linux x86_64; rv:89.0) Gecko/20100101 Firefox/89.0"
    )
    echo "${agents[$RANDOM % ${#agents[@]}]}"
}

# --- 2. 检查更新功能 (修复版) ---
check_update() {
    echo -e "${CYAN}正在连接 GitHub 检查更新...${NC}"
    # 使用加速代理防止国内/部分IP连接失败
    local remote_url="https://ghproxy.com/https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh"
    # 如果代理失败，尝试直连
    local remote_script=$(curl -s --connect-timeout 5 "$remote_url")
    if [ -z "$remote_script" ]; then
        remote_script=$(curl -s --connect-timeout 5 "https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh")
    fi

    local remote_version=$(echo "$remote_script" | sed -n 's/.*CURRENT_VERSION="\([0-9\.]*\)".*/\1/p')

    if [ -z "$remote_version" ]; then
        echo -e "${RED}检查失败：无法获取远程版本号 (可能是网络问题)${NC}"
        return
    fi

    # 简单的版本号比较逻辑
    if [[ "$remote_version" > "$CURRENT_VERSION" ]]; then
        echo -e "${YELLOW}发现新版本！当前: $CURRENT_VERSION -> 最新: $remote_version${NC}"
        echo -e "注意：远程版本可能不包含您当前的[智能/限速]增强功能。"
        read -p "是否确要更新并覆盖当前脚本? (y/n): " confirm
        if [ "$confirm" == "y" ]; then
            echo "$remote_script" > "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            echo -e "${GREEN}更新成功！请重启脚本。${NC}"
            exit 0
        else
            echo -e "已取消更新。"
        fi
    else
        echo -e "${GREEN}当前使用的是最新(或定制)版本 ($CURRENT_VERSION)，无需更新。${NC}"
        echo -e "(远程仓库版本为: $remote_version)"
    fi
}

# --- 3. 核心运行逻辑 ---

run_traffic() {
    load_config
    local target_mb=$1
    local mode=$2

    # 智能模式检查
    if [ "$mode" == "auto" ] && [ "$SMART_MODE" == "true" ]; then
        if check_vnstat; then
            local sys_usage=$(get_system_monthly_traffic)
            local is_limit_reached=$(awk -v u="$sys_usage" -v g="$MONTHLY_GOAL_GB" 'BEGIN {print (u >= g) ? 1 : 0}')
            if [ "$is_limit_reached" -eq 1 ]; then
                local log_msg="[智能模式] 本月流量($sys_usage GB) 已达标($MONTHLY_GOAL_GB GB)。停止运行。"
                echo -e "${YELLOW}$log_msg${NC}"
                send_telegram "$log_msg"
                exit 0
            else
                echo -e "${GREEN}[智能模式] 本月已用 $sys_usage GB，未达标，开始补课...${NC}"
            fi
        fi
    fi

    local total_downloaded=0
    local count=0
    local target_bytes=$((target_mb * 1024 * 1024))
    
    # [关键修复] 增加 -k (忽略证书), 增加超时时间到10s, 增加重试次数
    local curl_opts="-L -s -o /dev/null -k --retry 2 --connect-timeout 10 --max-time 180"
    if [ "$LIMIT_RATE" != "0" ]; then curl_opts="$curl_opts --limit-rate $LIMIT_RATE"; fi
    if [ "$IP_VERSION" == "4" ]; then curl_opts="$curl_opts -4"; fi
    if [ "$IP_VERSION" == "6" ]; then curl_opts="$curl_opts -6"; fi

    echo -e "${YELLOW}[运行中] 目标: ${target_mb} MB | 限速: ${LIMIT_RATE:-无} | UA: 随机${NC}"

    while [ $total_downloaded -lt $target_bytes ]; do
        local url=${URLS[$RANDOM % ${#URLS[@]}]}
        local ua=$(random_user_agent)
        
        # 执行下载
        curl $curl_opts --user-agent "$ua" "$url"
        
        if [ $? -eq 0 ]; then
            local chunk_size=$((50 * 1024 * 1024)) 
            total_downloaded=$((total_downloaded + chunk_size))
            log_traffic_usage "$chunk_size"
            count=$((count + 1))
            local current_mb=$((total_downloaded / 1024 / 1024))
            echo -e " -> ${GREEN}成功块 #$count (累计约 ${current_mb} MB)${NC}"
        else
            # 失败时输出简单的提示
            echo -e " -> ${RED}下载失败 (网络波动或IP不通)，更换链接重试...${NC}"
        fi
        sleep $((RANDOM % 3 + 2))
    done

    echo -e "${GREEN}任务完成！${NC}"
    send_telegram "Traffic Wizard: 任务完成。本次脚本消耗约 $target_mb MB。"
}

# --- 4. 菜单界面 ---

settings_menu() {
    while true; do
        clear; load_config
        echo -e "${PURPLE}=== 参数设置 ===${NC}"
        echo -e "1. 配置 Telegram Bot [$( [ -n "$TELEGRAM_TOKEN" ] && echo "${GREEN}已配${NC}" || echo "${RED}无${NC}" )]"
        echo -e "2. 流量限速设置    [${GREEN}${LIMIT_RATE:-0}${NC}]"
        echo -e "3. IP 协议偏好     [${CYAN}${IP_VERSION:-auto}${NC}]"
        echo -e "4. 智能补课模式    [$( [ "$SMART_MODE" == "true" ] && echo "${GREEN}开启${NC}" || echo "${RED}关闭${NC}" )]"
        echo -e "0. 返回"
        read -p "选择: " s_choice
        case $s_choice in
            1)
                read -p "Bot Token: " TELEGRAM_TOKEN
                read -p "Chat ID: " TELEGRAM_CHAT_ID
                save_config; echo "已保存。" ;;
            2)
                read -p "限速值 (如 2M, 500k, 0为不限): " LIMIT_RATE
                save_config ;;
            3)
                read -p "1.auto 2.IPv4 3.IPv6 : " ip_c
                case $ip_c in 2) IP_VERSION="4";; 3) IP_VERSION="6";; *) IP_VERSION="auto";; esac
                save_config ;;
            4)
                if ! check_vnstat; then echo "请先安装 vnstat"; sleep 2; else
                    if [ "$SMART_MODE" == "true" ]; then SMART_MODE="false"; else
                        SMART_MODE="true"; read -p "月度目标(GB): " MONTHLY_GOAL_GB
                    fi
                    save_config
                fi ;;
            0) return ;; # [修复] 这里 return 后，main_menu 会重新加载
        esac
    done
}

main_menu() {
    while true; do
        load_config
        clear
        echo -e "${BLUE}Traffic Wizard Ultimate v${CURRENT_VERSION}${NC}"
        echo -e "--------------------------"
        echo -e " 1. ${GREEN}立即运行${NC} (手动)"
        echo -e " 2. ${YELLOW}定时任务管理${NC}"
        echo -e " 3. ${CYAN}流量统计面板${NC}"
        echo -e " 4. ${PURPLE}参数设置${NC}"
        echo -e " 5. ${BLUE}检查更新${NC}"
        echo -e " 0. 退出"
        echo -e "--------------------------"
        read -p "请输入选项: " choice
        case $choice in
            1) read -p "输入流量(MB): " mb; run_traffic "$mb" "manual"; read -p "按回车..." ;;
            2) 
               echo "1.添加 2.删除 3.查看"; read -p "选: " c
               if [ "$c" == "1" ]; then read -p "MB: " m; read -p "Hour: " h; 
                  (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "0 $h * * * /bin/bash $SCRIPT_PATH auto $m >> /dev/null 2>&1") | crontab -; echo "已加"; fi
               if [ "$c" == "2" ]; then crontab -l | grep -v "$SCRIPT_PATH" | crontab -; echo "已删"; fi
               if [ "$c" == "3" ]; then crontab -l | grep "$SCRIPT_PATH"; fi
               read -p "按回车..." ;;
            3) 
               u=$(get_script_monthly_usage); s=$(get_system_monthly_traffic)
               echo "脚本跑了: $u GB | 系统总计: $s GB"; read -p "按回车..." ;;
            4) settings_menu ;;
            5) check_update; read -p "按回车..." ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

# --- 入口 ---
if [ "$1" == "auto" ]; then
    run_traffic "$2" "auto"
else
    main_menu
fi

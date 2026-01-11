#!/bin/bash

# =========================================================
# 脚本名称: Traffic Wizard Ultimate (流量保号助手 - 完美交互版)
# 版本: 2.9.2 (主菜单净化、停止功能归档、更新检测修复)
# GitHub: https://github.com/ioiy/xiaohao
# =========================================================

# --- 全局配置 ---
CONFIG_FILE="$HOME/.traffic_wizard.conf"
SCRIPT_LOG="$HOME/.traffic_wizard.log"
SCRIPT_PATH=$(readlink -f "$0")

# 默认下载链接池
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
BOLD='\033[1m'

# 当前版本
CURRENT_VERSION="2.9.2"

# --- 0. 初始化与配置加载 ---
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
LIMIT_RATE="0"        
IP_VERSION="auto"     
SMART_MODE="false"    
MONTHLY_GOAL_GB="10"
ENABLE_JITTER="true"
CUSTOM_URLS_STR="" 

load_config() {
    if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi
    URLS=("${DEFAULT_URLS[@]}")
    if [ -n "$CUSTOM_URLS_STR" ]; then
        IFS=',' read -ra USER_URLS <<< "$CUSTOM_URLS_STR"
        URLS+=("${USER_URLS[@]}")
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
ENABLE_JITTER="$ENABLE_JITTER"
CUSTOM_URLS_STR="$CUSTOM_URLS_STR"
EOF
}

# --- 1. 核心工具函数 ---

check_vnstat() { if ! command -v vnstat &> /dev/null; then return 1; else return 0; fi; }

get_main_interface() {
    local iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    if [ -z "$iface" ]; then
        iface=$(cat /proc/net/dev | grep -v 'lo:' | head -n 1 | awk -F: '{print $1}' | sed 's/ //g')
    fi
    echo "$iface"
}

get_system_traffic() {
    if check_vnstat; then
        local traffic_output
        traffic_output=$(vnstat -m --oneline 2>/dev/null | awk -F';' '{print $11}') 
        if [ -n "$traffic_output" ]; then
            echo | awk -v bytes="$traffic_output" '{printf "%.2f", bytes/1024/1024/1024}'
            return
        fi
    fi
    local iface=$(get_main_interface)
    if [ -n "$iface" ]; then
        local line=$(grep "$iface" /proc/net/dev)
        if [ -n "$line" ]; then
            local rx=$(echo "$line" | awk '{print $2}')
            local tx=$(echo "$line" | awk '{print $10}')
            local total_bytes=$(awk -v r="$rx" -v t="$tx" 'BEGIN {print r + t}')
            awk -v b="$total_bytes" 'BEGIN {printf "%.2f", b/1024/1024/1024}'
            return
        fi
    fi
    echo "0"
}

log_traffic_usage() { 
    echo "$(date '+%Y-%m-%d %H:%M:%S')|$1" >> "$SCRIPT_LOG" 
}

get_script_monthly_usage() {
    if [ ! -f "$SCRIPT_LOG" ]; then echo "0"; return; fi
    awk -F'|' '{sum+=$2} END {printf "%.2f", sum/1024/1024/1024}' "$SCRIPT_LOG"
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

# --- 2. 功能函数 ---

# [修复] 增加防缓存机制的更新检测
check_update() {
    echo -e "${CYAN}正在连接 GitHub 检查更新...${NC}"
    local timestamp=$(date +%s) # 时间戳防止CDN缓存
    local mirrors=(
        "https://ghproxy.net/https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh?t=$timestamp"
        "https://fastly.jsdelivr.net/gh/ioiy/xiaohao@main/xiaohao.sh?t=$timestamp"
        "https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh?t=$timestamp"
    )
    local remote_script=""
    local remote_version=""
    for url in "${mirrors[@]}"; do
        remote_script=$(curl -s -k -L --connect-timeout 10 "$url")
        if [ -n "$remote_script" ]; then
            remote_version=$(echo "$remote_script" | sed -n 's/.*CURRENT_VERSION="\([0-9\.]*\)".*/\1/p')
            if [ -n "$remote_version" ]; then break; fi
        fi
    done
    
    if [ -z "$remote_version" ]; then 
        echo -e "${RED}检查失败：无法连接服务器。${NC}"
        return
    fi
    
    echo -e "当前: v$CURRENT_VERSION | 最新: v$remote_version"
    
    if [ "$CURRENT_VERSION" != "$remote_version" ]; then
        echo -e "${YELLOW}发现新版本！${NC}"
        read -p "是否更新? (y/n): " confirm
        if [ "$confirm" == "y" ]; then
            # 移除可能存在的URL参数内容，纯净覆盖
            # 注意：curl 获取的内容本身不含参数，直接覆盖即可
            echo "$remote_script" > "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            echo -e "${GREEN}更新成功。请重新运行。${NC}"; exit 0
        fi
    else 
        echo -e "${GREEN}无需更新。${NC}"
    fi
}

uninstall_dependencies() {
    if check_vnstat; then
        read -p "是否同时卸载 vnstat? (y/n): " rm_vn
        if [ "$rm_vn" == "y" ]; then
            echo "正在卸载 vnstat..."
            if [ -f /etc/alpine-release ]; then apk del vnstat
            elif [ -f /etc/debian_version ]; then apt-get purge -y vnstat && apt-get autoremove -y; fi
            echo "vnstat 已卸载。"
        fi
    fi
}

kill_all_tasks() {
    echo -e "${YELLOW}正在终止所有后台流量任务...${NC}"
    pgrep -f "$SCRIPT_PATH" | grep -v $$ | xargs -r kill -9
    echo -e "${GREEN}脚本后台进程已停止。${NC}"
    sleep 1
}

install_dependencies() {
    echo -e "${CYAN}正在安装依赖...${NC}"
    if [ -f /etc/alpine-release ]; then apk update && apk add vnstat curl bash && rc-service vnstatd start 2>/dev/null && rc-update add vnstatd default 2>/dev/null
    elif [ -f /etc/debian_version ]; then apt-get update && apt-get install -y vnstat curl cron bc && systemctl enable vnstat 2>/dev/null && systemctl start vnstat 2>/dev/null
    else echo -e "${RED}未知系统。${NC}"; return; fi
    echo -e "${GREEN}完成。${NC}"; vnstat -u 2>/dev/null; sleep 1
}

reset_stats() { rm -f "$SCRIPT_LOG"; echo -e "${GREEN}已重置。${NC}"; sleep 1; }

uninstall_script() {
    read -p "确定卸载? (y/n): " c
    if [ "$c" == "y" ]; then
        uninstall_dependencies
        crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
        rm -f "$CONFIG_FILE" "$SCRIPT_LOG" "$SCRIPT_PATH"
        echo -e "${GREEN}卸载完成。${NC}"; exit 0
    fi
}

live_speed() {
    if ! check_vnstat; then echo -e "${RED}请先在系统工具中安装 vnstat。${NC}"; sleep 2; return; fi
    echo -e "${GREEN}正在启动实时监视 (按 Ctrl+C 退出)...${NC}"
    vnstat -l
}

view_log() {
    echo -e "${CYAN}=== 最近 10 条运行记录 ===${NC}"
    if [ -f "$SCRIPT_LOG" ]; then
        tail -n 10 "$SCRIPT_LOG"
    else
        echo "暂无日志。"
    fi
    echo -e "${CYAN}=========================${NC}"
    read -p "按回车返回..."
}

# --- 3. 核心下载逻辑 ---
run_traffic() {
    load_config
    local target_mb=$1
    local mode=$2

    if [ "$mode" == "auto" ] && [ "$SMART_MODE" == "true" ]; then
        local sys_usage=$(get_system_traffic)
        local is_limit_reached=$(awk -v u="$sys_usage" -v g="$MONTHLY_GOAL_GB" 'BEGIN {print (u >= g) ? 1 : 0}')
        if [ "$is_limit_reached" -eq 1 ]; then
            local log_msg="[智能模式] 流量($sys_usage GB) 已达标($MONTHLY_GOAL_GB GB)。停止运行。"
            echo -e "${YELLOW}$log_msg${NC}"; send_telegram "$log_msg"; exit 0
        fi
    fi

    if [ "$ENABLE_JITTER" == "true" ]; then
        local percent=$((RANDOM % 21 - 10))
        local offset=$((target_mb * percent / 100))
        target_mb=$((target_mb + offset))
        echo -e "${PURPLE}[拟人化] 目标修正为 ${target_mb} MB${NC}"
    fi

    local total_downloaded=0
    local count=0
    local target_bytes=$((target_mb * 1024 * 1024))
    local curl_opts="-L -s -o /dev/null -k --retry 2 --connect-timeout 15 --max-time 180"
    if [ "$LIMIT_RATE" != "0" ]; then curl_opts="$curl_opts --limit-rate $LIMIT_RATE"; fi
    if [ "$IP_VERSION" == "4" ]; then curl_opts="$curl_opts -4"; fi
    if [ "$IP_VERSION" == "6" ]; then curl_opts="$curl_opts -6"; fi

    echo -e "${YELLOW}[运行中] 目标: ${target_mb} MB | 链接数: ${#URLS[@]} | UA: 随机${NC}"
    while [ $total_downloaded -lt $target_bytes ]; do
        local url=${URLS[$RANDOM % ${#URLS[@]}]}
        local ua=$(random_user_agent)
        curl $curl_opts --user-agent "$ua" "$url"
        if [ $? -eq 0 ]; then
            local chunk_size=$((50 * 1024 * 1024)) 
            total_downloaded=$((total_downloaded + chunk_size))
            log_traffic_usage "$chunk_size"
            count=$((count + 1))
            local current_mb=$((total_downloaded / 1024 / 1024))
            echo -e " -> ${GREEN}成功 #$count (共 ${current_mb} MB)${NC}"
        else
            echo -e " -> ${RED}失败，重试...${NC}"
        fi
        sleep $((RANDOM % 3 + 2))
    done
    echo -e "${GREEN}完成！${NC}"
    send_telegram "Traffic Wizard: 任务完成。消耗约 $target_mb MB。"
}

# --- 4. 菜单逻辑 (最终版) ---

cron_menu() {
    while true; do
        clear; show_dashboard
        echo -e "${YELLOW}=== 当前生效的定时任务 ===${NC}"
        local tasks=$(crontab -l 2>/dev/null | grep "$SCRIPT_PATH")
        if [ -z "$tasks" ]; then
            echo -e "${RED}    暂无计划任务${NC}"
        else
            echo "$tasks" | while read -r line; do
                local mb=$(echo "$line" | grep -o 'auto [0-9]*' | awk '{print $2}')
                if [[ "$line" == *"sleep"* ]]; then
                    echo -e " ${PURPLE}[随机]${NC} 每天 00:00 启动 (随机延迟执行) -> 计划跑 ${GREEN}${mb}MB${NC}"
                else
                    local hour=$(echo "$line" | awk '{print $2}')
                    echo -e " ${CYAN}[固定]${NC} 每天 ${hour}点 运行             -> 计划跑 ${GREEN}${mb}MB${NC}"
                fi
            done
        fi
        echo -e "----------------------------------------"
        echo -e "1. 添加 ${GREEN}固定时间${NC} 计划 (如每天 3点)"
        echo -e "2. 添加 ${PURPLE}随机时间${NC} 计划 (每天时间都不一样)"
        echo -e "3. 删除所有计划"
        echo -e "0. 返回上级"
        read -p "选择: " c_choice
        case $c_choice in
            1)
                read -p "请输入每天消耗流量 (MB): " m
                read -p "请输入开始时间 (0-23点): " h
                crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
                (crontab -l 2>/dev/null; echo "0 $h * * * /bin/bash $SCRIPT_PATH auto $m >> /dev/null 2>&1") | crontab -
                echo -e "${GREEN}已添加: 每天 $h 点运行。${NC}"; sleep 2 ;;
            2)
                read -p "请输入每天消耗流量 (MB): " m
                echo -e "${PURPLE}[随机模式] 每天 00:00 启动，随机等待 0~18 小时后开始跑。${NC}"
                crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
                (crontab -l 2>/dev/null; echo "0 0 * * * sleep \$((RANDOM + RANDOM)) && /bin/bash $SCRIPT_PATH auto $m >> /dev/null 2>&1") | crontab -
                echo -e "${GREEN}已添加随机计划。${NC}"; sleep 2 ;;
            3)
                crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
                echo -e "${GREEN}已删除任务。${NC}"; sleep 1 ;;
            0) return ;;
        esac
    done
}

system_tools_menu() {
    while true; do
        clear
        echo -e "${PURPLE}=== 系统与高级工具 ===${NC}"
        echo -e "1. 配置 Telegram Bot"
        echo -e "2. ${CYAN}一键安装 vnstat (推荐)${NC}"
        echo -e "3. ${GREEN}实时网速监视器${NC} (Live Speed)"
        echo -e "4. ${GREEN}查看运行日志${NC} (Logs)"
        echo -e "5. 重置流量统计数据"
        echo -e "6. ${RED}停止当前运行 (Kill)${NC}" 
        echo -e "7. ${RED}彻底卸载脚本${NC}"
        echo -e "0. 返回主菜单"
        read -p "选择: " sys_c
        case $sys_c in
            1) read -p "Token: " TELEGRAM_TOKEN; read -p "ChatID: " TELEGRAM_CHAT_ID; save_config ;;
            2) install_dependencies; read -p "按回车..." ;;
            3) live_speed ;;
            4) view_log ;;
            5) reset_stats ;;
            6) kill_all_tasks ;;
            7) uninstall_script ;;
            0) return ;;
        esac
    done
}

show_dashboard() {
    load_config
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local script_u=$(get_script_monthly_usage)
    local sys_u=$(get_system_traffic)
    local status_text=""; if check_vnstat; then status_text="${GREEN}vnstat${NC}"; else status_text="${YELLOW}内核${NC}"; fi
    local custom_url_count=0; if [ -n "$CUSTOM_URLS_STR" ]; then IFS=',' read -ra TMP_ARR <<< "$CUSTOM_URLS_STR"; custom_url_count=${#TMP_ARR[@]}; fi

    echo -e "${BLUE}====================================================${NC}"
    echo -e "         ${BOLD}Traffic Wizard Ultimate v${CURRENT_VERSION}${NC}        "
    echo -e "${BLUE}====================================================${NC}"
    echo -e " ${BOLD}状态:${NC} RAM:${mem_used}MB | 源:$status_text | 链接:${#URLS[@]}个(自定:${custom_url_count})"
    echo -e " ${BOLD}流量:${NC} 脚本:${GREEN}${script_u}G${NC} | 系统:${YELLOW}${sys_u}G${NC} | 目标:${MONTHLY_GOAL_GB}G"
    echo -e "${BLUE}====================================================${NC}"
}

main_menu() {
    while true; do
        clear; show_dashboard 
        echo -e " [ 1] ${GREEN}立即运行${NC} (手动)"
        echo -e " [ 2] ${YELLOW}计划任务${NC} (自动/随机)"
        echo -e "----------------------------------------"
        echo -e " [ 3] 智能模式 [当前: $([ "$SMART_MODE" == "true" ] && echo "${GREEN}开${NC}" || echo "${RED}关${NC}")]"
        echo -e " [ 4] 流量波动 [当前: $([ "$ENABLE_JITTER" == "true" ] && echo "${GREEN}开${NC}" || echo "${RED}关${NC}")]"
        echo -e " [ 5] 速度限制 [当前: ${CYAN}${LIMIT_RATE:-0}${NC}]"
        echo -e " [ 6] IP 偏好  [当前: ${CYAN}${IP_VERSION:-auto}${NC}]"
        echo -e " [ 7] 添加自定义链接"
        echo -e "----------------------------------------"
        echo -e " [ 8] ${PURPLE}系统工具${NC} (日志/卸载/vnstat/停止)"
        echo -e " [ 9] 检查更新"
        echo -e " [ 0] 退出脚本"
        echo -e "----------------------------------------"
        read -p "请输入选项: " choice
        case $choice in
            1) read -p "输入流量(MB): " mb; run_traffic "$mb" "manual"; read -p "按回车..." ;;
            2) cron_menu ;;
            3) 
               if [ "$SMART_MODE" == "true" ]; then SMART_MODE="false"; else SMART_MODE="true"; read -p "输入月度目标(GB): " MONTHLY_GOAL_GB; fi
               save_config ;;
            4) 
               if [ "$ENABLE_JITTER" == "true" ]; then ENABLE_JITTER="false"; else ENABLE_JITTER="true"; fi
               save_config ;;
            5) read -p "输入限速值 (如 2M, 500k, 0为不限): " LIMIT_RATE; save_config ;;
            6) read -p "1.auto 2.IPv4 3.IPv6: " ip_c; case $ip_c in 2) IP_VERSION="4";; 3) IP_VERSION="6";; *) IP_VERSION="auto";; esac; save_config ;;
            7) 
               echo -e "请输入下载链接 (http/https):"
               read -r new_url
               if [[ $new_url == http* ]]; then
                   if [ -z "$CUSTOM_URLS_STR" ]; then CUSTOM_URLS_STR="$new_url"; else CUSTOM_URLS_STR="$CUSTOM_URLS_STR,$new_url"; fi
                   save_config; echo "已添加。"
               else echo "无效链接"; fi; sleep 1 ;;
            8) system_tools_menu ;;
            9) check_update; read -p "按回车..." ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

if [ "$1" == "auto" ]; then run_traffic "$2" "auto"; else main_menu; fi

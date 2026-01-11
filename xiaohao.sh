#!/bin/bash

# =========================================================
# 脚本名称: Traffic Wizard Ultimate (流量保号助手 - 自由版)
# 版本: 2.7.0 (移除熔断保护、新增自定义链接、一键停止)
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
CURRENT_VERSION="2.7.0"

# --- 0. 初始化与配置加载 ---
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
LIMIT_RATE="0"        
IP_VERSION="auto"     
SMART_MODE="false"    
MONTHLY_GOAL_GB="10"
ENABLE_JITTER="true"
CUSTOM_URLS_STR=""    # 存储用户自定义链接，用逗号分隔

load_config() {
    if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi
    
    # 重置并合并链接池
    URLS=("${DEFAULT_URLS[@]}")
    
    # 如果有自定义链接，加入池子
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
    # 内核读取模式
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

log_traffic_usage() { echo "$(date +%s)|$1" >> "$SCRIPT_LOG"; }

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

# --- 2. 功能函数 ---

check_update() {
    echo -e "${CYAN}正在连接 GitHub 检查更新...${NC}"
    local remote_url="https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh"
    local remote_script=$(curl -s --connect-timeout 5 "https://ghproxy.com/$remote_url")
    if [ -z "$remote_script" ]; then remote_script=$(curl -s --connect-timeout 5 "$remote_url"); fi
    local remote_version=$(echo "$remote_script" | sed -n 's/.*CURRENT_VERSION="\([0-9\.]*\)".*/\1/p')

    if [ -z "$remote_version" ]; then echo -e "${RED}检查失败。${NC}"; return; fi
    echo -e "当前: v$CURRENT_VERSION | 最新: v$remote_version"

    if [ "$CURRENT_VERSION" != "$remote_version" ]; then
        read -p "发现新版本，是否更新? (y/n): " confirm
        if [ "$confirm" == "y" ]; then
            echo "$remote_script" > "$SCRIPT_PATH"; chmod +x "$SCRIPT_PATH"
            echo -e "${GREEN}更新成功。${NC}"; exit 0
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

# [新增] 紧急停止
kill_all_tasks() {
    echo -e "${YELLOW}正在终止所有后台流量任务...${NC}"
    # 杀掉所有包含当前脚本路径的 bash 进程，排除自己
    pgrep -f "$SCRIPT_PATH" | grep -v $$ | xargs -r kill -9
    # 杀掉 curl 进程 (谨慎操作，假设只杀本脚本起的curl有点难区分，这里简单粗暴杀掉长时间运行的curl)
    # 为安全起见，只提示
    echo -e "${GREEN}脚本后台进程已停止。${NC}"
    echo -e "${YELLOW}提示: 如果 curl 还在运行，请手动执行 'killall curl' (如果有权限)${NC}"
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

# --- 3. 核心下载逻辑 (无熔断版) ---
run_traffic() {
    load_config
    local target_mb=$1
    local mode=$2

    # [已移除] 负载检查 check_load 及其熔断逻辑

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
    local curl_opts="-L -s -o /dev/null -k --retry 2 --connect-timeout 10 --max-time 180"
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

# --- 4. 仪表盘与菜单 ---

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
    echo -e " ${BOLD}配置:${NC} 智能[$( [ "$SMART_MODE" == "true" ] && echo "${GREEN}开${NC}" || echo "${RED}关${NC}" )] | 波动[$( [ "$ENABLE_JITTER" == "true" ] && echo "${GREEN}开${NC}" || echo "${RED}关${NC}" )] | 限速[${CYAN}${LIMIT_RATE:-无}${NC}]"
    echo -e "${BLUE}====================================================${NC}"
}

settings_menu() {
    while true; do
        clear; show_dashboard
        echo -e "${PURPLE}=== 参数设置 ===${NC}"
        echo -e "1. 配置 Telegram Bot"
        echo -e "2. 流量限速设置"
        echo -e "3. IP 协议偏好"
        echo -e "4. 智能补课模式"
        echo -e "5. 随机流量波动"
        echo -e "6. ${CYAN}添加自定义下载链接${NC} (NEW!)"
        echo -e "7. 清空自定义链接"
        echo -e "8. 安装 vnstat | 9. 重置统计 | 10. 卸载"
        echo -e "0. 返回"
        read -p "选择: " s_choice
        case $s_choice in
            1) read -p "Token: " TELEGRAM_TOKEN; read -p "ChatID: " TELEGRAM_CHAT_ID; save_config ;;
            2) read -p "限速 (如 2M, 500k, 0关): " LIMIT_RATE; save_config ;;
            3) read -p "1.auto 2.IPv4 3.IPv6: " ip_c; case $ip_c in 2) IP_VERSION="4";; 3) IP_VERSION="6";; *) IP_VERSION="auto";; esac; save_config ;;
            4) [ "$SMART_MODE" == "true" ] && SMART_MODE="false" || { SMART_MODE="true"; read -p "目标(GB): " MONTHLY_GOAL_GB; }; save_config ;;
            5) [ "$ENABLE_JITTER" == "true" ] && ENABLE_JITTER="false" || ENABLE_JITTER="true"; save_config ;;
            6) 
               echo -e "请输入下载链接 (http/https):"
               read -r new_url
               if [[ $new_url == http* ]]; then
                   if [ -z "$CUSTOM_URLS_STR" ]; then CUSTOM_URLS_STR="$new_url"; else CUSTOM_URLS_STR="$CUSTOM_URLS_STR,$new_url"; fi
                   save_config; echo "已添加。"
               else echo "无效链接"; fi; sleep 1 ;;
            7) CUSTOM_URLS_STR=""; save_config; echo "已清空"; sleep 1 ;;
            8) install_dependencies; read -p "按回车..." ;;
            9) reset_stats ;;
            10) uninstall_script ;;
            0) return ;;
        esac
    done
}

main_menu() {
    while true; do
        clear; show_dashboard 
        echo -e " 1. ${GREEN}立即运行${NC} (手动)"
        echo -e " 2. ${YELLOW}定时任务${NC} (自动)"
        echo -e " 3. ${PURPLE}高级设置${NC} (链接/配置/卸载)"
        echo -e " 4. ${RED}停止运行${NC} (Kill All)"
        echo -e " 5. ${BLUE}检查更新${NC}"
        echo -e " 0. 退出"
        echo -e "----------------------------------------------------"
        read -p "请输入选项: " choice
        case $choice in
            1) read -p "输入流量(MB): " mb; run_traffic "$mb" "manual"; read -p "按回车..." ;;
            2) 
               echo "1.添加 2.删除 3.查看"; read -p "选: " c
               if [ "$c" == "1" ]; then read -p "MB: " m; read -p "StartHour: " h; 
                  (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "0 $h * * * /bin/bash $SCRIPT_PATH auto $m >> /dev/null 2>&1") | crontab -; echo "已加"; sleep 1; fi
               if [ "$c" == "2" ]; then crontab -l | grep -v "$SCRIPT_PATH" | crontab -; echo "已删"; sleep 1; fi
               if [ "$c" == "3" ]; then crontab -l | grep "$SCRIPT_PATH"; read -p "按回车..."; fi ;;
            3) settings_menu ;;
            4) kill_all_tasks ;;
            5) check_update; read -p "按回车..." ;;
            0) exit 0 ;;
        esac
    done
}

if [ "$1" == "auto" ]; then run_traffic "$2" "auto"; else main_menu; fi

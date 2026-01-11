#!/bin/bash

# =========================================================
# 脚本名称: Traffic Wizard Ultimate (流量保号助手 - 完美内核版)
# 版本: 2.6.0 (新增: vnstat卸载、手动更新确认)
# GitHub: https://github.com/ioiy/xiaohao
# =========================================================

# --- 全局配置 ---
CONFIG_FILE="$HOME/.traffic_wizard.conf"
SCRIPT_LOG="$HOME/.traffic_wizard.log"
SCRIPT_PATH=$(readlink -f "$0")

# 默认下载链接
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
CURRENT_VERSION="2.6.0"

# --- 0. 初始化与配置加载 ---
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
LIMIT_RATE="0"        
IP_VERSION="auto"     
SMART_MODE="false"    
MONTHLY_GOAL_GB="10"
ENABLE_JITTER="true"

load_config() {
    if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi
    if [ -z "${URLS+x}" ] || [ ${#URLS[@]} -eq 0 ]; then URLS=("${DEFAULT_URLS[@]}"); fi
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
    # 优先 vnstat
    if check_vnstat; then
        local traffic_output
        traffic_output=$(vnstat -m --oneline 2>/dev/null | awk -F';' '{print $11}') 
        if [ -n "$traffic_output" ]; then
            echo | awk -v bytes="$traffic_output" '{printf "%.2f", bytes/1024/1024/1024}'
            return
        fi
    fi

    # 降级: 内核读取
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

check_load() {
    local load=$(cat /proc/loadavg | awk '{print $1}')
    local is_high=$(echo "$load > 2.0" | bc -l 2>/dev/null || awk -v l="$load" 'BEGIN {print (l>2.0)}')
    if [ "$is_high" -eq 1 ]; then return 1; else return 0; fi
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

# --- 2. 核心功能升级区 ---

# [升级] 检查更新 (手动选择模式)
check_update() {
    echo -e "${CYAN}正在连接 GitHub 检查更新...${NC}"
    local remote_url="https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh"
    # 增加加速源备用
    local remote_script=$(curl -s --connect-timeout 5 "https://ghproxy.com/$remote_url")
    if [ -z "$remote_script" ]; then
        remote_script=$(curl -s --connect-timeout 5 "$remote_url")
    fi

    local remote_version=$(echo "$remote_script" | sed -n 's/.*CURRENT_VERSION="\([0-9\.]*\)".*/\1/p')

    if [ -z "$remote_version" ]; then
        echo -e "${RED}检查失败：无法获取版本信息。${NC}"
        return
    fi

    echo -e "当前版本: v$CURRENT_VERSION"
    echo -e "最新版本: v$remote_version"

    if [ "$CURRENT_VERSION" != "$remote_version" ]; then
        echo -e "${YELLOW}发现新版本！${NC}"
        read -p "是否立即更新并覆盖当前脚本? (y/n): " confirm
        if [ "$confirm" == "y" ]; then
            echo "$remote_script" > "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            echo -e "${GREEN}更新成功！请重新运行脚本。${NC}"
            exit 0
        else
            echo -e "已取消更新。"
        fi
    else
        echo -e "${GREEN}当前已是最新版本。${NC}"
    fi
}

# [新增] 卸载依赖 (vnstat)
uninstall_dependencies() {
    if check_vnstat; then
        echo -e "${YELLOW}检测到系统安装了 vnstat。${NC}"
        read -p "是否同时卸载 vnstat? (y/n): " rm_vn
        if [ "$rm_vn" == "y" ]; then
            echo -e "${CYAN}正在卸载 vnstat...${NC}"
            if [ -f /etc/alpine-release ]; then
                apk del vnstat
            elif [ -f /etc/debian_version ]; then
                apt-get purge -y vnstat
                apt-get autoremove -y
            fi
            echo -e "${GREEN}vnstat 已卸载。${NC}"
        fi
    fi
}

# --- 3. 辅助功能 ---

install_dependencies() {
    echo -e "${CYAN}正在检测并安装依赖 (vnstat, curl, cron)...${NC}"
    if [ -f /etc/alpine-release ]; then
        apk update && apk add vnstat curl bash
        rc-service vnstatd start 2>/dev/null
        rc-update add vnstatd default 2>/dev/null
    elif [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y vnstat curl cron bc
        systemctl enable vnstat 2>/dev/null
        systemctl start vnstat 2>/dev/null
    else
        echo -e "${RED}未识别的系统，请手动安装 vnstat。${NC}"
        return
    fi
    echo -e "${GREEN}安装完成！${NC}"
    vnstat -u 2>/dev/null
    sleep 2
}

reset_stats() {
    rm -f "$SCRIPT_LOG"
    echo -e "${GREEN}统计数据已重置。${NC}"
    sleep 1
}

# [升级] 卸载脚本 (集成依赖卸载)
uninstall_script() {
    echo -e "${RED}${BOLD}警告：即将删除脚本、配置、日志及定时任务！${NC}"
    read -p "确定要继续卸载吗？(y/n): " confirm
    if [ "$confirm" == "y" ]; then
        # 询问卸载 vnstat
        uninstall_dependencies
        
        # 删除任务和文件
        crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
        rm -f "$CONFIG_FILE" "$SCRIPT_LOG" "$SCRIPT_PATH"
        
        echo -e "${GREEN}脚本及其数据已彻底清除。再见！${NC}"
        exit 0
    fi
}

# --- 4. 核心下载逻辑 ---
run_traffic() {
    load_config
    local target_mb=$1
    local mode=$2

    if ! check_load; then
        local load_msg="[熔断保护] 系统负载过高 (>2.0)，跳过本次任务。"
        echo -e "${RED}$load_msg${NC}"
        if [ "$mode" == "auto" ]; then send_telegram "$load_msg"; fi
        return
    fi

    if [ "$mode" == "auto" ] && [ "$SMART_MODE" == "true" ]; then
        local sys_usage=$(get_system_traffic)
        local is_limit_reached=$(awk -v u="$sys_usage" -v g="$MONTHLY_GOAL_GB" 'BEGIN {print (u >= g) ? 1 : 0}')
        if [ "$is_limit_reached" -eq 1 ]; then
            local log_msg="[智能模式] 流量($sys_usage GB) 已达标($MONTHLY_GOAL_GB GB)。停止运行。"
            echo -e "${YELLOW}$log_msg${NC}"
            send_telegram "$log_msg"
            exit 0
        fi
    fi

    if [ "$ENABLE_JITTER" == "true" ]; then
        local percent=$((RANDOM % 21 - 10))
        local offset=$((target_mb * percent / 100))
        target_mb=$((target_mb + offset))
        echo -e "${PURPLE}[拟人化] 流量随机波动生效: 目标修正为 ${target_mb} MB${NC}"
    fi

    local total_downloaded=0
    local count=0
    local target_bytes=$((target_mb * 1024 * 1024))
    local curl_opts="-L -s -o /dev/null -k --retry 2 --connect-timeout 10 --max-time 180"
    if [ "$LIMIT_RATE" != "0" ]; then curl_opts="$curl_opts --limit-rate $LIMIT_RATE"; fi
    if [ "$IP_VERSION" == "4" ]; then curl_opts="$curl_opts -4"; fi
    if [ "$IP_VERSION" == "6" ]; then curl_opts="$curl_opts -6"; fi

    echo -e "${YELLOW}[运行中] 目标: ${target_mb} MB | 限速: ${LIMIT_RATE:-无} | UA: 随机${NC}"
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
            echo -e " -> ${GREEN}成功块 #$count (累计约 ${current_mb} MB)${NC}"
        else
            echo -e " -> ${RED}下载失败，更换链接重试...${NC}"
        fi
        sleep $((RANDOM % 3 + 2))
    done
    echo -e "${GREEN}任务完成！${NC}"
    send_telegram "Traffic Wizard: 任务完成。本次脚本消耗约 $target_mb MB。"
}

# --- 5. 仪表盘与菜单 ---

show_dashboard() {
    load_config
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local load_avg=$(cat /proc/loadavg | awk '{print $1" "$2" "$3}')
    local script_u=$(get_script_monthly_usage)
    local sys_u=$(get_system_traffic)
    
    local status_text=""
    if check_vnstat; then status_text="${GREEN}vnstat(精准)${NC}"; 
    else status_text="${YELLOW}内核读取(重启清零)${NC}"; fi
    
    local percentage=0
    if [ "$MONTHLY_GOAL_GB" != "0" ]; then
         percentage=$(awk -v u="$sys_u" -v g="$MONTHLY_GOAL_GB" 'BEGIN {printf "%d", (u/g)*100}')
    fi
    if [ $percentage -gt 100 ]; then percentage=100; fi

    echo -e "${BLUE}====================================================${NC}"
    echo -e "         ${BOLD}Traffic Wizard Ultimate v${CURRENT_VERSION}${NC}        "
    echo -e "${BLUE}====================================================${NC}"
    echo -e " ${BOLD}系统状态:${NC} RAM: ${mem_used}/${mem_total}MB | Load: ${load_avg}"
    echo -e " ${BOLD}流量统计:${NC} 脚本: ${GREEN}${script_u} GB${NC} | 系统: ${YELLOW}${sys_u} GB${NC}"
    echo -e " ${BOLD}数据来源:${NC} $status_text"
    
    if [ "$SMART_MODE" == "true" ]; then
        echo -e " ${BOLD}智能进度:${NC} [${percentage}%] 已用 ${sys_u} / ${MONTHLY_GOAL_GB} GB"
    fi

    echo -e " ${BOLD}当前配置:${NC} 智能[$( [ "$SMART_MODE" == "true" ] && echo "${GREEN}开${NC}" || echo "${RED}关${NC}" )] | 波动[$( [ "$ENABLE_JITTER" == "true" ] && echo "${GREEN}开${NC}" || echo "${RED}关${NC}" )] | 限速[${CYAN}${LIMIT_RATE:-无}${NC}]"
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
        echo -e "5. 随机流量波动 [$( [ "$ENABLE_JITTER" == "true" ] && echo "${GREEN}开启${NC}" || echo "${RED}关闭${NC}" )]"
        echo -e "6. ${CYAN}一键安装 vnstat (推荐)${NC}"
        echo -e "7. 重置统计"
        echo -e "8. ${RED}完全卸载 (含vnstat)${NC}"
        echo -e "0. 返回"
        read -p "选择: " s_choice
        case $s_choice in
            1) read -p "Token: " TELEGRAM_TOKEN; read -p "ChatID: " TELEGRAM_CHAT_ID; save_config ;;
            2) read -p "限速 (如 2M, 500k, 0关): " LIMIT_RATE; save_config ;;
            3) read -p "1.auto 2.IPv4 3.IPv6: " ip_c; case $ip_c in 2) IP_VERSION="4";; 3) IP_VERSION="6";; *) IP_VERSION="auto";; esac; save_config ;;
            4) [ "$SMART_MODE" == "true" ] && SMART_MODE="false" || { SMART_MODE="true"; read -p "目标(GB): " MONTHLY_GOAL_GB; }; save_config ;;
            5) [ "$ENABLE_JITTER" == "true" ] && ENABLE_JITTER="false" || ENABLE_JITTER="true"; save_config ;;
            6) install_dependencies; read -p "按回车..." ;;
            7) reset_stats; sleep 1 ;;
            8) uninstall_script ;;
            0) return ;;
        esac
    done
}

main_menu() {
    while true; do
        clear; show_dashboard 
        echo -e " 1. ${GREEN}立即运行${NC} (手动)"
        echo -e " 2. ${YELLOW}定时任务${NC} (自动)"
        echo -e " 3. ${PURPLE}高级设置${NC} (环境/配置/卸载)"
        echo -e " 4. ${BLUE}检查更新${NC}"
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
            4) check_update; read -p "按回车..." ;;
            0) exit 0 ;;
        esac
    done
}

if [ "$1" == "auto" ]; then run_traffic "$2" "auto"; else main_menu; fi

#!/bin/bash

# =========================================================
# 脚本名称: Traffic Wizard Ultimate (流量保号助手 - 终极版)
# 适用环境: Alpine, Debian, Ubuntu (256M内存 NAT VPS)
# 功能: 智能补课、限速、IPv4/6切换、流量统计、TG通知
# =========================================================

# 当前脚本版本
CURRENT_VERSION="1.3.0"

# --- 全局配置与文件路径 ---
CONFIG_FILE="$HOME/.traffic_wizard.conf"
SCRIPT_LOG="$HOME/.traffic_wizard.log"  # 记录脚本累计跑了多少
SCRIPT_PATH=$(readlink -f "$0")

# 默认下载链接 (大文件)
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

# --- 0. 初始化与配置加载 ---

# 默认配置变量
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
LIMIT_RATE="0"        # 0 代表不限速，单位可以是 2M, 500k
IP_VERSION="auto"     # auto, 4, 6
SMART_MODE="false"    # 是否开启智能补课
MONTHLY_GOAL_GB="10"  # 月度目标流量 (GB)

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
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

# 检查并尝试安装 vnstat (智能模式依赖)
check_vnstat() {
    if ! command -v vnstat &> /dev/null; then
        return 1 # 未安装
    else
        return 0 # 已安装
    fi
}

# 获取本月系统总流量 (GB)，依赖 vnstat
get_system_monthly_traffic() {
    if check_vnstat; then
        # 尝试适配不同版本的 vnstat 输出
        # 方法：获取 json (新版) 或 解析 -m (旧版)
        # 这里使用一种较为通用的 grep 方法提取本月总流量 (RX+TX)
        # 注意：这只是一个估算值，用于智能判断
        local traffic_output
        traffic_output=$(vnstat -m --oneline 2>/dev/null | awk -F';' '{print $11}') 
        
        # 如果 oneline 失败 (旧版本 vnstat)，尝试解析文本
        if [ -z "$traffic_output" ]; then
             # 这是一个极其简化的 fallback，实际旧版 vnstat 解析比较复杂，这里暂定为 0
             echo "0"
        else
            # vnstat --oneline 输出通常是 bytes，需要转换
            # 但不同版本差异大，这里为了脚本稳健性，建议用户安装 vnstat 2.x
            # 简化逻辑：直接返回 vnstat 原始数值(Bytes) / 1024^3
            echo | awk -v bytes="$traffic_output" '{printf "%.2f", bytes/1024/1024/1024}'
        fi
    else
        echo "0"
    fi
}

# 记录脚本消耗的流量 (追加到日志)
log_traffic_usage() {
    local bytes=$1
    # 格式: 时间戳|消耗字节
    echo "$(date +%s)|$bytes" >> "$SCRIPT_LOG"
}

# 计算脚本本月消耗总流量 (读取日志)
get_script_monthly_usage() {
    if [ ! -f "$SCRIPT_LOG" ]; then echo "0"; return; fi
    
    local current_month_start=$(date -d "$(date +%Y-%m-01)" +%s)
    local total_bytes=0
    
    while IFS='|' read -r timestamp bytes; do
        if [ "$timestamp" -ge "$current_month_start" ]; then
            total_bytes=$(awk -v t="$total_bytes" -v b="$bytes" 'BEGIN {print t + b}')
        fi
    done < "$SCRIPT_LOG"
    
    # 转换为 GB
    awk -v b="$total_bytes" 'BEGIN {printf "%.2f", b/1024/1024/1024}'
}

# 发送 TG 通知
send_telegram() {
    local msg=$1
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="$msg" > /dev/null
    fi
}

# 获取随机 UA
random_user_agent() {
    local agents=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15"
        "Mozilla/5.0 (X11; Linux x86_64; rv:89.0) Gecko/20100101 Firefox/89.0"
        "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1"
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36 Edg/92.0.902.55"
    )
    echo "${agents[$RANDOM % ${#agents[@]}]}"
}

# --- 2. 核心运行逻辑 ---

run_traffic() {
    load_config
    local target_mb=$1
    local mode=$2 # 'manual' or 'auto'

    # --- 智能模式检查 ---
    if [ "$mode" == "auto" ] && [ "$SMART_MODE" == "true" ]; then
        if check_vnstat; then
            local sys_usage=$(get_system_monthly_traffic)
            # 简单的浮点数比较
            local is_limit_reached=$(awk -v u="$sys_usage" -v g="$MONTHLY_GOAL_GB" 'BEGIN {print (u >= g) ? 1 : 0}')
            
            if [ "$is_limit_reached" -eq 1 ]; then
                local log_msg="[智能模式] 本月系统流量($sys_usage GB) 已超过目标($MONTHLY_GOAL_GB GB)。停止运行。"
                echo -e "${YELLOW}$log_msg${NC}"
                send_telegram "$log_msg"
                exit 0
            else
                echo -e "${GREEN}[智能模式] 本月已用 $sys_usage GB，未达标，开始补课...${NC}"
            fi
        else
            echo -e "${RED}[警告] 开启了智能模式但未检测到 vnstat，将忽略智能判断强制运行。${NC}"
        fi
    fi

    # --- 准备运行参数 ---
    local total_downloaded=0 # bytes
    local count=0
    local target_bytes=$((target_mb * 1024 * 1024))
    
    # 构建 curl 参数
    local curl_opts="-L -s -o /dev/null --connect-timeout 5 --max-time 180"
    
    # 限速设置
    if [ "$LIMIT_RATE" != "0" ]; then
        curl_opts="$curl_opts --limit-rate $LIMIT_RATE"
        echo -e "${CYAN}已启用限速: $LIMIT_RATE${NC}"
    fi

    # IPv4/v6 设置
    if [ "$IP_VERSION" == "4" ]; then curl_opts="$curl_opts -4"; fi
    if [ "$IP_VERSION" == "6" ]; then curl_opts="$curl_opts -6"; fi

    echo -e "${YELLOW}[开始运行] 目标消耗: ${target_mb} MB${NC}"

    while [ $total_downloaded -lt $target_bytes ]; do
        local url=${URLS[$RANDOM % ${#URLS[@]}]}
        local ua=$(random_user_agent)
        
        # 估算本次下载量：限速模式下通过时间估算，或直接假设 50MB (非精准，但够用)
        # 为了更真实，这里直接下载并获取 HTTP code
        curl $curl_opts --user-agent "$ua" "$url"
        
        if [ $? -eq 0 ]; then
            # 简单累加：如果限速了，下载会变慢，但我们按每次成功大概 50MB 计算
            # *注：为了脚本轻量化，不做精准字节统计，采用估算法*
            local chunk_size=$((50 * 1024 * 1024)) 
            total_downloaded=$((total_downloaded + chunk_size))
            log_traffic_usage "$chunk_size" # 写入统计日志
            
            count=$((count + 1))
            local current_mb=$((total_downloaded / 1024 / 1024))
            echo -e " -> ${GREEN}成功块 #$count (累计约 ${current_mb} MB)${NC}"
        else
            echo -e " -> ${RED}下载失败或超时 (可能是网络波动或IP协议不通)${NC}"
        fi
        
        sleep $((RANDOM % 3 + 2))
    done

    echo -e "${GREEN}任务完成！${NC}"
    send_telegram "Traffic Wizard: 任务完成。本次脚本消耗约 $target_mb MB。"
}

# --- 3. 菜单界面 ---

settings_menu() {
    while true; do
        clear
        load_config
        echo -e "${PURPLE}=== 高级设置 ===${NC}"
        echo -e "1. 配置 Telegram Bot [当前: $([ -n "$TELEGRAM_TOKEN" ] && echo "${GREEN}已配${NC}" || echo "${RED}无${NC}")]"
        echo -e "2. 流量限速设置    [当前: $([ "$LIMIT_RATE" == "0" ] && echo "${YELLOW}不限${NC}" || echo "${GREEN}$LIMIT_RATE${NC}")]"
        echo -e "3. IP 协议偏好     [当前: ${CYAN}${IP_VERSION:-auto}${NC}]"
        echo -e "4. 智能补课模式    [当前: $([ "$SMART_MODE" == "true" ] && echo "${GREEN}开启 ($MONTHLY_GOAL_GB GB)${NC}" || echo "${RED}关闭${NC}")]"
        echo -e "0. 返回主菜单"
        echo -e "----------------"
        read -p "选择: " s_choice
        
        case $s_choice in
            1)
                read -p "Bot Token: " TELEGRAM_TOKEN
                read -p "Chat ID: " TELEGRAM_CHAT_ID
                save_config
                send_telegram "Traffic Wizard: 测试通知成功！"
                echo "配置已保存并发送了测试消息。"
                read -p "按回车继续..."
                ;;
            2)
                echo "请输入限速值 (例如 2M, 500k, 10M)。输入 0 为不限速。"
                read -p "限速值: " LIMIT_RATE
                save_config
                ;;
            3)
                echo "1. 自动 (auto)"
                echo "2. 仅 IPv4 (-4)"
                echo "3. 仅 IPv6 (-6)"
                read -p "选择: " ip_c
                case $ip_c in
                    2) IP_VERSION="4" ;;
                    3) IP_VERSION="6" ;;
                    *) IP_VERSION="auto" ;;
                esac
                save_config
                ;;
            4)
                if ! check_vnstat; then
                    echo -e "${RED}系统未检测到 vnstat！智能模式无法工作。${NC}"
                    echo "Debian/Ubuntu 安装: apt update && apt install vnstat"
                    echo "Alpine 安装: apk add vnstat"
                    read -p "按回车继续..."
                else
                    if [ "$SMART_MODE" == "true" ]; then
                        SMART_MODE="false"
                    else
                        SMART_MODE="true"
                        read -p "请输入每月目标流量 (GB，整数): " MONTHLY_GOAL_GB
                    fi
                    save_config
                fi
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

show_stats() {
    clear
    local script_used=$(get_script_monthly_usage)
    local sys_used=$(get_system_monthly_traffic)
    
    echo -e "${CYAN}=== 流量统计 (本月) ===${NC}"
    echo -e "脚本消耗 (估算): ${GREEN}${script_used} GB${NC}"
    
    if check_vnstat; then
        echo -e "系统总消耗 (vnstat): ${YELLOW}${sys_used} GB${NC}"
        if [ "$SMART_MODE" == "true" ]; then
             echo -e "智能目标: ${PURPLE}${MONTHLY_GOAL_GB} GB${NC}"
             # 计算剩余
             local remaining=$(awk -v g="$MONTHLY_GOAL_GB" -v u="$sys_used" 'BEGIN {print g-u}')
             if (( $(echo "$remaining > 0" | bc -l 2>/dev/null || awk -v r="$remaining" 'BEGIN{print (r>0)}') )); then
                 echo -e "距离目标还差: ${RED}${remaining} GB${NC}"
             else
                 echo -e "状态: ${GREEN}已达标，智能模式将暂停脚本运行。${NC}"
             fi
        fi
    else
        echo -e "系统总消耗: ${RED}未安装 vnstat，无法读取${NC}"
    fi
    echo -e "------------------------"
    read -p "按回车返回..."
}

# 定时任务 (保持不变，略微简化显示)
cron_menu() {
    echo -e "1. 添加计划 (每天自动跑)"
    echo -e "2. 删除计划"
    echo -e "3. 查看 Crontab"
    echo -e "0. 返回"
    read -p "选择: " c_choice
    case $c_choice in
        1)
            read -p "每天跑多少MB: " d_mb
            read -p "几点开始(0-23): " d_hour
            crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
            (crontab -l 2>/dev/null; echo "0 $d_hour * * * /bin/bash $SCRIPT_PATH auto $d_mb >> /dev/null 2>&1") | crontab -
            echo "已添加。"
            sleep 1
            ;;
        2)
            crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
            echo "已删除。"
            sleep 1
            ;;
        3) crontab -l | grep "$SCRIPT_PATH"; read -p "按回车..." ;;
    esac
}

main_menu() {
    load_config
    clear
    echo -e "${BLUE}Traffic Wizard Ultimate v${CURRENT_VERSION}${NC}"
    echo -e "当前模式: $([ "$SMART_MODE" == "true" ] && echo "${GREEN}智能补课${NC}" || echo "${YELLOW}普通模式${NC}") | 限速: ${CYAN}${LIMIT_RATE}${NC}"
    echo -e "--------------------------"
    echo -e " 1. ${GREEN}立即运行${NC} (手动)"
    echo -e " 2. ${YELLOW}定时任务管理${NC}"
    echo -e " 3. ${CYAN}流量统计面板${NC} (本月数据)"
    echo -e " 4. ${PURPLE}参数设置${NC} (限速/TG/IPv4/智能模式)"
    echo -e " 0. 退出"
    echo -e "--------------------------"
    read -p "请输入选项: " choice
    
    case $choice in
        1) 
            read -p "输入消耗流量(MB): " mb
            run_traffic "$mb" "manual"
            read -p "结束. 按回车..."
            main_menu
            ;;
        2) cron_menu; main_menu ;;
        3) show_stats; main_menu ;;
        4) settings_menu; main_menu ;;
        0) exit 0 ;;
        *) main_menu ;;
    esac
}

# --- 入口 ---
if [ "$1" == "auto" ]; then
    run_traffic "$2" "auto"
else
    main_menu
fi

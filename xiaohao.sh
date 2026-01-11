#!/bin/bash

# =========================================================
# 脚本名称: Traffic Wizard (轻量级流量消耗交互脚本)
# 适用环境: Alpine, Debian, Ubuntu (256M内存 NAT VPS)
# 功能: 交互式菜单、后台静默运行、定时任务管理
# =========================================================

# --- 全局配置 ---
# 测速文件列表 (大厂CDN，速度快且稳定)
URLS=(
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
NC='\033[0m' # No Color

# 获取脚本的绝对路径
SCRIPT_PATH=$(readlink -f "$0")

# --- 核心功能函数 ---

# 1. 下载核心逻辑 (直接消耗流量)
# 参数 $1: 目标流量(MB)
run_traffic() {
    local target_mb=$1
    local total_downloaded=0
    local count=0
    
    # 简单的防止并发导致卡死
    if [ -z "$target_mb" ]; then target_mb=100; fi
    
    echo -e "${YELLOW}[运行中] 目标消耗: ${target_mb} MB (不占硬盘)${NC}"

    while [ $total_downloaded -lt $target_mb ]; do
        # 随机取链接
        local url=${URLS[$RANDOM % ${#URLS[@]}]}
        
        # 估算每个文件大小(MB)，简单按50MB算，脚本不求精确，只求消耗
        # 使用curl下载到 /dev/null
        curl -L -s -o /dev/null "$url" --connect-timeout 5 --max-time 120
        
        if [ $? -eq 0 ]; then
            # 假设每次成功下载大约 50-100MB，这里保守计数增加 50MB
            total_downloaded=$((total_downloaded + 50))
            count=$((count + 1))
            echo -e " -> ${GREEN}成功下载第 $count 块 (累计约 ${total_downloaded} MB)${NC}"
        else
            echo -e " -> ${RED}下载超时或失败，重试中...${NC}"
        fi
        
        # 随机休眠 1-3秒
        sleep $((RANDOM % 3 + 1))
    done
    echo -e "${GREEN}任务完成！${NC}"
}

# 2. 添加定时任务
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

    # 添加新任务 (为了适配Alpine，明确使用/bin/bash)
    # 格式: 0 3 * * * /bin/bash /path/to/script.sh auto 500
    (crontab -l 2>/dev/null; echo "0 $start_hour * * * /bin/bash $SCRIPT_PATH auto $daily_mb >> /dev/null 2>&1") | crontab -
    
    echo -e "${GREEN}成功设置！每天 $start_hour 点将自动消耗 $daily_mb MB 流量。${NC}"
    echo -e "${YELLOW}提示: 请确保 cron 服务正在运行 (Alpine: rc-service crond start)${NC}"
}

# 3. 删除定时任务
del_cron() {
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    echo -e "${GREEN}已清除本脚本的所有定时任务。${NC}"
}

# 4. 显示菜单
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

# 检查是否为自动运行模式 (通过参数判断)
# 如果第一个参数是 "auto"，则直接在后台执行流量消耗，不显示菜单
if [ "$1" == "auto" ]; then
    run_traffic "$2"
else
    # 否则显示交互菜单
    show_menu
fi

# 🧙‍♂️ Traffic Wizard Ultimate (流量保号助手 - 完美内核版)

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Language](https://img.shields.io/badge/Language-Bash-green.svg)
![Version](https://img.shields.io/badge/Version-2.6.0-orange.svg)

**Traffic Wizard Ultimate** 是一个专为 VPS（特别是小内存 NAT VPS、Alpine 系统）设计的轻量级流量消耗脚本。它可以帮助你自动化消耗流量，防止 VPS 因闲置被服务商回收。

---

## ✨ 核心功能

* **🖥️ 交互式仪表盘**：启动即显示系统状态、内存/硬盘占用、实时流量统计及配置状态。
* **📊 双模流量统计 (Hybrid Mode)**：
    * **精准模式**：自动检测并调用 `vnstat` 数据库，重启不丢失数据。
    * **内核模式**：无依赖直接读取 `/proc/net/dev`，适合极简系统（重启后清零，但无需安装软件）。
* **🧠 智能补课模式 (Smart Mode)**：设定每月目标流量（如 10GB），脚本运行前自动计算剩余需求。如果本月已达标，自动停止运行，避免超额。
* **🌊 拟人化流量波动 (Jitter)**：开启后，实际消耗流量会在设定值的 ±10% 之间随机浮动，规避流量曲线死板被检测的风险。
* **🛡️ 熔断保护机制**：运行前检测系统负载（Load Average），如果负载过高（>2.0），强制跳过本次任务，防止小内存机器死机。
* **🚀 极致轻量 & 兼容**：完美支持 Alpine、Debian、Ubuntu 等系统。增加 SSL 证书忽略与重试机制，老旧系统也能跑。
* **🐢 流量限速**：支持自定义下载速度（如 `2M`、`500k`），模拟真实用户观看视频的行为。
* **📱 Telegram 通知**：任务完成或触发熔断/达标停止时，发送消息到你的 TG 机器人。
* **🧹 彻底卸载**：一键卸载脚本、配置文件、定时任务，并支持**选择性卸载 vnstat 依赖**，还你干净系统。
* **🔄 手动更新确认**：检测到 GitHub 有新版本时，显示版本号并由用户决定是否覆盖更新。

---

## 📥 一键安装/使用

推荐使用 `root` 用户运行：

```bash
curl -sS -O https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh && chmod +x xiaohao.sh && ./xiaohao.sh
```
如果无法连接 GitHub，可以使用加速源：

```bash
curl -sS -O https://ghproxy.com/https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh && chmod +x xiaohao.sh && ./xiaohao.sh
```

🎮 菜单功能说明
运行脚本后，你将看到如下菜单：

立即运行 (手动)：输入想要消耗的流量数值（MB），立即执行下载任务。

定时任务 (自动)：

添加计划：设置每天几点开始运行，以及每天的目标流量。

删除/查看计划：管理后台 Crontab 任务。

高级设置：

配置 Telegram Bot：填入 Token 和 Chat ID 开启推送。

流量限速设置：限制 curl 的最大下载速度。

IP 协议偏好：强制使用 IPv4 或 IPv6，或自动选择。

智能补课模式：设置月度总目标（GB），脚本将根据系统实际用量智能决策。

随机流量波动：开启/关闭拟人化波动。

一键安装 vnstat：自动识别系统并安装流量统计服务（推荐）。

重置/卸载：清理日志或彻底删除脚本（含 vnstat 卸载选项）。

检查更新：联网比对 GitHub 版本，手动选择是否更新。

⚙️ 配置文件
脚本会自动在用户目录下生成隐藏配置文件，升级脚本不会丢失配置：

路径：~/.traffic_wizard.conf

日志：~/.traffic_wizard.log

📋 常见问题
Q: 为什么显示 "系统总计: 0 GB (内核读取)"？ A: 这表示你没有安装 vnstat，或者网卡流量确实为 0。建议在“高级设置”中选择“一键安装 vnstat”，这样能获得重启不丢的精准统计。

Q: 智能模式如何工作？ A: 假设你设置月度目标 100GB。脚本每次运行前会检查 vnstat 数据。如果系统总流量已经达到 100GB，脚本会直接退出并通知你“已达标”，只有未达标时才会继续下载。

Q: 为什么下载会失败？ A: 脚本内置了多个大厂测速节点（Cloudflare, Tele2 等）。如果当前网络环境无法连接某个节点，脚本会自动重试或切换链接。

⚠️ 免责声明
本脚本仅用于 VPS 流量消耗测试或保号目的。

请勿在严禁跑流量的商家（如部分工单明确禁止的商家）上使用，否则可能导致封机。

作者不对使用本脚本产生的任何后果（如流量超额扣费、VPS 被封禁等）负责。

Star ⭐ This Repository if it helps you!

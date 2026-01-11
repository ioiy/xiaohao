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
curl -sS -O [https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh](https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh) && chmod +x xiaohao.sh && ./xiaohao.sh

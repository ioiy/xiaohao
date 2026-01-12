# 🧙‍♂️ Traffic Wizard Ultimate (流量保号助手 - 旗舰交互版)

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Language](https://img.shields.io/badge/Language-Bash-green.svg)
![Version](https://img.shields.io/badge/Version-2.9.3-orange.svg)

**Traffic Wizard Ultimate** 是一个专为 VPS（特别是小内存 NAT VPS、Alpine 系统）设计的轻量级流量消耗脚本。它可以帮助你自动化消耗流量，防止 VPS 因闲置被服务商回收。

**v2.9.3 更新亮点**：全新扁平化主菜单、易读日志查看器（自动转换 MB）、实时网速监视器、以及更强的 CDN 更新检测机制。

---

## ✨ 核心功能

* **🖥️ 交互式仪表盘**：启动即显示内存/硬盘占用、实时流量数据、以及所有开关的当前状态。
* **🕹️ 扁平化主菜单**：智能模式、限速、流量波动、IP偏好等常用开关直接挂载主菜单，点击即切换，无需进入二级菜单。
* **📊 易读日志系统 (Log Viewer)**：内置日志翻译器，自动将原始字节数据转换为 MB 显示，并标记任务状态。
* **📈 实时网速监视 (Live Speed)**：集成 `vnstat -l`，在终端内实时展示当前的上传/下载速率。
* **🧠 智能补课模式 (Smart Mode)**：设定每月目标（如 10GB），脚本运行前自动计算。若本月已达标，自动停止运行，防止超额扣费。
* **🌊 拟人化流量波动 (Jitter)**：流量消耗在设定值的 ±10% 之间随机浮动，规避流量曲线死板被检测的风险。
* **🛡️ 双模统计 (Hybrid Mode)**：支持 `vnstat` (精准/重启不丢) 和 `内核读取` (无依赖/重启清零) 双模式自动切换。
* **🔗 自定义链接**：支持用户添加自定义下载节点，与内置的大厂 CDN 节点混合使用。
* **🧹 系统工具箱**：包含一键安装依赖、重置统计、强制停止进程 (Kill Switch)、完全卸载等运维功能。

---

## 📥 一键安装/使用

推荐使用 `root` 用户运行：

```bash
curl -sS -O [https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh](https://raw.githubusercontent.com/ioiy/xiaohao/main/xiaohao.sh) && chmod +x xiaohao.sh && ./xiaohao.sh

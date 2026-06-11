<p align="center">
  <code>N1KO</code><strong>STATE</strong>
</p>

<h1 align="center">N1KO-STATE</h1>

<p align="center">
  <strong>A lightweight, native macOS menu bar system monitor.</strong><br/>
  <strong>轻量原生 macOS 菜单栏系统监控工具。</strong>
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#中文">中文</a> ·
  <a href="https://github.com/baogutang/N1KO-STATE/releases">Releases</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 12+" />
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/version-1.0.1-blue?style=flat-square" alt="1.0.1" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT" />
</p>

---

## English

**N1KO-STATE** lives quietly in your menu bar and surfaces the metrics that matter — CPU, memory, GPU, network, disk, battery, temperatures, and fans — without turning your Mac into a second monitoring workload.

Left-click the menu bar icon for the live dashboard. Right-click for settings, about, and quit.

### Highlights

| | Feature | Description |
|---|---------|-------------|
| 📊 | **Live metrics** | CPU cores, memory pressure, GPU utilization, disk I/O, network rates, battery health |
| 🌡️ | **Sensors** | Apple Silicon HID temperatures + Intel SMC fallback; peak temperature tracking |
| 🌀 | **Fan control** | Manual RPM with one-time admin authorization; temperature-based fan curve |
| 📈 | **History** | 24-hour trend charts (CPU / memory / network) at 30 s granularity |
| 🔔 | **Alerts** | Configurable thresholds for CPU, memory, temperature, disk space, battery |
| 🌍 | **Localization** | English, 简体中文, 繁體中文 |
| ⚡ | **Low overhead** | Visibility-driven sampling — idle ~0.3–0.5% CPU, ~20 MB footprint |

### Requirements

- macOS **12.0** (Monterey) or later
- Apple Silicon or Intel Mac

### Install

1. Download **`N1KO-STATE.dmg`** from [Releases](https://github.com/baogutang/N1KO-STATE/releases).
2. Open the DMG and drag **N1KO-STATE** to **Applications**.
3. First launch (ad-hoc build): **right-click → Open**, or run the included `修复打不开.command`.

> Fan control installs a small privileged helper (one administrator password, once). Without it, fan speeds are read-only.

### Build from source

```bash
git clone git@github.com:baogutang/N1KO-STATE.git
cd N1KO-STATE

# Universal release + DMG (for distribution)
./build_app.sh --dmg

# Fast local build (host arch only)
./build_app.sh --native

# Smoke test after build
./build_app.sh --native --smoke
```

Output: `build/N1KO-STATE.app` · DMG: `build/N1KO-STATE.dmg`

Optional Developer ID signing:

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notarytool-profile"
./build_app.sh --dmg
```

### Project layout

```
Sources/N1KOState/     App UI, monitors, settings
Sources/FanHelper/     Privileged fan-control daemon
Sources/SMCKit/        Vendored SMC client (MIT, beltex)
Localization/          en · zh-Hans · zh-Hant
Resources/             Info.plist, app icon
build_app.sh           Build, sign, DMG, smoke test
```

### Credits

- [SMCKit](https://github.com/beltex/SMCKit) — MIT © 2014–2017 beltex (vendored locally)

---

## 中文

**N1KO-STATE** 是一款原生 macOS **菜单栏系统监控**应用。它把 CPU、内存、GPU、网络、磁盘、电池、温度与风扇等关键指标收进菜单栏，自身占用极低，不会「监控你的 Mac 的同时再拖慢 Mac」。

左键点击菜单栏图标打开监控面板；右键打开设置、关于与退出。

### 功能亮点

| | 功能 | 说明 |
|---|------|------|
| 📊 | **实时监控** | CPU 核心、内存压力、GPU 利用率、磁盘 I/O、网速、电池健康 |
| 🌡️ | **传感器** | Apple Silicon HID 温度 + Intel SMC 回退；峰值温度追踪 |
| 🌀 | **风扇控制** | 手动 RPM（一次性管理员授权）；温度曲线自动调速 |
| 📈 | **历史趋势** | 24 小时图表（CPU / 内存 / 网络），30 秒粒度 |
| 🔔 | **告警通知** | CPU、内存、温度、磁盘空间、电量阈值可配置 |
| 🌍 | **多语言** | English · 简体中文 · 繁體中文 |
| ⚡ | **低占用** | 可见性驱动采样 — 空闲约 0.3–0.5% CPU、~20 MB 内存 |

### 系统要求

- macOS **12.0**（Monterey）或更高
- Apple Silicon 或 Intel Mac

### 安装

1. 从 [Releases](https://github.com/baogutang/N1KO-STATE/releases) 下载 **`N1KO-STATE.dmg`**。
2. 打开 DMG，将 **N1KO-STATE** 拖入「应用程序」。
3. 首次启动（ad-hoc 签名）：**右键 → 打开**，或运行 DMG 内的 `修复打不开.command`。

> 风扇控制需安装小型特权 Helper（仅需输入一次管理员密码）。未授权时风扇转速为只读。

### 从源码构建

```bash
git clone git@github.com:baogutang/N1KO-STATE.git
cd N1KO-STATE

# Universal 发布包 + DMG
./build_app.sh --dmg

# 本机架构快速构建
./build_app.sh --native

# 构建后冒烟测试
./build_app.sh --native --smoke
```

产物：`build/N1KO-STATE.app` · DMG：`build/N1KO-STATE.dmg`

### 致谢

- [SMCKit](https://github.com/beltex/SMCKit) — MIT © 2014–2017 beltex（本地 vendored）

---

<p align="center">
  <sub>N1KO-STATE · v1.0.1 · Made for macOS power users who want clarity without clutter.</sub>
</p>

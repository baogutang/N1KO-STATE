# N1KO-STATE 交接说明（2026-06-04 更新）

## 项目概览

| 项 | 值 |
|---|---|
| 路径 | `/Users/nikooh/gitHubProjects/N1KO-STATE` |
| 类型 | SwiftPM + `build_app.sh` 打 `.app` |
| Bundle ID | `com.n1ko.state.monitor` |
| 最低系统 | macOS 13（`Package.swift` / `Info.plist`） |
| 构建 | `./build_app.sh` 或 `./build_app.sh --native` |
| 产物 | `build/N1KO-STATE.app` |
| 安装 | `cp -R build/N1KO-STATE.app /Applications/` |

**功能：** CPU/GPU/内存/磁盘/网络/传感器/风扇/电池监控；SwiftUI 下拉面板（卡片/环形仪表盘两种样式）；设置窗口；多语言（en / zh-Hans / zh-Hant）；风扇手动控制。

---

## 已修复的问题

### 菜单栏不可见（P0，已修复 2026-06-04）

**根因：** macOS Tahoe (26.5) 记住了旧 Bundle ID `com.n1kostate.menubar.app2026` 的损坏菜单栏状态，新启动时恢复坏位置。

**修复（三个叠加问题）：**
1. **Bundle ID 卡死** → 更换为 `com.n1ko.state.monitor`，重置 Tahoe 菜单栏状态
2. **`LSUIElement=true` 错位** → 移除该 plist 键，改用 `NSApp.setActivationPolicy(.accessory)`
3. **`NSImage.lockFocus()` 过时** → 改用 `NSImage(size:flipped:drawingHandler:)` 现代 API
4. 旧 UserDefaults 自动迁移到新 Bundle ID 域

### FourCharCode 崩溃（已修复）

`FS!` 只有 3 字符 → 改为 `FS! `（4 字符，含尾部空格）。

---

## 风扇控制架构（2026-06-05 重写）

旧方案「每次 `osascript` 提权跑一次性 CLI」已替换为**常驻 root LaunchDaemon + NSXPC**（无 Developer ID，故非 SMJobBless，而是一次管理员授权手动安装 LaunchDaemon）。

| 组件 | 路径 | 作用 |
|------|------|------|
| `FanXPCShared` | `Sources/FanXPCShared/FanXPC.swift` | 共享 `@objc FanControlHelperProtocol` + `FanStatePayload(Codable)` + 常量 |
| `XPCAuditShim` | `Sources/XPCAuditShim/` | ObjC shim 暴露 `NSXPCConnection.auditToken`（SPI），用于客户端签名校验 |
| 守护进程 | `Sources/FanHelper/main.swift` | root 常驻，`NSXPCListener(machServiceName:)`，连接失效即写回 `FS!=0` |
| 客户端 | `Sources/N1KOState/Monitors/FanControlService.swift` | `NSXPCConnection(.privileged)`；首次写操作触发**一次**密码安装 daemon |

**安装位置（一次密码）：** `/Library/PrivilegedHelperTools/com.n1ko.state.monitor.helper`（544 root:wheel）+ `/Library/LaunchDaemons/com.n1ko.state.monitor.helper.plist`（644 root:wheel，`launchctl bootstrap system`）。

**Bug 修复（2026-06-05）：**
- **Bug1 过夜变手动**：根因是「切自动」走旧 osascript 取消/失败时 `FS!` 没写回。现：启动 / `didWakeNotification` / 30s 定时器都 `syncFromSMC()` 以 SMC 真值对账 UI；退出 `resetAllFansSync()`；**daemon 连接失效自动复位**（覆盖强杀/崩溃，OS 级保证）。
- **Bug2 每次弹密码**：常驻 helper，首次一次密码，之后免授权。
- **Bug3 低版本打不开**：`Package.swift` `.macOS(.v12)`；`Info.plist` `LSMinimumSystemVersion=12.0`；`SettingsView` 的 `.scrollContentBackground`（13+）用 `hiddenScrollContentBackground()` 守卫降级。

**安全说明：** ad-hoc 签名只能用 `identifier "com.n1ko.state.monitor"` 校验客户端（无 Team ID/anchor apple），属 sanity filter；暴露面仅风扇转速，影响面有限。`build_app.sh` 用 `codesign -i` 固定 identifier，**必须保留**否则 daemon 拒绝连接。

## 卸载 daemon（调试用）

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.n1ko.state.monitor.helper.plist
sudo rm -f /Library/LaunchDaemons/com.n1ko.state.monitor.helper.plist
sudo rm -f /Library/PrivilegedHelperTools/com.n1ko.state.monitor.helper
```

## 未完成功能

| 项 | 状态 |
|----|------|
| 温度曲线自动控制风扇 | 未做 |
| daemon 自身被 SIGKILL 时不复位（极罕见） | 可加 unclean 标记文件，本次未做 |

---

## 验收清单（需 macOS 12 真机/VM + 交互密码，本机 Tahoe 仅做静态验证）

1. macOS 12：双击启动、菜单栏出现。
2. 首次调风扇弹**一次**密码 → 之后调速/切换不再弹框。
3. 切自动 → `kill -9` → 重开仍是自动（daemon 失效复位 + 启动 `syncFromSMC` 双保险）。
4. 切手动 → 休眠唤醒 → UI 与 `FS!` 实际一致。
5. 退出 app → `FS!` 写回 0（风扇回自动）。

静态验证（本机可做）：
```bash
vtool -show-build build/N1KO-STATE.app/Contents/MacOS/N1KOState | grep minos     # 12.0
vtool -show-build build/N1KO-STATE.app/Contents/MacOS/n1ko-fanctl | grep minos   # 12.0
lipo -archs build/N1KO-STATE.app/Contents/MacOS/N1KOState                        # arm64 x86_64
codesign -d -vvv build/N1KO-STATE.app 2>&1 | grep Identifier                     # com.n1ko.state.monitor
```

---

## 构建与验证

```bash
cd /Users/nikooh/gitHubProjects/N1KO-STATE
pkill -x N1KOState || true
./build_app.sh --native
cp -R build/N1KO-STATE.app /Applications/
open /Applications/N1KO-STATE.app
```

**成功标准：** 菜单栏右侧出现 CPU/MEM/网速 widget；左键弹出下拉面板；右键有 Settings / Quit。

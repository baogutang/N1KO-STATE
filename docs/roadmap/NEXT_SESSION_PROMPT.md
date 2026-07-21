# Copy-ready prompt for the next Codex task

Copy the prompt below into a new task opened from the N1KO-STATE project.

```text
请在当前 N1KO-STATE 项目中继续路线的唯一 Next 工作包：WP6 — Release hardening residual evidence。

先完整阅读 AGENTS.md、docs/roadmap/README.md、01-audit-findings.md、02-target-architecture.md、
03-fullscreen-window-design.md、04-delivery-plan.md、research-sources.md，以及
docs/roadmap/evidence/wp4/2026-07-21/results.md、
docs/roadmap/evidence/wp5/2026-07-21/upstream-v0.26.0-audit.md、
docs/roadmap/evidence/wp6/2026-07-21/results.md。检查 git status，保留用户改动，以当前 checkout
与路线文档为权威来源。

WP0–WP5 的开发已完成；不要重写 Agent Island、不要恢复被否决的 N1KO 近似卡片，也不要整仓合并
Ping Island。生产入口必须继续使用迁移后的 NotchViewController/NotchView 和
DetachedIslandWindowController/DetachedIslandPanelView，并保留 N1KO 公共 API 双窗口全屏修复。
截至 2026-07-21 已审计 Ping Island v0.26.0；Qoder CN 桌面/CLI 已选择性迁移，registry 为 21
profiles。N1KO 已拥有 Claude pseudo-terminal runtime、Codex app-server stdio 双向传输、非 tmux
follow-up 和 process-tree/tmux focus suppression。

v1.0.18 已于 2026-07-21 从 `4ff76b1` 发布，GitHub Actions run `29799932353` 的 universal DMG、
DMG 验证、签名 Sparkle appcast 和 GitHub Release 全部成功，main 的 appcast 回写提交为 `c348a93`。
不要重复发布或移动 v1.0.18 标签，除非用户再次明确要求。

本包只补剩余真实证据：两个互相独立的 24 小时 monitoring-only / Agent-enabled soak，以及可获得
环境上的 notched/mixed-display、Intel/macOS 12、different-user、real SSH、VoiceOver、lock/unlock、
fast-user-switch 矩阵。短时 calibration 不能冒充 24 小时。此前 1,093 awake seconds 仍是 partial。
soak 必须使用隔离 preferences/history/runtime 和 N1KO_PERF_HEADLESS，不占用户 Menu Bar、不安装展示
surface；不得再打断用户正在使用的 Agent Island。

不得牺牲监控采样语义、历史、告警、风扇控制或 thermal safety；不得引入私有 CGS/SLS/SkyLight；
保持一个 AppDelegate、AppSettings/SettingsWindowController、UpdateController、
PresentationCoordinator 和 AgentSessionCoordinator。不要提交、push、tag 或发布，除非用户再次明确要求。

若所有残余矩阵确实完成并通过，才把 WP6 标记为 Complete；否则保持 WP6 为唯一 Next，并逐项记录环境、
命令、时长、结果和真实风险。
```

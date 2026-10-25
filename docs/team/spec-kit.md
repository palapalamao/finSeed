# Spec Kit 项目接入

选型：GitHub 官方 [github/spec-kit](https://github.com/github/spec-kit)，固定正式版 [v1.2.3](https://github.com/github/spec-kit/releases/tag/v1.2.3)，采用其自带 [Lean 模式](https://github.com/github/spec-kit/tree/v1.2.3/presets/lean)。本项目使用它组织较大功能的需求、计划和可追溯任务；代码实现仍由当前开发者或 Codex 执行，验收沿用现有工程工具。

核对日期：2026-10-25。安装与验证结果见本页最后一节及 `.specify/install-manifest.json`；没有填写成功的步骤不视为已完成。

## 为什么选它

- 官方发布稳定版本，支持已有项目、Windows PowerShell 和 Codex 的项目技能目录。
- Lean 把核心步骤缩成聚焦的 `spec.md`、`plan.md`、`tasks.md`，适合已有代码和已确认需求。
- 不依赖业务技术栈，可用于本项目 Fantom 后端与 React 前端的变更组织。
- 比较过 BMad 的角色式流程；当前已有产品、开发和测试聊天，先用 Spec Kit 串起工作产物，避免重复增加角色和流程。

安装范围仅为当前项目：工具环境放在 `.local/tools/`，生成的项目基础放在 `.specify/`，Codex 技能放在 `.agents/skills/`。MIT 许可随工具文件保留。本次不启用 Spec Kit 的 Git 扩展、远端 Issue 写入扩展或自动运行事件。

## 怎样用

你照常描述目标，例如“做新版驾驶舱的第一个可用版本”。经理先关联看板任务和已有设计，再按需要调用：

| 步骤 | Codex 技能 | 输入与结果 |
| --- | --- | --- |
| 明确范围 | `$speckit-specify` | 已有需求、任务 ID 与功能目录 → 聚焦的 `spec.md` |
| 规划实现 | `$speckit-plan` | 当前代码与规格 → `plan.md` |
| 拆任务 | `$speckit-tasks` | 计划与验收 → 有依赖顺序的 `tasks.md` |
| 实现 | `$speckit-implement` | 连续完成任务、相关测试和进度勾选 |
| 核对遗漏 | `$speckit-converge` | 对照规格与代码找未完成项；按影响补实现和验证 |

这些是聊天中的技能，不是终端命令。Codex 从仓库 `.agents/skills` 发现技能；若选择器尚未刷新，重新加载聊天或应用后再检查。来源：[OpenAI 技能文档](https://learn.chatgpt.com/docs/build-skills)。

默认功能目录为 `specs/<看板任务ID>-<简短名称>/`，由经理连同请求提供，例如：

```text
$speckit-specify
功能目录：specs/N02-cockpit-first-slice
引用任务：docs/team/board.md 的 N02。
复用已有驾驶舱 V1.1 需求，只做一个站点、一个能源、指标卡和下钻。
保持当前统计口径、原始历史和权限；覆盖中英文与手机。
```

已有确认和文档直接引用，不重写全套需求。小缺陷、文案与局部样式沿用复现、最小修改和相关验证的短流程，不强制创建三个文档。重要业务歧义才向用户询问；路径、普通实现细节和既定规则由经理补齐。

遇到失败先定位原因、修复并继续验证；只有确实需要用户决定或外部条件时才报告阻塞。现有用户指令与 `AGENTS.md` 的协作和效率规则继续适用，不因默认模板增加重复确认、逐步审查或新审批。

## 并行和交付

- 看板仍是唯一排期来源；`tasks.md` 只记录该功能内部执行项，看板链接它，不复制一份相互独立的完成状态。
- `.specify/feature.json` 是当前工作区的活动功能指针。并行开发各用自己的 worktree 和功能目录，不让两个聊天争用同一指针。
- 从包含接入文件的集成提交建立新工作区；接入尚未提交时，由经理明确复制已核对的项目工具文件。
- 不启动 Spec Kit 的自动代理编排。普通工作由当前负责人连续完成；需要额外聊天、消息或代理时遵循当次授权。
- 完成标志继续要求可运行结果和对应验证证据；文档生成、勾选任务和 `converge` 判断不能代替真实测试。

## 工具维护

本地管理入口：

```powershell
& .\.local\tools\spec-kit-venv\Scripts\specify.exe version
& .\.local\tools\spec-kit-venv\Scripts\specify.exe integration status --json
& .\.local\tools\spec-kit-venv\Scripts\specify.exe preset list
```

普通技能执行不必重新安装工具。升级时先在隔离目录检查新版本生成差异，保留 `.specify/memory/constitution.md` 的项目约束，不直接用初始化的覆盖选项更新活动工作区。工具环境和下载缓存不提交；业务版本号、前端依赖和 FIN 环境由原负责人维护。

## 验证状态

- CLI `1.2.3` 在项目专用 Python 环境中启动成功，依赖一致性检查通过。
- 已安装 10 个 Codex 项目技能，Lean `1.0.0` 生效；五个核心技能正文与固定版本的官方 Lean 模板一致（含 Codex 命令占位符展开）。
- 官方集成状态检查没有缺失文件、非法路径或未检查清单；它报告五个核心文件被修改的 warning，已确认全部来自官方 Lean 预设覆盖，未把该提示伪装为无警告状态。
- 隔离验证中，缺少活动功能、缺少任务文件均被拒绝；规格、计划、任务齐全时成功返回对应功能目录及 tasks.md。
- 项目约束已写入 `.specify/memory/constitution.md`。没有给活动工作区设置测试用功能指针，没有安装自动事件配置。
- 本次验证针对工具接入；未执行一个新产品功能的完整开发，也未重新验证产品业务或生产 FIN。现有干净安装阻塞仍由看板 N00 跟踪。

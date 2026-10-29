# 开发入口 / Contributing

先阅读 [AGENTS.md](AGENTS.md) 和 [团队工作方式](docs/team/README.md)。当前任务与负责人见 [任务看板](docs/team/board.md)，交接格式见 [工作模板](docs/team/templates.md)。

每项代码任务有一个交付负责人、可观察的验收条件和明确修改范围。优先交付一个完整的小功能或缺陷修复；并行开发使用独立工作区。已有确认不重复询问，普通改动不启动独立审查代理。

Start with one owner, a bounded change and observable acceptance criteria. Use an isolated checkout for concurrent implementation. Reuse agreed requirements and review according to risk.

## 分支流程 / Branch workflow

`developer` 是开发主分支，`main` 用于稳定发布。日常开发与修复默认直接在最新 `developer` 上进行；仅在并行隔离需要时拆出短期 `codex/<任务ID>-<简短名称>`，验证后合回 `developer` 并清理。发布时再按授权从 `developer` 合入 `main`。

Use the latest `developer` directly for routine development and fixes, and keep `main` for stable releases. Create a short-lived `codex/<task-id>-<short-name>` branch only when concurrent work needs isolation; merge it into `developer` after verification and remove it. Release integration into `main` follows the release owner's authorization.

需要并行隔离时的命令行示例；替换任务名称与工作区路径 / CLI example for isolated concurrent work; replace the task name and checkout path:

```powershell
git fetch origin
git worktree add -b codex/task-name ..\finSeed-task-name origin/developer
```

使用 Codex 托管工作区时，先刷新远端引用，再显式指定最新 `developer` 提交或 `origin/developer` 为 `create_worktree` 的 `ref`。已有分支不批量重建，接续任务先核对差异并按归属集成。

For Codex-managed worktrees, refresh remote refs and explicitly pass the latest `developer` commit or `origin/developer` as `create_worktree.ref`. Preserve existing branches and uncommitted work; reconcile their changes with `developer` before continuing them.

## 本地检查 / Local checks

仅检查团队工具与版本 / Team tooling and version metadata:

```powershell
node --test scripts/check-versions.test.mjs
node scripts/check-versions.mjs
```

前端改动，使用当前目录（旧版工作区为 `finSeed.pod/ts`） / Frontend changes; older checkouts use `finSeed.pod/ts`:

```powershell
npm --prefix enerCubix.pod/ts ci
npm --prefix enerCubix.pod/ts test
npm --prefix enerCubix.pod/ts run build
```

浏览器只运行受影响场景；新增界面覆盖中英文与手机。不要在其他开发者正在使用的工作区重新安装依赖或覆盖构建输出。
Run affected browser scenarios and applicable language/mobile checks. Avoid reinstalling dependencies or replacing build output in another worker's active checkout.

后端或发布候选沿用 [README 的构建与分层验收](README.md)。FIN SDK、许可和审计连接在受控的本地验收环境准备；GitHub 的前端检查不能代替 FIN 验收。
For backend changes or release candidates, follow the build and layered acceptance procedures in README. Hosted frontend checks do not replace licensed FIN runtime acceptance.

## 提交与交付 / Changes and handoff

使用功能／缺陷表单和 PR 模板，记录实际测试结果与未验证项。提交仅包括任务所需文件；不要整体暂存混杂工作区、原始业务数据、认证材料或生成的临时文件。版本与打包由发布负责人协调。提交、推送、合并和部署遵循本次任务授权。

Use the issue and PR templates, include verification evidence, and stage only task-owned changes. Coordinate versioning and packaging with the release owner. Follow the current task's authorization for publishing and deployment.

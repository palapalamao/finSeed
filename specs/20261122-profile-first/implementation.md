# 普通能耗概况首图 / Ordinary consumption profile first chart

实施基线：`2dee476dc08778fc6991f7be58c52802a44ef8d3`。本任务不修改发行版本、不替换生产 Pod，也不改驾驶舱。部署由集成负责人执行。

## 服务契约 / Service contract

现有 `POST /report` 增加可选 `responseMode: "chart" | "full"`。缺省仍执行原来的完整查询，Axon 和既有调用方无需修改。首版仅启用 `profile + energy + day + space + spaceSource=fin`，不启用单位面积、参考曲线、比较或 raw；不支持的选择继续原完整路径。服务端独立验证，客户端不能用 `_profileFirst` 强制启用。

The existing `POST /report` accepts optional `responseMode: "chart" | "full"`. Omission preserves the full report and existing Axon consumers. P0 admits FIN-space daily energy profiles without area normalization, references, comparison or raw mode. Other requests retain the original full path. The server independently validates eligibility and removes client-supplied `_profileFirst`.

## 统计边界 / Statistical boundary

完整当前配置仍参与分类、别名、关系、范围去重和数据质量判断。历史读取集合来自与原图相同的 `categories + scopeMeters`，只读各贡献表自己的主点；直接选择子表时仍读子表自身。清洗采用原算法及相同闭合区间；首图省去仅供原始观察/诊断使用的读数 DTO、小时 DTO、清洗明细、全成员明细和大覆盖证据。严格值、已有量、覆盖、NA、单位和贡献源保持原计算。

The complete current catalog remains authoritative for categories, aliases, relationships, scope deduplication and quality. The history plan uses the chart's existing `categories + scopeMeters` closure and each contributing meter's own primary point. Cleaning uses the same algorithm and authoritative closed intervals. The chart skips diagnostic-only raw/hourly DTOs, cleaning evidence, noncontributing member details and large coverage evidence; numeric, strict/known, NA, unit, coverage and source semantics are retained.

首图提示仅覆盖实际贡献源，明确标注完整来源诊断尚未读取。`extra.profileDelivery` 标识 `mode=chart`、`diagnostics=deferred`、独立随机快照编号及来源数量。固定字段的 `phaseMs` 只计准备、历史适配、计算和总服务耗时；不宣称是纯 Folio I/O 或包含网络、JSON 序列化及绘图。

First-chart warnings cover contributing sources only, with an explicit bilingual notice that full source diagnostics have not been read. `extra.profileDelivery` identifies the chart stage, deferred diagnostics, a random observation ID and source count. Bounded `phaseMs` fields measure preparation, history adaptation, calculation and total service work; they do not claim pure Folio I/O, network, JSON serialization or chart-rendering time.

## 独立读取与完整输出 / Independent reads and complete output

用户展开统计明细、选择完整诊断、导出或点击报表打印时，调用原完整路径并重新生成整份快照。沿用截止时刻并不能阻止 FIN 历史回补；新结果、图表、明细及生成时间一起替换，明确提示已经重新读取。不会把新诊断追加为旧首图的证据。完整读取失败时保留首图，可重试。原生浏览器打印无法等待异步网络，首图阶段仅打印指引；报表打印按钮先读取完整数据。

Opening statistics, requesting full diagnostics, exporting or using the report Print button invokes the original full path and rebuilds the whole snapshot. An unchanged cutoff cannot prevent FIN history backfills: the chart, details, result and observation time are replaced together with an explicit reread notice. New diagnostics are never attached as evidence for the old chart. Failed reads retain the chart and allow retry. Native browser printing cannot await an asynchronous read, so a deferred snapshot prints instructions instead; the toolbar Print action first reads full data.

并发保护同时使用工作台请求序号和按当前快照隔离的 pending 记录，迟到的旧查询不能阻塞或覆盖新快照。

Workspace sequencing and snapshot-scoped pending entries prevent an obsolete request from blocking or overwriting a newer snapshot.

## 验证层级 / Verification scope

- 后端隔离 SDK：首轮 5 类、48 方法、382 校验通过；最终兼容性修正后新首图 6 方法、56 校验再次通过，涵盖贡献点集合、默认 full、未知模式保留 full、私有参数清除、别名、多能源、缺测子表、拓扑、NA、替代、回卷和截止时刻。
- 前端类型检查、生产构建及 3 套 17 单元测试通过。
- 最终单 worker 受控浏览器 8 项通过，覆盖中英、桌面/390 px、按需请求、新完整快照、实际 Excel 下载、失败重试、浏览器打印保护、明细触发和迟到请求竞态。使用合成输出来检查 UI 契约，不冒充 FIN 实机速度或真实历史证据。
- 实际 FIN 的准确来源数、首图耗时、响应字节数、清洗版本及固定截止下的统计对账由集成负责人另行记录。新旧独立读取若遇回补，先说明快照差异，不宣称数据未变。

Backend evidence includes the initial 5 classes / 48 methods / 382 assertions and the final focused 6 methods / 56 assertions after the compatibility adjustment. Type checking, production build, 17 frontend unit tests and the final 8 single-worker browser scenarios pass. Browser tests use synthetic responses to verify the UI contract, bilingual/mobile layout, complete downloads and races; they are not live FIN performance evidence. The integrator separately records real FIN source counts, timings, response sizes, cleaning configuration and reconciliation, accounting for independently observed history/backfills.

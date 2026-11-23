# FIN 能源管理接口文档

## 0.16.0 原生授权与命名空间升级

当前技术命名为 `finEnergy`：安装包 `finEnergy.pod`、类型 `FinEnergy*`、Axon 函数 `finEnergy*`、API `/api/{project}/ext/finEnergy/v1`。产品自有标签统一为 `finEnergy*`，FIN 标准标签保留。下文0.14.37引用属于历史证据，不代表新版本已通过实机验收。

`GET license/status` 返回只读状态：`source:"fin"`、`status:"active"|"missingFeature"|"invalid"|"inactive"`、`feature:"finenergy"`、`canManageFinLicense`、管理员可见的可选 `hostId` 及可选原因。实机验收需要包含该精确功能标识的 FIN 许可证。授权更新与删除在 FIN 原生 Host 中操作，候选没有旧应用授权导入／删除／申请接口或表计免费额度。原生缺功能可停用整个扩展，此接口本身也不保证可用。

管理员迁移函数为 `finEnergyRenameNamespace("enerCubix","finEnergy",false)` 预览，携带返回的准确修订并传 `true` 明确应用，以及按原备份编号调用 `finEnergyResumeNamespace(backup)` 或 `finEnergyRollbackNamespace(backup)`。Folio、原生报警和自有图片分别备份、记录阶段；原 ID 与主点历史保留。预览指纹绑定迁移差异，独立摘要绑定完整恢复快照。普通采集值、确认状态及无关编辑保留。维护期间持续暂停能源任务及配置编辑，直到原日志完成或恢复，具体顺序见升级说明。

`409` 还包括 `LICENSE_REQUIRED`（原生能源功能不可用）和 `NAMESPACE_MIGRATION_REQUIRED`（旧项目尚须明确升级）。这些前置失败不能按普通模块缺项处理，也不能用旧快照伪装成新的查询成功。

**FIN 能源管理 0.16.0 候选 · FIN Framework 5.3.0.2761 · 简体中文版**

[English version](api.md) · [架构与模块设计](../docs/finenergy-architecture-design.md)

浏览器通过 FIN 的同源项目地址 `/api/{project}/ext/finEnergy/v1` 使用已认证的会话。JSON 调用使用 `haystack-nclient` 的 `finCsrfFetch`。当前用户、项目和访问权限由 FIN 提供。

POST 接收 `Content-Type: application/json` 的 JSON 对象。`report`、`cockpit` 和 `cleaning/preview` 是只读 POST 路由，其余 POST 路由要求管理员权限。迁移预览的 GET 和 POST 路由同样要求管理员权限。写操作按接口规定提交当前 `mod`。

正常响应为 HTTP 200，正文为 `{ok:true,data:...}`。应用错误返回非 2xx 状态和 `{ok:false,error:{code,msg}}`。图片路由成功时返回二进制内容。FIN 可在 FIN 能源管理分发请求之前拒绝过期会话或 CSRF 校验失败的请求。客户端还处理 FIN 重定向和非 JSON 错误。JSON 和驾驶舱图片使用 `Cache-Control: no-store`。普通 POST 请求体最多 2,097,152 字符，素材上传的 JSON 最多 3,145,728 个 UTF-8 字节。

| 状态 | 代表性错误码 | 处理 |
| --- | --- | --- |
| 400 | `INVALID` | 修正请求体、参数或引用。 |
| 401 / 403 | `SESSION` / `PERMISSION` | 恢复 FIN 会话，或检查项目和记录权限。 |
| 404 / 405 | `NOT_FOUND` / `METHOD` | 检查路由、HTTP 方法或引用的资源。 |
| 409 | `CONFLICT` | 读取最新版本或检查配置冲突。 |
| 413 | `TOO_LARGE` / `RESPONSE_LIMIT` | 缩小请求体，或缩小驾驶舱结果范围。 |
| 422 | 例如 `PREPARED_READ_LIMIT` | 查询触发资源保护。根据错误码缩小查询范围。 |
| 429 | `COCKPIT_BUSY` | 用户或项目的驾驶舱并发名额已占用。响应包含 `Retry-After: 2` 和 `error.retryAfterSeconds: 2`。 |
| 502 / 504 | `HISTORY_READ_FAILED` / `QUERY_TIMEOUT` | FIN 原生历史读取失败，或驾驶舱达到执行时限。 |
| 503 | `UNKNOWN` | 无法确认素材提交结果。再次发起写入前先读取当前素材状态。 |
| 500 | `INTERNAL` | 通过 FIN 日志定位错误。 |

### 路由索引

以下路由均相对于 v1 地址。

| 范围 | GET | POST |
| --- | --- | --- |
| 会话与目录 | `session`、`catalog`、`tree`、`points` | — |
| 原生授权状态 | `license/status` | — |
| 分析 | `comparison-scopes` | `report`、`cleaning/preview` |
| 驾驶舱快照 | — | `cockpit` |
| 驾驶舱预算与规则 | `cockpit/budgets`、`cockpit/rule-profiles`、`cockpit/config-audit` | `cockpit/budgets/save`、`cockpit/budgets/delete`、`cockpit/rule-profiles/save`、`cockpit/rule-profiles/delete` |
| 驾驶舱素材 | `cockpit/assets`、`cockpit/assets/image` | `cockpit/assets/upload`、`cockpit/assets/save`、`cockpit/assets/select`、`cockpit/assets/delete` |
| 配置 | `migration/preview` | `records`、`records/delete`、`tree/manage`、兼容路由 `tree/copy`、`tree/move`、`tree/toggle`、`migration` |
| 报警与消息 | `alarms`、`messages/changes` | `alarms/ack`、`tasks` |

服务端分发和权限入口及客户端处理见 [FinEnergyExt.fan](../finEnergy.pod/fan/FinEnergyExt.fan) · [FinEnergyRest.fan](../finEnergy.pod/fan/FinEnergyRest.fan) · [api.ts](../finEnergy.pod/ts/src/api.ts)。

GET `session` 自 0.12.16 起从已认证的 FIN 请求上下文返回 `{locale:string,username:string}`，其中 `username` 自 0.12.17 加入。前端在加载多语言界面前以同源凭据读取会话，并关闭缓存。默认使用 FIN 语言，可手动选择中文、English 或恢复跟随 FIN。本浏览器的偏好以当前已认证用户名区分。旧的全局偏好、浏览器语言和 URL 语言参数均不参与。界面文字、浏览器标题、日期控件、图表与导出使用同一语言。FIN 原生菜单始终跟随 FIN 用户。中文变体统一采用简体中文，未支持的语言回退英文。会话缺失、过期或不可读时停止启动。业务名称保留原文。

## 当前数据来源与版本边界

自 0.12.9 起，实测表、物理表和虚拟设备的用量统一读取该设备明确配置的主能耗点在 FIN 中的原生历史。FIN 负责采集与历史存储。FIN 能源管理负责读取、清洗、计算和展示，复用 FIN 的时序数据。未设置主点或主点没有历史时保留缺测。辅助历史、旧分钟批次、当前分表之和以及公式输入点的历史均不替代设备自身历史。贡献成员也分别读取各自的主点。

查询使用当前配置的关系。有效表计去重集合、范围、截止时间、指标与单位、清洗配置相同时，各视角和报表应得出相同的基础用量。改动草稿条件不改变已成功生成的报表及导出快照。查询清洗只作用于计算，缺测、NA、真实零和估算质量分别保留。

关系和分项两种能流模式的费用范围合计，与其他费用报表使用同一组选定主点表计的有效统计边界。`extra.energyFlowAccounting.basis:"meterCostScope"`、`memberIds`、`unionValue` 和 `unionQuality` 描述去重后的已有费用。贡献成员和共享引用只解释各自的图，所选设备的主点来源与去重费用保持独立。能流图仍沿用物理边界和贡献统计规则。虚拟总表缺少主点历史时同样保留缺测。

`FinEnergyMeterGeneration.update/ensure` 保留空实现，`publish/recalculate` 拒绝调用。`tasks` 接受 `scanAlarms` 和 `setAlarmEnabled`，`recalculate` 和 `setCalculationEnabled` 返回校验错误。停用历史生成时保留原有记录和绑定，删除、标记删除、重绑及迁移各自需要授权。当前值自动合计独立于历史报表，只更新当前计算结果，不写入历史。

包版本来自 `build.fan` 和各包清单。自 0.12.12 起，前端能够识别自身编译版本、检测后端版本差异并给出多语言刷新提示。版本化 HTML 入口避免继续加载旧界面。代码实现、本地验证、集成和部署是各自独立的证据层级。标为历史记录的章节用于识别已退出当前运行的旧行为。

## 驾驶舱快照

POST `cockpit` 是已认证的只读请求，使用与 `report` 一致的 FIN 原生会话和 CSRF 校验。查询范围仅限快照生成，配置保存、报警扫描及确认通过各自的操作接口进行。Pod 打包的原生应用入口打开带版本的资源，并进入 `#/cockpit?project=...`。旧概览仍可通过 `#/dashboard` 访问，前端能力开关可回退到该概览。

请求格式采用模式版本 1。

```json
{
  "schemaVersion": 1,
  "requestId": "client-sequence",
  "reportScope": {"dimension": "space", "nodeIds": ["native-space-ref"], "selectionIntent": "range"},
  "focusCategoryId": "energy-category-ref",
  "time": {"preset": "thisMonth", "period": "day"},
  "comparison": {"mode": "presetDefault"},
  "modules": ["kpis", "space", "trend", "time", "endUse", "organization", "balance", "efficiency", "issues"]
}
```

`dimension` 接受 `space`、`metering`、`organization`，`selectionIntent` 接受 `range` 或 `explicitObjects`。焦点对象属于客户端观察状态。`time.preset` 接受 `today`、`thisMonth`、`thisYear`、`custom`，自定义区间通过绝对时间 `from/to` 指定。新查询可省略 `asOf` 并由 FIN 服务端确定数据截止，结果快照冻结该截止。对比模式为 `none`、`presetDefault`、`previousMonth` 和 `custom`。默认对比中，今日采用上一日本地同一截止时间，本月和本年采用上一年同期，自定义时间不设对比。`previousMonth` 适用于 `thisMonth` 和 `custom`，在项目时区将两个端点各回移一个自然月，遇到缺少的日期按对应月底收敛。`custom` 对比必须指定参考区间的 `from/to`。返回区间注明月日对齐、闰日、夏令时与时长调整。变化率要求数据可比且参考值非零。

请求必须提供非空的 `requestId`（最多 200 字符）、1–200 个 `reportScope.nodeIds`、`focusCategoryId` 和非空的 `modules`。可选 `auxiliaryCategoryId` 必须不同于焦点能源分类。驾驶舱粒度为 `hour`、`day`、`month`。项目和时区取自 FIN 上下文。绝对时间使用带明确偏移量的 ISO 8601。未来 `asOf` 限制到服务器当前时间。

响应包含 `schemaVersion/snapshotId/requestId/generatedAt/context/provenance/boundary/modules/reports/quality/capabilities/limitations`。上下文包含项目时区与当前、参考区间的绝对时间。来源证据包含当前配置的 Ref/mod 指纹、设备自身主点历史依据、实际读取观测区间、采用的清洗方案快照、来源最后观察时刻以及流式读取限制。`sourceLastObservedAt` 是观察时间，历史完整性须依据覆盖信息。同一 `asOf` 重新查询时仍可能读到迟到的历史数据或更新后的配置。快照冻结本次结果，FIN 历史和配置仍按查询时读取。

`boundary.meterIds/sourcePointIds` 标识有效能源统计边界。同一集合、配置和时间范围在不同视角复用同一基础用量。显式选择重叠对象时保留各自明细，混合合计与比例遵循可加性校验。虚拟设备与其他设备一样读取自身明确配置的主点历史，贡献成员保持独立。

各可选模块包含 `status:ok|partial|empty|unavailable|error`、数据与原因码。缺少可选配置或个别模块发生普通故障时，其他模块的成功结果仍可用。输入无效、授权失败和请求资源不足影响整个请求。报表引用解析到同一响应内的 ReportResult 对象。

| 模块 | 冻结内容 |
| --- | --- |
| kpis | 四张指标卡、严格值和已有值、质量、比较及有条件的经营结论。缺少碳因子时，碳指标位置展示当前进行中的事件。 |
| space | 可读的原生空间层级、节点证据和已解析的能源统计边界。 |
| trend | 主要能耗概况报表的 `reportRef`。 |
| time | 各小时平均能耗报表的 `reportRef`、完整本地日热图、排除的不完整日，以及已配置工作日历的报表。 |
| endUse | 分项报表的 `reportRef`、有效表计 ID 和可加标记。沿用驾驶舱已解析的表计边界，未分项用量单列。 |
| organization | 当前组织层级、根 ID 和未分配组。上下级用量分别展示。 |
| balance | 现有能流报表引用及独立图 ID，图形、统计和共享来源沿用能流契约。 |
| efficiency | 适用 COP 配置的 Ref/mod、分子、分母、比值、服务边界与报表引用。使用总输出除以总输入。 |
| issues | 一次当前事件观测、稳定的持续事件及原生报警标识、分别记录的确认与恢复、只读小时证据及实际指标质量问题。 |

当前原生事件的观察时间独立于历史 `asOf`。选择对象和有效统计表计共同限定事件范围，选择实测总表仅纳入其所属范围内的事件。已确认但未恢复的事件仍在进行。事件证据可早于上层能耗区间，打开时按独立绝对时间请求并保留上层快照。消息中心通过 `eventId` 定位已有事件，沿用 FIN 报警和既有消息数据来源。

### 快照传输与资源保护

默认 JSON 响应将逻辑快照直接放在 `data`。请求 `payloadEncoding:"compact-v1"` 时，`data` 包含 `{payloadEncoding:"compact-v1",codecVersion:1,snapshot,evidence}`。随包交付的客户端使用该编码，在绘图和导出前解码。证据引用和表格压缩共享传输表示。紧凑模式下，服务端在 `diagnostics` 中提供受限的诊断明细，包括 `rowBudget`、`returnedCount`、截断状态和各项来源。明细截断与用量缺测需分别解读，业务值和汇总覆盖口径保持一致。客户端也可省略编码字段以获取普通 JSON。类型与解码实现见 [cockpitTypes.ts](../finEnergy.pod/ts/src/cockpitTypes.ts) · [cockpitPayload.ts](../finEnergy.pod/ts/src/cockpitPayload.ts)。

驾驶舱在单次请求内分块读取原生历史，准备可复用的汇总数据。当前上限为 200 个选定范围 ID、200 台有效设备、2 种能源分类、20 项适用 COP 配置，选择区间最多 366 个本地日，对比期独立解析。原始历史读取每块目标为 50,000 条样本，最多持有 200,000 条原始样本，累计最多扫描 20,000,000 条。准备和临时结构另有 200,000 条目预算。服务端执行检查期限为 30 秒，观察目标为 20 秒。序列化 HTTP 响应上限为 8 MiB。同一用户在同一项目可执行 1 个活动请求，每个项目可执行 2 个。服务端先组装并校验响应，触发资源保护时返回显式错误。独立 `report` 路由使用自身的历史样本限制。

### 驾驶舱配置和素材

| 路由 | 请求和响应 |
| --- | --- |
| GET `cockpit/budgets`、GET `cockpit/rule-profiles` | 返回 `{records,complete,canWrite,projectRef}`。记录按当前权限可见，判断列表是否完整前检查 `complete`。 |
| POST `cockpit/budgets/save` | 传入扁平对象 `name,scopeKind,scopeRef,categoryRef,enabled,month,currency,amount,distribution`，可选 `dailyAmounts`。更新时同时传 `id,mod`。返回已保存的预算。 |
| POST `cockpit/rule-profiles/save` | 传入扁平对象 `name,scopeKind,scopeRef,categoryRef,enabled,ruleType,threshold,thresholdUnit`，并按规则类型提供 `calendarRef` 或 `currency`。更新时同时传 `id,mod`。返回已保存的规则。 |
| POST `cockpit/budgets/delete`、POST `cockpit/rule-profiles/delete` | 传入 `{id,mod}`，返回 `{deleted}`。 |
| GET `cockpit/config-audit?targetId=...` | 返回 `{targetId,records}`，包含带版本的创建、更新、删除事件和可读取的变更前后值。 |
| GET `cockpit/assets` | 返回 `{projectId,items,manifestMod,selectedId,limits}`。 |
| POST `cockpit/assets/upload` | 传入 `{manifestMod,scopeId,name,base64,id?,mod?,clearHotspots?}`。替换已有热点的素材时须传 `clearHotspots:true`。 |
| POST `cockpit/assets/save` | 传入 `{id,mod,manifestMod,scopeId,name,hotspots:[{spaceId,x,y}]}`。坐标为相对于图片的归一化值。 |
| POST `cockpit/assets/select` | 传入 `{id,manifestMod}`，`id` 为 null 时清除选择。 |
| POST `cockpit/assets/delete` | 传入 `{id,mod,manifestMod}`。删除当前选中素材时同时清除选择。 |
| GET `cockpit/assets/image?id=...&hash=...` | 检查记录、范围与内容哈希后返回 PNG 或 JPEG 二进制。 |

预算和规则范围使用 `scopeKind:"project"|"space"`，关联项目 Ref 或有权读取的原生站点、楼层 Ref。预算月份为 `YYYY-MM`，币种使用三个大写字母，金额须为正数。`distribution:"uniform"` 表示逐日均摊，`"daily"` 表示为每个自然日设置一个非负金额，合计须等于月预算。匹配预算要求统计边界、能源分类、月份和币种一致。未满一日的部分按实际本地日时长计算，并考虑夏令时。快照保留 `periodBudget`、`monthBudget`、`periodActualCost` 及预算依据。正式 `variancePct` 和 `monthUsagePct` 要求费用覆盖符合条件。只有已有费用时，可返回 `referenceVariancePct`、`referenceMonthUsagePct` 并通过 `referenceBasis` 说明依据。

`nonWorkingHighUsage` 规则使用日历 Ref 和兼容的用量单位。`budgetVariance` 规则使用币种和 `%` 阈值单位。阈值须为非负有限数。快照提供规则的评估证据和原因。预算规则使用正式偏差。规则线索和 FIN 原生报警是两种独立的事件类型。

素材写操作返回更新后的素材目录。服务端检查 `manifestMod`，编辑已有条目时还检查 `mod`。支持 PNG 和 JPEG，每张图片最大 2 MiB、单边最长 4,096 像素、总像素不超过 800 万。每项目最多 10 个素材，每个素材最多 100 个站点或楼层热点。二进制读取使用目录的内容哈希并校验 FIN 权限。服务端从项目私有存储中的素材元数据解析文件名。

已部署的安装包、查询、受控浏览器验证、性能观察和延期验收见 [0.14.37 交付记录](../specs/cockpit-parity-20261101/final-handoff-01437.md)。

## 原生设备存储（0.4.0）

正常保存表计和传感器、批量分配和角色更改均写入 FIN 既有设备记录。记录 ID 为物理设备 ID，这条存储路径无需 `nativeEquip:true` 或模型 Marker。上级引用指向上游设备 ID，设备业务标量和引用通过同一记录上的可见 `finEnergy*` 标签持久化。正常保存直接更新原生设备。编辑保留的历史档案时，系统先修复其原生设备配置，验证引用、乐观并发版本和恢复快照，用户可继续正常编辑。共用费率、日历、表达式等项目配置使用自己的记录。

`autoSum?:boolean` 允许在既有主点 `pointId` 上计算当前累计读数，按各直属分表自基线后的增量累加。绑定表达式的虚拟设备以当前输入计算公式结果，写到符合条件的自有点位。添加、移除或重绑来源时从新基线开始。项目 `settings.meterRollupSeconds` 控制当前值更新间隔，允许 1–3600 秒的整数，缺省为 1 秒。后台检查串行执行，采集点位受写入保护。该路径只更新瞬态当前值和连续性状态。报表查询读取所选设备自身主点的历史。其他设置页保留无关设置和乐观并发版本 `mod`。

正常运行时，`catalog.storageModel` 为 `nativeEquip`。物理表计和传感器的 `id`、报表的 `nodeIds` 是 FIN 设备 ID，`pointId` 和报表的 `sourceIds` 仍是原生历史点 ID。三个视角使用同一设备记录。`finEnergyAlias` 保存简称，原生 `dis`、`navName` 保留。默认显示原生设备名称，设置 `useAlias:true` 且别名非空时才显示别名。设备关联使用已有的 `finEnergy*Ref` 标签，标量使用 `FinEnergyNativeEquip.scalars`，包括 `finEnergyArea`、`finEnergyMaximum`、`finEnergyHistoryMode`、`finEnergyIncludeInTotals` 等。下文的旧档案仅指仍保留的兼容数据。

纳入表计时提交既有设备 ID、已读取的 `mod`、类型、能源分类及显式绑定的自有兼容历史点 `pointId`。批量保存原子执行，同一设备的多条记录被拒绝。`tree/manage copy` 要求 `targetId`、`targetMod` 和目标设备的 `pointId`，复制配置写入目标设备。`records/delete` 和 `tree/manage delete` 取消纳入时移除本应用拥有的能源标签，保留设备、原生层级、点位和历史。创建原生虚拟设备时提供 `createVirtual:true`、`expressionId`、`siteId` 以及该站点下的 `floorId`。默认排除在汇总外。

普通表计创建使用 `createNative:true`、`kind:'totalMeter'|'meter'`、`name`、`categoryId`、`siteId` 与该站点下的 `floorId`。普通表计使用独立入口，直接创建原生设备和自有 Number 点，已有点绑定和表达式均不参与。两条记录在一次原子提交中生成，站点和楼层引用一致，使用能源分类单位或兼容的所选单位，包含 `his`、`hisTotalized`、站点或项目时区及 15 分钟历史采集间隔。`finEnergyPointRef` 指向新点。主表默认 `autoSum:true`、`includeInTotals:true`，创建时保留当前值和历史样本为空。表达式设备入口明确要求选择表达式。

原生导航提供 `nativeTreeParentId`。编辑已有设备保持 FIN 位置引用。`spaceId` 表示覆盖范围，缺省从安装位置推断。原生标签类型、点位归属、历史、能源、引用或拓扑无效时显示 `configurationError`，用量结果返回 `invalidConfiguration` 质量。刷新会直接读取最新的原生修改。

`migration/preview` 默认预览 `target:nativeEquip`，返回旧 ID、原生 ID、主点、上级设备、逐标签 `tagChanges`、冲突、配置 `revision` 和相关来源 `sourceRevision`。应用时检查两个版本，原子写入本应用拥有的标签、依赖引用重写、兼容别名、恢复快照和读取模式。应用后读取忽略旧物理档案。完成报表验证后，可用 `migration {action:finalize,jobId,mod}` 移除旧档案。`rollback` 恢复旧 ID、读取模式及迁移自身产生的变更，后续修改发生冲突时停止。历史报警来源记录保持不可变，旧报表 ID 通过兼容别名解析。`target:threeTree` 用于下文的旧迁移协议。

## 配置

`FinEnergyRecord` 是普通 JSON 对象。通用字段为 `id?:string,mod?:string,kind:string,name:string`，其余字段见下文。ID 使用不带 `@` 的 FIN Ref 字符串，存储时关系字段使用原生 Folio Ref。设备属性存储在原始设备的可见标量及引用标签上。共用项目配置使用独立 Folio 记录及 `finEnergyConfig` JSON。支持的 `kind` 包括 `space,organization,group,meter,totalMeter,sensor,category,subcategory,utility,tariff,calendar,expression,cop,template,settings,binding,job,alarm,cleaningProfile`。

- `space`、`organization` 的字段为 `parentId?,area?,description?`。上级与当前对象必须同为 `space` 或同为 `organization`。两套层级独立于旧分组和计量拓扑。
- `group` 的字段为 `parentId?,area?,description?,alarmLimits:[{categoryId,limit,enabled}]`。
- `meter`、`totalMeter`、`sensor` 的字段为 `parentId?,spaceId?,meterParentId?,organizationId?,canonicalId?,pointId?,categoryId?,subcategoryId?,utilityId?,tariffId?,expressionId?,area?,maximum?,includeInTotals?,actualEfficiency?,baselineEfficiency?,alarmEnabled?,alarmLimit?,unit?,description?,location?`。表计和总表的 `historyMode?:auto|cumulative|interval` 仅在 FIN 能源管理内指定历史的解释方式。同一点位的显式模式须一致。省略模式时采用 FIN 配置，包括单独设置的累计量 Marker `hisTotalized`。
- `category` 提供 `unit`。`subcategory` 提供 `categoryId,coalFactor,co2Factor,rawcoalFactor?,oilFactor?`。`utility` 提供 `categoryId`。折算因子为每单位分类能源的产出质量，标准煤以 kgce 计、二氧化碳以 kgCO2 计，原煤和石油以 kg 计。例如，0.1229 kgce/kWh × 240 kWh = 29.496 kgce。
- `tariff` 的字段为 `categoryId?,isDefault?,mode=flat|absolute|weekly|monthlyBlock|yearlyBlock,rate:number,rules:[{from?,to?,startHour?,endHour?,weekday?,rate}],exceptions:[{from,to,startHour?,endHour?,rate}],blocks:[{limit:number|null,rate:number}]`。
- `calendar` 的字段为 `isDefault?,peakHours:number[],valleyHours:number[],workHours:number[],workDays:number[],exceptions:[{date:string,working:boolean}]`，工作日采用 ISO 编号，从周一 1 到周日 7。
- `expression` 的字段为 `formula:string,variables:{[variableName]:meterRecordId}`。
- `cop` 的字段为 `numeratorId,denominatorId`。
- `template` 的字段为 `request:ReportRequest,preset?:thisWeek|lastWeek|thisMonth|lastMonth|thisYear|lastYear`。
- `settings` 的字段为 `visibleMetrics:string[],visibleCategoryIds?:string[],rotationSeconds:number`。`visibleCategoryIds` 控制概览轮播中的能源分类，省略时选择所有分类，`[]` 表示不选分类。费用、标准煤及二氧化碳轮播独立由 `visibleMetrics` 选择。
- `binding` 的字段为 `pointId,role=energy|reference|runtime,alias?`。
- `job` 的字段为 `action,enabled,status,from?,to?,message?,processed?,lastRun?`。
- `alarm` 的字段为 `nodeId,categoryId?,ts,value,limit,state=open|acknowledged,ackBy?,ackAt?,ackNote?`。

`spaceId` 表示空间覆盖，`meterParentId` 表示已确认的上游表计，`organizationId` 表示核算归属。三者分别对应 `finEnergySpaceRef`、`finEnergyMeterParentRef`、`finEnergyOrganizationRef`。`canonicalId` 和 `finEnergyCanonicalRef` 表示同一点位或表达式且同能源分类的旧兼容别名，指向规范表计或传感器。上游表计也必须为同一能源分类的规范表计。循环、缺失或不兼容的目标会被拒绝。新视角中一个物理点对应一条规范表计记录，既有重复记录可以保留为旧别名。表计的 `parentId` 和 `finEnergyParentRef` 只描述旧版分组。

GET `catalog` 返回 `{version,project,projectRef,cockpitConfigRefs,user:{name,canWrite},storageModel:'nativeEquip',spaceSource:'fin',nativeTreePath,nativeTreeWarnings:string[],records:FinEnergyRecord[]}`。`cockpitConfigRefs` 以 `{id,mod}` 列出可读且有效的驾驶舱预算、规则版本。每次请求直接读取当前原生 `legacy::NavTree.find(cx,"equip")`，保留导航名称、顺序、嵌套设备、叶子点位和 FIN 权限校验。页面或工作台刷新时重新读取该投影。GET 只读目录。

原生容器投影为 `kind:'space',nativeReadonly:true,nativeSourceId,nativeSourceKind,parentId`。ID 使用 FIN 原生 Ref，具有匹配 `migrationSourceId` 的已有 FIN 能源管理空间保持自身 ID。叶子点位投影为 `kind:'nativePoint',nativeReadonly:true,nativeSourceId,parentId,nativeDis,unit?,his?,pointKind?`，用于目录浏览。界面仅显示 `his:true` 的叶子点位，原生容器全部保留。已绑定的合格叶子点位在原始 FIN 叶子名称下显示其规范计量配置。旧手工空间保留在目录，并用 `nativeHidden:true` 排除出当前 FIN 树。

表计投影从当前点位上级附加瞬态 `nativeSpaceReadonly:true,nativeSpaceId?`。来源缺失或不可读时保留表计配置，标记 `nativeSourceMissing:true`，并取消当前覆盖。刷新保留已存记录、组织与上游引用。新增或修改绑定时将原生上级存为 Folio `finEnergySpaceRef`，无关编辑保留用于兼容请求的 `spaceId`。持久化前移除所有 `native*` 字段。原生容器和叶子点位拒绝结构编辑、移动、复制和删除。站点或楼层面积有下文限定的面积例外。未绑定和虚拟表计仍在全对象列表及其他维度中可用。

GET `tree?dimension=space|metering|organization|legacy` 返回 `{dimension,spaceSource,records:FinEnergyRecord[]}`。默认 `space`，并返回 `spaceSource:'fin'`，其余维度返回空 `spaceSource`。响应是扁平目录。空间和组织实体按同类 `parentId` 组织，表计按所请求维度的关系组织。新维度提供规范表计，`legacy` 包含原分组与兼容别名。

GET `points?q=&offset=0&limit=200` 返回 `{items:FinPoint[],total,offset,limit}`。`FinPoint` 为 `{id,name,unit,kind,his:boolean,hisMode?,source?,hisStart?,hisEnd?,curStatus?,hisStatus?,hisErr?,hisLastCollect?,navName?,equipId?,equipName?,equipNavName?,floorId?,floorName?,siteId?,siteName?,energyTags?:string[]}`。HTTP `limit` 允许 1–500，默认 200。关联名称和 ID 来自可读的原生引用，`energyTags` 包含原生 Marker。

POST `records` 请求体为 `{record:FinEnergyRecord}`，返回保存后的 `FinEnergyRecord`。更新必须提供当前 `mod`。

原生站点或楼层面积使用限定请求体 `{record:{id,mod,kind:'space',areaOnly:true,area:number|null}}`。只接受这些字段，要求管理员权限以及原生记录的读写权限。正有限数以 m² 为单位写入原 FIN 记录的 Number 类型 `area`，`null` 清除面积。写入仅限面积。FIN 原生面积及其缺省状态优先于旧覆盖面积，读取时将兼容的原生面积单位换算为 m²。

表计支持 `areaSource:'space'|'custom'` 和 `areaSpaceId`，分别对应 `finEnergyAreaSource` 和原生 Ref `finEnergyAreaSpaceRef`。空间模式显式引用可读的原生站点或楼层，并读取其当前面积。自定义模式使用 `area` 和 `finEnergyArea`，省略来源保留旧自定义面积。服务面积须明确设置，安装和覆盖位置独立保存。普通能耗读取无需有效面积。

当 `perArea:true` 时，报表冻结 `extra.areaBasis:[{nodeId,categoryId,name?,basis,baseValue,baseUnit,value,unit,area:{value,quality,unit:'m²',sources:[{id,name,area,source}]}}]`。同一服务空间和被包含的服务空间计一次，独立空间面积求和。多个边界未知的自定义面积返回 `ambiguousArea`，缺失或无效面积返回 `missingArea`，原用量仍可从 `areaBasis` 读取。每种能源分类使用自己的选定对象。`__selection__` 标识分类总计，`difference` 标识泄漏分析差额。单一分类的 `normalizationArea` 保留兼容的 `value/quality/unit` 字段，并补充来源。界面与导出使用冻结结果。

POST `records/delete` 请求体 `{id,mod}`，返回 `{deleted:id}`。被引用、被占用、成环或重复的配置会被拒绝。

POST `tree/copy` 或 `tree/move` 请求体 `{id,parentId,mod}`，返回 `{records:FinEnergyRecord[]}`。

POST `tree/manage` 仅管理员可用。`action=save` 接收 `{records:FinEnergyRecord[]}`，最多 200 条，在一次 Folio 提交前验证最终整批记录。新增或修改物理点绑定时，若该点已绑定其他表计则拒绝。迁移前的重复记录在修改其他字段时可保留未改动的来源引用。已有记录须提供当前 `mod`。

`action=move` 接收 `{items:[{id,mod}],parentId}`。同时选择祖先与后代时，后代仍留在所选祖先下。`action=totals` 接收 `{items:[{id,mod}],included:boolean}`，只作用于表计。每次修改原子执行，并按最终结构验证环路和主表唯一性。

新树使用 `tree/manage` 并提供 `dimension:'space'|'metering'|'organization'`。各动作如下。

- `action:'move',items:[{id,mod}],parentId:string|null`。移动表计只修改当前维度的 `spaceId`、`meterParentId` 或 `organizationId`。移动空间或组织修改其同类上级。`parentId:null` 清除本维度的关系，其他维度与旧分组位置保留。
- `action:'assign',items:[{id,mod}],patch:{...}`。批量更新规范表计。允许的 `patch` 字段为 `spaceId,meterParentId,organizationId,utilityId,categoryId,includeInTotals`，`null` 移除字段。提交前验证最终整批候选。
- `action:'copy',items:[{id,mod}]`。复制一个对象。表计和传感器还需提交未纳入的原生目标设备及其合格点位的 `targetId,targetMod,pointId`。服务端将配置保存到目标，清除复制的表达式和规范别名。复制非表计配置时生成新记录，清除来源与规范绑定，并排除在汇总外。保留的关系仍须校验。

省略 `dimension` 沿用旧树分组。原 `tree/move` 和 `tree/toggle` 也采用旧关系语义，`tree/manage` 支持指定维度操作。旧 `tree/copy` 复制分组层级，所复制的表计配置清除物理点、表达式及规范绑定，默认排除在汇总外。

`action=previewDelete` 接收 `{items:[{id,mod}]}`，返回 `{revision,roots,records:[{id,kind,name}],blockers:[{id,kind,name,referencedIds}]}`。预览纳入完整 FIN 能源管理子树。外部模板、表达式、COP 或其他配置引用阻止删除。`action=delete` 接收相同条目及预览版本，配置已变化时拒绝，成功返回 `{deleted:string[]}`。删除范围仅为 FIN 能源管理配置，保留 FIN 原生点位、设备和历史。报警、任务审计继续按既有事件保留规则处理。

工程界面可限定直属子级、所有后代或全对象。路径按所选维度的关系解析。拖放和批量移动共用后端校验。新物理表计默认纳入汇总，传感器排除，复用表计保留已存开关。规范化单位和原生 Marker 证据唯一一致时，向导才建议能源分类。批量存在歧义时须显式选择。简称使用明确的原生命名元数据，来源证据保留原名。计量能源分组只用于展示。桌面使用右侧检查面板，手机使用详情抽屉。高级单对象字段折叠时保留存量值。

## 原生 Axon 入口

| 函数 | 结果与权限 |
| --- | --- |
| `finEnergyAppUri()` | 当前 FIN 项目的应用入口 URI。 |
| `finEnergyInfo()` | 包含 Pod 名称、版本和当前用户的 Dict。 |
| `finEnergyCatalog()`、`finEnergyNativeSpaceInfo()` | 可读目录或受限的原生导航元数据。 |
| `finEnergyReport(json)`、`finEnergyCleaningPreview(json)` | 使用对应 HTTP 路由的查询或预览模型。 |
| `finEnergySaveConfig(json)`、`finEnergyManage(json)`、`finEnergyMigrate(json)` | 管理员配置操作。保存直接接收一条 `FinEnergyRecord`，管理和迁移接收相应动作对象。 |
| `finEnergyCleanHis(rec,dates,opts,yield,config:{})` | 原生计算历史函数，详见数据清洗章节。 |
| `finEnergyScheduled()`、`finEnergyScanAlarms(from,to)` | 管理员执行调度任务和有界报警扫描的入口。 |

目录、原生导航、报表、清洗预览、保存、管理、迁移、调度任务和报警结果为 `{result: JSON string}` 形式的 Dict。对 `result` 解析一次即可。这些函数共用对应 HTTP 接口的服务校验和原生权限。`finEnergyCleanHis` 通过原生回调输出历史条目。驾驶舱快照由 HTTP 路由提供。验收辅助和命名空间维护函数用于受控工程操作，见 [FinEnergyLib.fan](../finEnergy.pod/fan/FinEnergyLib.fan)。

## 三树迁移

POST `migration` 携带 `target:'threeTree'` 时使用本兼容协议，预览、应用和回滚均须携带该目标。默认迁移及 GET `migration/preview` 使用上文的原生设备迁移协议。两种协议均需管理员权限。POST `migration` 传 `{action:'preview',target:'threeTree'}` 时返回以下三树方案。

`{version:1,revision:string,sourceRevision:string,records:FinEnergyRecord[],suggestions:MigrationSuggestion[],warnings:string[],counts:{added,updated,canonicalAliases,spaces,suggestions,unboundMeters}}`。

`records` 包含自动新增记录和完整的编辑记录。`MigrationSuggestion` 为 `{id,type,title,reason,requiresConfirmation:true,records:FinEnergyRecord[],patches:object[],recordIds:string[],sourceIds:string[],count:number,placementRequired?:boolean,parentId?:string}`。建议类型包括 `legacySpace,nativeFloor,meterTopology,legacyGroup`。完整建议记录便于审阅，字段补丁允许组合空间与拓扑建议，各自的修改可独立应用。`placementRequired` 建议需要明确选择目标空间。

POST `migration` 传 `{action:'apply',target:'threeTree',revision,sourceRevision,acceptedSuggestionIds?:string[],placements?:{[suggestionId]:spaceId}}` 时应用自动记录、已接受的建议及显式位置。两个版本均须原样取自预览。服务端重新生成方案并对比 FIN 能源管理配置版本和原生来源元数据签名。发生变化时返回 HTTP 409 / `CONFLICT`，需要重新预览。未知建议 ID 或无效目标会被拒绝。位置键必须标识 `placementRequired` 建议，目标须为已有空间或接受建议中的新空间。重叠建议为同一表计指定的位置须一致。全部候选在一次 Folio 提交前校验。响应 `{applied:number,job:FinEnergyRecord|null}`，无修改时返回零且无任务。

仅有充分依据的站点根和有来源的空间位置会自动创建。只有所有已提供的原生 `submeterOf` 引用均明确映射到同能源分类的同一现有规范上游表计，且不会产生环路时，才继承关系。原生楼层名称也可能代表功能分组，按名称推断的楼层或楼栋位置仍须人工确认。总能耗、风机盘管等功能组需要显式目标，没有表计的分组保持未绑定。诸如 1#楼水表 的外层分组可给出批量拓扑建议，其上级为现有总表点的规范记录。共用分组或名称不足以自动建立计量拓扑。

同一点位的兼容别名接收 `canonicalId`。优先选择纳入统计且生效的总表为规范记录，否则以确定性规则选择既有记录，并保留一致的既有规范选择。不兼容的能源分类或表达式会产生警告。新空间 ID 使用确定性的项目限定 FIN Ref，应用后重新预览不会重复新增。既有分组、表计 `parentId`、原始点位绑定和旧汇总开关保留。迁移写入限于 FIN 能源管理配置。

已应用的迁移保留任务 `action:'treeMigration',status:'applied',migrationKey,processed`，并保留 `treeMigrationSnapshot` 任务记录中的配置前后值。POST `migration` 传 `{action:'rollback',target:'threeTree',jobId,mod}` 需要当前迁移任务的 `mod`，返回 `{rolledBack:number,job:FinEnergyRecord}`。回滚比对当前业务字段与保存的修改后状态，迁移记录已变更或缺失时返回 HTTP 409。服务端还验证恢复候选，若迁移新建的对象随后获得外部引用，则拒绝删除。回滚成功时原子恢复原记录、删除仅迁移产生的新增项，并标记任务为 `rolledBack`。审计和快照记录继续保留。此流程恢复 FIN 能源管理配置，原生历史备份独立处理。

## 报表

POST `report` 直接接收 ReportRequest 作为 JSON 请求体，在 `data` 中返回 ReportResult。以下示例使用从 `catalog` 取得的 ID。

```json
{
  "kind": "profile",
  "dimension": "metering",
  "nodeIds": ["meter-ref"],
  "from": "2026-10-01T00:00:00+08:00",
  "to": "2026-10-08T00:00:00+08:00",
  "asOf": "2026-10-08T00:00:00+08:00",
  "period": "day",
  "metric": "energy",
  "categoryId": "energy-category-ref",
  "perArea": false
}
```

ReportRequest 格式为 `{kind,nodeIds:string[],dimension?:'space'|'metering'|'organization'|'legacy',spaceSource?:'fin',from:string,to:string,asOf?:string,period:'hour'|'day'|'week'|'month'|'year',metric:'energy'|'cost'|'coal'|'co2'|'rawcoal'|'oil',perArea:boolean,categoryId?:string,flowMode?:'relations'|'endUse',scopeDimension?:Dimension,scopeNodeIds?:string[],referenceIds?:string[],otherFrom?:string,otherTo?:string,xId?:string,yId?:string,workHours?:number[]}`。日期使用带时区的 ISO 8601，区间为 `[from,to)`，时间桶采用项目时区。`kind` 支持 `profile|ranking|proportion|utility|daily|comparison|primary|cop|leak|workingHours|workingDays|regression|forecast|trend|dashboard|energyFlow`。对比和预测附加字段见下文，客户端完整格式见 `ts/src/types.ts`。空选项仅在文档所述概览和能流概览场景具有默认范围。缺测保留 `null` 和质量。

`asOf` 独立冻结数据截止，查询范围仍由起止时间决定。界面生成的时间戳使用其实际值。报表快照冻结请求、结果、清洗上下文及导出数据。Excel 长文本按单元格 32767 个 UTF-16 单元的限制分段，保留来源工作表、单元格和分段元数据以完整重建。桌面版 Excel 打开验证与 OOXML 检查分开记录。

`energyFlow` 采用 `flowMode:'endUse'` 时，按分项展示选定设备自身主点的用量。有关联的站点、楼层选择去重为可见范围，上游或重叠来源作为参考独立保留。平衡依据不足时保留用量和质量。当前选择规则取代旧版仅限根或首层的规则。

独立 `utility` 报表按当前关系将所选空间、组织或表计解析为合格末端表计。显式选择的末端表计即使未纳入自动汇总，仍可查看其自身用量。规范表计去重后，按分项汇总各参与设备自身主点历史的用量，并区分能源、单位和未分项组。边界重叠或比例无效时保留明细，隐藏混合图。驾驶舱的用途面使用自身已经解析的统计表计边界。

ReportResult 格式为 `{kind,from,to,asOf?,period,series:Series[],rows:object[],warnings:string[],summary:object,extra?:object}`。定义见 [请求和结果类型](../finEnergy.pod/ts/src/types.ts)。

`ranking` 保留请求起止范围，并返回其中满足闭合条件的已有源用量。不完整或缺测的对象仍保留各自行及质量。客户端继续接受旧响应的可选 `rangeAdjustment`。

`Series` 格式为 `{id,nodeId?,name,categoryId?,unit,points:[{ts:string,value:number|null,quality:string,sourceIds:string[],band?:string,x?:number,label?:string}]}`。普通表格行包含 `{key,nodeId,name,categoryId,unit,value,quality,sourceIds}` 和报告特有字段。存在 `summary.totals` 时，包含非参考系列的 `{id,name,categoryId,value,quality,unit,sourceIds}`。引擎负责汇总计算。

省略 `dimension` 或使用 `dimension:'legacy'` 时，旧分组、`parentId`、总表选择、开关和历史模板请求保持原语义。迁移保留旧报表请求的解释。

新空间报表和模板携带 `spaceSource:'fin'`，以 `nativeSpaceId` 解析当前 FIN 归属。没有该字段的兼容请求和模板使用已存空间配置。能源分析使用显式绑定主点的合格表计。来源缺失时产生警告并保留覆盖缺口。

新维度先将兼容别名解析为规范记录，再确定成员与依赖。`space` 按上述来源标志纳入所选空间及其下级表计，`organization` 使用核算归属子树。合计纳入合格的规范物理表计。当同一范围内已纳入确认的上游表计时，其下级从合计中排除。因此建筑范围可以使用建筑总表，楼层范围仍可读取自己的表计。`metering` 采用已确认的 `meterParentId`。单选表计时读取自身历史，泄漏分析仅扣除已确认的直属分表。

总表覆盖重叠尚未解决或上游拓扑无效、缺失时，合计返回 `value:null,quality:'topologyIncomplete'`。核算归属与另一归属的计量支路无法分离时，返回 `accountingIncomplete` 和空合计。历史缺失保留原有质量和来源证据。普通维度汇总报表附加 `extra.details:[{scopeId,nodeId,name,categoryId,value,quality,unit,sourceIds,counted:boolean}]`，在合计不可用时仍保留各表明细。`counted` 标识选定的计量拓扑边界。原始趋势和回归保留各自输出。

当前 `utility` 使用上述解析后的分项成员，支持合格的嵌套范围和计量选择。总表减分表所得差额独立于各用途组。`leak` 要求选择表计。可靠的物理泄漏判断还要求独立的物理边界和完整可用的数据。

各报表的专用字段如下。

- `leak`。每个时间桶的行保留 `total`、`submeter`、`difference`（总表减分表）和 `percentage`（差额除以总表乘以 100）。`extra.leakBranches:[{nodeId,branchId,name,categoryId,unit,ts,value,quality,sourceIds}]` 提供同一时间桶、同一单位下的各个合格直属分支。面积归一化时，两侧柱形均使用所选总表的面积。`extra.leakTotals` 提供相应区间合计以及普通行标识、质量与来源。图表并排展示总表柱和分表堆积柱，差额单列，负值保留并附警告。有分支缺测时，严格分表合计保留 `null`，图表继续展示其他分支的已有值和质量证据。差额序列保持兼容。周桶从项目时区的周一开始，首尾不完整桶只使用 `[from,to)` 内的数据。
- `dashboard`。`extra.overview:[{key,value,quality,sourceIds}]` 的 `key=categoryId|unit`。`extra.grandTotals:[{key,name,unit,value,quality,sourceIds}]` 的 `key=metric|unit`。总计仅合并相同单位，不兼容的能源单位单列。传入对比区间还会生成 `extra.comparisons`。
- `utility`。`extra.utilityShares` 按用途、能源分类和单位汇总解析后的成员主点用量，`extra.utilityMembers` 保留各设备自身值。所有当前视角均可选择明确的设备和嵌套范围，包括 `includeInTotals:false` 的设备。仅在集合可比且不重叠时生成共用饼图。重叠时保留各自用量，并隐藏依据不足的比例。`includeInTotals` 控制上级自动汇总，显式查询设备自身用量仍可用。分项与 `proportion` 的所选对象占比采用不同分母和分组。
- `daily`。点位附加 `band:'peak'|'valley'|'flat'|'unknown'`，行附加 `hour:number,ts:string,samples:number,band:string`。能源点展示请求区间内每天对应小时的平均能耗，`extra.aggregation='mean energy for each hour of day'`。`extra.loadBands` 保留普通行和 `band`，按时段分类统计区间能源合计，`extra.loadBandsAggregation='intervalTotal'`。此区间合计使用实际区间用量。缺少日历时使用 `unknown` 并提示。存在数据的瞬时值或比值时段返回 `null` 及 `invalidMetric`。
- `regression`。点增加 `x`，行包含 `{key,ts,x,y,value,quality,sourceIds}`，其中 `value=y`。`extra` 包含 `{slope:number|null,intercept:number|null,r2:number|null,count:number,equation?:string,xName:string,yName:string,fitLine:[{x:number,y:number}]}`。`fitLine` 使用 X 最小、最大值的拟合端点，无法拟合时为空。配对不完整时省略该对并提示。少于两组有效配对或 X 为常数时，系数保持 `null`。
- `comparison`。`extra.comparisons:[{id,name,current,reference,difference,percentage,quality,unit,referenceName?}]`。显式对比区间还会附加 ID 以 `|reference` 结尾的参考系列。
- 参考曲线。`profile`、`daily`、`utility`、`primary`、`leak` 和两期 `comparison` 使用 `referenceIds` 选择可读的传感器、绑定。响应行与系列使用 `role:"reference"`，采样证据在 `extra.referenceCurves`。参考曲线提供上下文，业务合计、折算、费率、占比和平衡只使用纳入统计的用量。
- `trend`。`extra.aggregation='raw samples'`，以 `{raw}` 读取所选对象自身 FIN 点位。保留 `[from,to)` 内原始时间戳、值和 null/NA 类型。趋势直接呈现原始采样，清洗、报表时间桶和子级历史独立处理。

## 计算引擎边界

Fantom 计算工作程序通过 `FinEnergyEngine.report([Str:Obj?] request, [Str:Obj?][] records, [Str:Obj?][] histories) -> [Str:Obj?]` 返回 ReportResult。每条历史格式为 `{pointId,unit,mode:'cumulative'|'interval'|'sampled'|'cov',samples:[{ts:ISO8601,value:Float?}],quality?:string}`，包含所需的前后边界值。点位范围和采样缺口均保留质量。引擎只使用传入的记录与引用，源历史保持只读。

## 任务与报警

FIN 扩展每秒检查配置的更新间隔。显式设置 `autoSum:true`（`finEnergyAutoSum:true`）的规范原生 `meter`、`totalMeter` 设备，可以按直属分表增量更新自身 `finEnergyPointRef`。绑定表达式的虚拟表可将当前公式结果写至符合条件的自有点。开关默认关闭，`finEnergyKind:totalMeter` 和上级关系本身不授予实测点覆盖权限。带任意 `*ConnRef` 采集标签的点始终受到保护，手工开启也不会覆盖，常规配置校验会拒绝此组合。实测中间表贡献自身读数。计算层从下向上评估，换算兼容单位，并排除传感器及别名。来源基线和累计连续性持久化，`finEnergyRollupRef/At/Status` 提供当前计算状态，`finEnergyRollupHasGap` 保留遗漏或不确定增量的证据。输入缺失、复位、分类或单位不兼容及循环，仅使受影响目标进入故障状态。FIN 负责主点历史采集。

POST `tasks` 请求体为 `{action:'setAlarmEnabled'|'scanAlarms',from?,to?,enabled?}`，返回任务 `FinEnergyRecord`。任务状态持久化到 Folio。报警扫描读取主点历史，可更新报警和任务记录。已停用的 `recalculate` 和 `setCalculationEnabled` 在创建任务之前拒绝。原生采集由 FIN 负责。

GET `alarms` 返回 `FinEnergyRecord[]` 报警记录。POST `alarms/ack` 传入 `{id,mod,note}`，返回已确认的 `FinEnergyRecord`，操作者取自 FIN 会话。

## 界面

桌面端提供侧边栏、可选分析树、筛选和报表工作区，手机端折叠导航。登录和用户管理沿用 FIN，界面使用随包主题，报表使用项目实际数据。已有业务配置类型均有表单，复杂费率和日历规则有结构化编辑器。Pod 资源服务在部分 FIN 构建中拒绝普通查询参数，因此将 FIN 项目放在哈希查询 `#/profile?project=...`。

### 对比区间对齐（0.2.9）

`comparison` 可选 `comparisonAlignment: "duration" | "calendarMonth"`。`duration` 要求两期时长严格相等，仅支持 hour/day/week，并从各自区间起点生成等长汇总桶；`calendarMonth` 要求两期均为完整自然月且 period=month，保留月份实际天数。未传参数的旧请求继续使用原自然时间桶与区间。`comparisonPreset` 由前端模板解析，后端以已解析的 from/to/otherFrom/otherTo 为准；日期控件包含结束日，传输仍使用左闭右开区间。图表按桶序配对，不移动或改写原时间戳。

### 对象对比基准（0.2.10）

同一时段的 comparison 请求可指定 `baselineId`，它必须属于 `nodeIds`；三维请求按同样规则规范化该引用。后端按对象及能源分类、单位匹配基准，返回 comparisonBaselineId/Name，以及 comparisons 中的 referenceId/Name、current/reference、difference、percentage 和 percentageQuality。缺失或不兼容时保留系列并提示，差值及变化率为空；零基准变化率为空。未提供 baselineId 的旧请求继续按首对象比较。模板将该引用保存为 Folio 依赖 Ref。新页面统一使用 nodeIds 选择对象，旧模板可继续带 referenceIds。

### 能耗预测（0.3.0）

`kind: "forecast"` 使用 `metric: "energy" | "cost"`、`period: "day"`，`from/to` 为项目时区中 28–180 个完整日的训练区间（结束不含），截止不得晚于今天零点。选择 1–10 个表计或统计范围，`forecastDays` 取 7（默认）、14、30。`trainingDays`、`forecastRolling` 保存前端模板意图，服务端以解析后的日期为准。源历史只读，计算前剔除训练截止后的样本；累计读数在截止时的精确边界可以使用。

费用预测先用各规范表计的完整每日费用独立拟合，再汇总同一成员集合，模型标记为 `meterSum`；空间／组织仅改变分组，不能改变成员预测。`summary.forecastTotals` 提供去重的预测费用合计，`extra.forecastMeterIds` 保存成员，`forecastBasis:historicalMeterCostPatterns` 明确其为历史费用模式估计，不包含未来费率调整，不是账单。误差参考半宽为成员误差范围之和，合并回测仅使用共同的历史留出样本；费用预测不支持面积归一化。

至少需要 28 个有效日、80% 完整率、每星期位置三个有效日及最近七天完整数据。按预测长度最多留出四个不重叠的滚动回测区间，每次仅用此前历史训练；比较上周同期、近期同星期加权均值、周周期加权衰减趋势，以 MAE 选择，复杂模型须改善超过 2%。30 天预测需要至少 44 个日历日才能形成一次回测。WAPE 在实际用量合计为零时返回空值。模型选择与评估共用这些历史留出区间，回测误差不是独立测试集或未来准确率保证。

系列增加 `role: "history" | "forecast"`；预测点质量为 `predicted`，包含 `lower/upper`；明细增加 `phase/model`。`extra.forecasts` 返回各对象预测合计、模型、MAE、WAPE、基准 MAE、样本覆盖、状态及模拟来源标记；`extra.backtests/modelScores` 保留回测证据。每日参考范围采用所选模型回测绝对误差第 90 百分位，不保证未来覆盖率。数据不足时保留历史、无预测系列并给出原因。模型不使用天气或运行计划，各对象独立预测，不能重复合计总分表。图表、表格及导出使用同一结果。旧 `regression` 接口、链接和模板仍保留兼容。


### 数据清洗（0.10.0）

`records` / `records/delete` 支持 `kind:"cleaningProfile"`。字段为 `name`、`mode:"drop"|"replace"|"rollover"`、`parameters`、`version`，修改同时提交原 `mod/version`。通用初始参数为 `{deltaMin:0,timeMax:"1h",defNull:true}`，没有默认最大增量。清空可选参数即删除规则。`defNull/removeNA:true` 写入原生 Marker，关闭时移除标签。普通数值按源点单位解释；带单位数值为 `{type:"number",value:0,unit:"kWh"}`。`defVal` 必须用此显式数值类型或 `{type:"na"}`，后者表示真实 Haystack NA。回卷周期为数值（0..32767 的计数器填 32768），并必须设置有效的正增量或变化率上限。

设备配置增加 `cleaningEnabled/cleaningProfileId`，分别持久化为设备上的 `finEnergyCleaningEnabled` Marker 和 `finEnergyCleaningProfileRef`。主点使用 `hisFunc:"finEnergyCleanHis"`、原生 Dict `hisFuncConfig`、`hisFuncWritable` Marker，以及 `finEnergyCleaningOwned/ProfileRef/ProfileVersion/EquipRef/Original/Applied/Rollover` 标签。现有手工历史函数返回 `cleaningStatus:"externalFunctionManaged"`，不会被接管。取消纳入或关闭清洗只恢复本模块拥有的设置。方案修改和引用点更新为同一次 Folio 乐观并发提交。

内置函数 `finEnergyCleanHis(rec,dates,opts,yield,config:{})` 和报告共用主点自身原始历史的读取核心。正常用量按 `[from,to)` 输出区间开始时间戳；内部差分证据保留结束读数时间，仅转换一次。手工 `hfTotalized` 在 `hisMode:"consumption"` 下的开始戳不会再次前移。显式 `{raw}` 始终读取原始历史。新查询应用当前已保存且通过校验的清洗方案，显式参数覆盖优先；关闭清洗后不再应用旧方案。外部历史函数保留自身输出约定，未知外部函数必须明确声明累计或区间类型。旧报告快照及其导出保持冻结，显式预览使用候选配置且不写入历史。普通查询不优先读取旧用量批次或辅助归档，不按当前子表或公式输入替代所选设备的主点历史。

POST `cleaning/preview` 接收 `{nodeId,from,to}`，也可明确传 `pointId/profileId/profile`；只读用户可使用。范围大于零且最多31天，返回 `raw/cleaned/details/summary/profileSnapshot`，不改写历史。`valueType:"number"|"null"|"na"` 区分零、缺值与 NA。调试明细记录原始值、前值、时长、触发原因及替代标记。

报告 `extra.cleaning` 保存方案ID、版本、完整参数、来源及过滤/替代/NA计数和覆盖率。`filtered` 用量表示有效小计，`substituted` 表示含替代值；NA 传播为 `value:null,valueType:"na",quality:"na"`。不完整小计可用于明确标注的已有用量平均、最高及已有用量占比；完整范围指标、COP、差额和阶梯费率继续执行完整性校验，重算不会写成完整实测值。报告中的异常明细最多1000条，并返回 `detailsTruncated`；预览保留所读范围的调试明细。已有导出快照保留生成时参数与结果。

### 能流图

`kind:"energyFlow"` 要求明确的有单位能源分类 `categoryId`。支持 `dimension:"metering"|"space"|"organization"`、`metric:"energy"|"cost"`，`perArea` 须关闭。`flowMode:"relations"` 为默认，按当前计量、空间或组织关系展示。`flowMode:"endUse"` 按参与表计的分项用途展示。兼容调用可传 `scopeDimension/scopeNodeIds` 指定视角和范围。空 `nodeIds` 使用对应视角的概览入口，显式选择则使用指定可读范围或表计。计量概览以同能源、允许汇总且无上级的总表为入口。

`extra.energyFlowGraphs` 按对象返回独立图。每图包含 `graphId/objectId/basis/rootIds/nodes/links`，以及 `contributionMemberIds/sharedMemberIds/additive/boundaryQuality`。`extra.energyFlow` 提供兼容展示。`extra.energyFlowOverview` 按全区间保留各对象用量与覆盖。`extra.energyFlowCoveredScopes` 在适用时列出已由上级覆盖的范围。节点和连线携带质量及来源。空间、组织分布与物理计量差额分别解释，覆盖不足时保留已有量。

虚拟总表自身读数来自自己的主点。公式贡献边界与自身读数分别展示。多个可加分类可以共享引用表计，`extra.energyFlowAccounting` 通过 `sharedMembers` 展示共享贡献，并在边界可验证时提供去重 `unionValue`、`unionQuality` 和 `basis:"classificationUnion"`。是否可以直接相加以 `canAdd` 为准。物理和虚拟混选、加权减法或无法确定统一边界时保留独立图和来源。费用合计采用 `meterCostScope`，物理漏损资格在费用模式下关闭。

前端在同一快照内下钻和返回，图表、明细和导出使用同一查询证据。报表读取当前计量关系及明确绑定的主点历史，历史关系变更记录供审计。

### 历史记录：0.11.x 对象归档与生效关系（已被当前主点只读规则替代）

以下保留旧协议用于识别既有证据和数据；自 0.12.0 起关系按当前配置解释，自 0.12.9 起停止辅助用量归档与重算。不得据此调用旧生成、发布或历史修正路径。

0.11.1 修正正式报告入口：`leak/energyFlow` 的历史关系分段由服务端从生效快照注入，不接受客户端伪造该内部证据。能流图进一步按各表自身历史的共同区间边界区分完整时段、缺测或异常时段与尚未发布的末段；不同采集间隔不要求时间戳逐条相等，不分摊不完整区间，也不将缺口变为零。历史快照中同一源点的原生表计与旧档案按当时保存的绑定消除重复，不使用今天的关系推定过去。

0.11.2 默认展示全查询区间总览，原始 `from/to` 保留；不再默认将最长完整子时段当作整周结果。`extra.energyFlowOverview:{from,to,unknownTopologySeconds,rows}` 与顶层 `rows` 独立列出各表自身历史，绝不合计总表和分表。每行提供 `value/quality/valueType/complete/coverage/activeSeconds/coveredSeconds/removed/sourceIds/periods`；覆盖率按时长计算，只累计完整落在查询及生效范围内的自身用量区间，累计读数的跨界区间不插值补算。`periods` 保留合并后的质量时段、缺口和源点，零、NA、过滤与替代分别保留。增删、迁移和换绑使用各自生效配置；历史成员仍列出其有效期数据，换绑不混用当前点，分类单位变化先换算为统一单位。旧关系未知时依然读取各表自身历史，但不生成流线、差额或泄漏结论。切换关系时段后，图、表及导出只使用该段快照，并移除全区间总览及不适用于该段的清洗摘要。

生成端在已结束的整分钟区间上处理自身采集、直属子表或公式输入，保留一分钟采集等待；每次每个对象最多追赶四分钟。输入按时间覆盖对齐，允许的一小时以内边界分摊标记为 `estimated`；缺测、NA、重置、过滤及替代值保留各自质量，不能变为零或完整实测。虚拟子表使用自己的已归档区间，不重复展开孙表。配置变更记录生效快照，启用前的计量关系不作推断。

对象的权威用量区间与质量、来源及配置版本在同一次 Folio 发布中保存，专用原生用量历史点作为镜像。生成游标持久化，原始采集历史不被改写。历史修正通过 `tasks` 的 `recalculate` 明确指定整分钟范围；拒绝未来、未生成及关系未知的区间。修正保留前后版本、按依赖顺序更新汇总结果，不倒退实时游标，也不把修正量再次加入实时累计读数。

泄漏与能流分析分别读取总表及涉及分表各自保存的历史。独立实测上游使用 `balanceMode:'independent'`；由同组分表生成的虚拟上游使用 `balanceMode:'consistency'`，差额为一致性检查。未知来源或关系使用 `balanceMode:'unknown'`。`lossEligible` 明确是否可作损耗判断，缺测、关系不明及负差额不会给出有效泄漏结论。负差额原值保留。`extra.energyFlowSegments:[{from,to,known,energyFlow,rows,series,summary,warnings}]` 返回历史关系分段；界面选择某段后，图、表及导出均使用该段快照。

### FIN 原生报警（0.8.3）

小时能耗超限保留逐小时能源证据；同一对象、能源分类和单位的持续超限共用一条原生 Alarm。`episodeId` 对应 Folio 的 `finEnergyAlarmEpisodeRef`，指向本次持续超限的主事件；`nativeAlarmId` 对应 `finEnergyNativeAlarmRef`。原生状态为 `offNormal`，优先级遵循 FIN 原生设置，要求确认。有效正常小时（quality 为 ok / derived 且 value <= limit）结束当前事件，恢复时间为该小时结束时刻；缺测和不确定数据不会推断恢复，恢复后再次超限产生新事件。物理点已有的连接器报警保持独立。

GET `alarms` 每次持续超限返回一行，包括 episodeStartTs、lastTs、recoveredAt?、hourCount、latestValue、peakValue 及 hours[]（ts、value、limit、unit、quality、原确认信息）。确认人、确认时间和备注以原生 Alarm 为准；原生正常且已确认后归档时保留确认快照。POST `alarms/ack` 使用原生确认接口，保留管理员权限及本地 mod 检查，旧小时事件 ID 也解析到主事件。确认与恢复正常互相独立；恢复但未确认的原生报警仍可确认。`nativeState`、`nativeActive` 返回原生状态；正常归档返回 nativeActive:false，其他被移除的原生记录返回 `nativeAlarmMissing:true`，均不会重新创建。

首次扫描回放旧小时事件至所选结束时间以识别恢复边界，后续从活动事件上次已评估小时续查，最长 366 天。合并前把本功能拥有的重复原生当前记录完整保存至原小时事件 nativeAlarmArchive，并保留 priorAckBy / priorAckAt / priorAckNote；然后仅移除这些重复当前记录，原生历史不清除。已确认的旧事件不会重新打开。重复扫描可找回创建成功但未保存关联的原生记录，且不重复生成小时证据或事件。任务 alarmsCreated 统计新增小时证据数。管理员 Axon `finEnergyScanAlarms(from,to)` 与页面扫描采用同一有界任务及共享锁。原生 metadata 包含 `finEnergyEnergyAlarm`、`finEnergyEventRef`、`finEnergyNodeRef`、`finEnergyCategoryRef`、`finEnergySourceRefs`、带单位的 `sourceValue` 与 `finEnergyLimit`。

### 跨模块基础用量与数据截止

报告保留调用方的 `[from,to)`，排名不再缩短请求时间。可传 `asOf` ISO 日期时间；FIN 服务将未来截止时间限制为服务器当前时间，响应返回实际 `asOf`。同一查询范围切换模块、视角或汇总间隔时界面沿用上次截止时间；同条件再次查询更新截止时间。模板保存选择范围及维度，不固定旧报告的数据截止。

概况、排名、占比、分项、对比、日均、工作时段、工作日、折算与概览共用 `closedSourceIntervals` 已有用量；适用能耗报表的 `cost` 也复用同一主点区间集合，逐表计计价后汇总。仅纳入按区间起点属于查询范围且在查询／截止前闭合的源区间，保持完整区间且不按时间比例补算。有限的过滤后小计可见，真实零保留；缺测、NA 不补零。`knownValue/knownValueType/knownQuality` 与严格的 `value/valueType/quality` 分开返回；客户端只在冻结的展示副本中采用已有量，并保留 `complete*` 字段。图、表和导出使用同一副本。

固定／日期／周时段费率对闭合区间按起点适用单价计价，例外规则优先于常规规则，均取最后匹配规则；不摊分穿越费率边界的源区间。已有费用小计不是完整账单。月／年阶梯仍要求完整的周期前缀与用量，缺少基线不能猜测阶梯。`extra.tariffSnapshot` 冻结实际表计采用的费率、版本、规则、例外及阶梯；不因草稿条件或后续费率配置变化而更改旧报告。

费率默认值、规则及例外的 `band` 可为 `sharp|peak|flat|valley|unknown`。日均配色按各表实际费率和日期例外解析，未配置费率时回退项目日历的 `sharpHours/peakHours/valleyHours`；不按单价高低推断分类。相同小时跨日期或表计分类不同时标记 `mixed`；未分类单列。区间分类合计与日均值分开，分类合计不能再次与总体重复相加。能流图支持 `energy|cost`，费用单位为元且 `lossEligible:false`，金额差额不能作为能源泄漏结论。

`summary.selectionTotals` 及 `extra.selectionTotals` 按有效表计集合去重，含 `meterIds/sourceIds/knownValue`。相同有效表计集合、单位、清洗规则和截止应有相同基础合计。父子同时选择只计有效上级一次；重叠空间／组织范围不重复累加。组织未分配不抹掉设备自身已知用量，但结算归属及完整性单独标记。`usageCoverage` 记录实际覆盖与查询时长；`knownUsage.sourceUsage` 的诊断区间总计最多1000条，截断标记不改变数值及覆盖统计。

排名保留无数据对象，`rank:null`；占比以明确标注的已有量为分母，单个正值为100%。零合计、负值、范围重叠或无有效量分别返回 `percentageBasis` 原因并不生成饼图比例。对比保留 `knownCurrent/knownReference`，仅完整可比覆盖生成差值及变化率。完整账单、COP、泄漏／计量差额及预测训练不因已有小计展示而放宽条件；FIN 能源管理不发布额外归档历史。

能流兼容 `scopeDimension/scopeNodeIds`。空间／组织选择由当前配置解析为有效表计集合。全区间总览读取每块表当前明确绑定的主点历史。覆盖区间描述源数据的可用性，关系变更日志供独立审计。

### 历史记录：配置有效版本的项目 ID（0.11.6）

新建配置的有效版本在提交前使用 Folio 的项目 ID 前缀规范化本地 Ref，保持配置 `id`、设备业务引用、分类和表达式变量与提交后的原生记录一致。项目限定的绝对引用保留原值，跨项目及失效引用仍由现有校验处理。

读取既有局部 ID 版本时，在内存中规范化已定义的引用字段；历史表达式虚拟设备由旧局部设备 ID 派生的历史点键，仅在匹配确定性旧键时兼容定位到原生设备的派生点。版本生效时间、参数和先后顺序保持原有语义，不改写已存 epoch JSON、原始读数或既有发布区间，不需要手工编辑配置或迁移；既有发布区间的修正仍通过明确范围重算执行。

虚拟表用量生成的状态键与引用使用提交后的完整主点 Ref；新增派生点时仍按 Folio 规则传入局部新增 ID，避免状态查找与原生点记录落在不同命名空间。

### 历史记录：虚拟表归档点引用（0.11.7）

原生虚拟设备目录中的 `historyPointId` 与实际归档点使用同一项目限定 Ref；独立无项目前缀的记录保持原有引用格式，派生点的确定性名称保持不变。普通报表仍只读取匹配的已发布历史，不重新计算表达式，也不根据局部后缀匹配其他项目的点。

`includeInTotals: false` 继续排除范围合计；显式选择该虚拟设备时，趋势、排名、占比和对比仍可读取自身已归档用量。缺失归档继续返回缺测，不回退为实时表达式值。

### 当前关系计算（0.12.0）

所有报告按当前生效关系和主点绑定查询。关系变更的历史用于审计。自 0.12.9 起，派生历史生成与重算入口已退出当前运行路径。

### 局部对照选择（0.12.0）

新泄漏报告传 `comparisonBasis:"physicalBoundary"`，并选择原生主表 ID；仅用于 `kind:"leak"`。不传此字段的旧模板保留原自动合计成员规则。三种视角均使用当前配置，`includeInTotals` 只控制自动汇总，不限制明确的自身用量查询或新局部对照。

只读 `GET comparison-scopes?nodeIds=<逗号分隔且URL编码的主表ID>` 返回 `{scopes:[{nodeId,categoryId,basis,availableMembers:[{nodeId,name,unit,via,sourceIds}],defaultMemberIds,selectedMemberIds,quality,completeSelection,limitations}]}`。`via` 是可读中间计算节点 ID；来源是本次配置绑定的实际历史点。最多200个主表，普通已登录只读用户可查询。服务端报告重新解析成员及权限，预览不是授权凭据。

`comparisonMembers?:Record<string,string[]>` 按主表指定：缺少该主表键表示全部当前可用边界，`[]` 明确不选任何分表，非空名单只能是该主表边界的子集；错误主表键、外部分表及无效类型返回400。兼容映射先规范化主表及分表 ID，同源别名只读一次。临时名单不写回资产。

解析穿透同能源、兼容单位的加法计算节点，遇到独立物理表停止，避免与下级重复相加。带权、减法及其他非加法节点保留其自有历史并返回范围限制。虚拟总表使用自身明确绑定的主点历史，缺失时为空。成员不完整、循环、缺少来源、单位不兼容或不可读时保留可读成员已有量，严格差额及比例为空，`lossEligible:false`。只返回有权读取的成员名称、ID 和源点。

完整的独立实测总表在物理用量指标下才可获得泄漏资格；计算总表是计算汇总校核。费用及折算可显示差额校核，不输出物理漏损比例。单个分表缺测不清空其他分表堆积段。

响应 `extra.comparisonScopes` 固定实际成员、绑定和限制，`extra.comparisonUnion` 按能源及单位展示各主表所选分表的来源并集，去掉同源别名和物理父子重复；各主表组分别保留，不能直接把组和相加。不能安全相加的未解析边界合计为空；跨范围面积分母不明确时归一化并集合计为空。图、明细和导出使用同一冻结结果，模板保存依据及明确名单；分类筛选保留上述范围证据。

- 每次查询固定当前配置，并读取原请求日期内各表自身的历史；不按日志开始时间、旧父引用或旧点绑定切分查询。当前关系修改后的新查询会重新归组，已生成报告和导出保持原快照。
- 服务端与纯引擎入口忽略外部 `meterHistorySegments`、`legacyMembership`、`leakSegment`。日志缺失、晚于查询日期或包含旧关系均不改变成员、数值、覆盖或漏损资格。
- 结果 `extra.relationBasis` 固定为 `current`。能流仍可依据源数据覆盖划分展示区间；这些区间全部使用当前关系，与关系变更日志无关。
- 分表堆积显示当前成员的已有量。一个分表缺测不补零，也不清空其他分表已有段；严格差额和漏损资格继续受数据完整性、独立来源、单位及权限约束。
- 可选虚拟总表当前值汇总与历史读取分开。历史报表保留主点读数和源历史，查询证据中的配置指纹来自当前配置。
- 自动汇总的 `includeInTotals` 及去重规则保持原语义。关系日志不提供另一套计算模式，也不要求普通用户确认或导入恢复凭据。

### 消息中心重要变更

GET `messages/changes?offset=0&limit=30` 返回 `{items:ChangeMessage[],total,offset,limit}`。`offset` 为非负整数，`limit` 为 1–200，默认30；非法范围返回400。沿用现有 `{ok:true,data:...}` 响应包装。只读接口不确认、不重算、不改写配置或日志；现有 `alarms` 与 `alarms/ack` 保持原行为。

`ChangeMessage` 为 `{id,ts,action,category,objectId,objectName,objectKind,actor?,changes:[{field,before,after}],detailsRestricted?}`。`action` 为 `created|updated|deleted`；`category` 为 `relationship|source|configuration`。一个对象 epoch 最多产生一条消息；同时包含多种字段时按 relationship、source、configuration 的优先级分类。按时间降序排列，同一时间以 epoch sequence 和不可变 epoch ID 稳定排序；分页总数在权限过滤后计算。分页期间发生新的提交时，offset 会随最新结果移动。

消息由既有 `finEnergyMeterEpoch` 的相邻配置前后值投影，目前覆盖其已追踪的表计、传感器、分类、分项、公式、清洗方案、组织和空间。初始化快照不作为用户操作，同值及仅敏感／非重要字段变化不产生消息。新提交在 epoch 的独立 `finEnergyEpochActor` 标签记录当前 FIN 用户名；旧日志缺少操作者时不返回 actor，也不从配置推断。操作者与初始化标记不进入计算配置。

仅返回白名单：当前归属引用、主点／公式绑定、公式与变量、对象名称／类型、autoSum、includeInTotals、historyMode、maximum、unit、清洗开关／方案／模式及受支持 parameters、报警开关／阈值。parameters 仅保留既有清洗参数名及受支持数值／单位结构，alarmLimits 仅保留 categoryId 与 limit；密码、令牌、凭据和整份旧配置不返回。

当前无权读取的对象不返回消息；当前已删除对象的日志仅管理员可见。历史引用按当前对象权限重新检查，包括旧父引用、公式 variables、alarmLimits 内引用；失效、无权或不支持的嵌套引用字段整项省略，并返回 `detailsRestricted:true`，不暴露引用 ID、缓存名称或部分旧值。单条损坏 epoch 仅记服务端通用告警；其后的未知旧值不冒充新建或已知变更，后续有效快照重新建立比较基线。消息投影不被报告、选表或虚拟表计算使用。

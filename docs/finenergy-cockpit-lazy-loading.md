# 驾驶舱按需查询 / Cockpit on-demand queries

驾驶舱首页请求 `kpis, trend, issues, space`。其他分析页签首次打开时只请求该模块；返回已加载页签复用本次观察的内存缓存。项目、用户、实例版本及客户端查询控制器相互隔离，手动刷新重建观察、截止时刻及缓存。

The homepage requests `kpis, trend, issues, space`. A different face requests only its own module on first opening. Previously loaded faces reuse their observation-local memory cache. A manual refresh starts a new observation and cutoff. Requests for different faces are serialized.

`POST /cockpit` 保留原有契约，新增可选 `expectedConfigurationToken`；响应 `context.configurationToken` 表示分析配置及权限/单位兼容事实。后续查询固定绝对起止时间、截止时刻、比较期、范围与能源。配置不匹配返回 HTTP 409 / `COCKPIT_CONFIGURATION_CHANGED`，在读取历史前拒绝。不以 token 代替每次原生权限检查。

`POST /cockpit` additionally accepts `expectedConfigurationToken` and returns `context.configurationToken`. Follow-up queries retain the exact absolute interval, cutoff, reference period, scope and energy category. A mismatch returns HTTP 409 / `COCKPIT_CONFIGURATION_CHANGED` before reading history. Native permissions are still checked on every request.

各页签保留各自的不可变快照编号及历史观察时刻；不把多个响应拼成一份冻结报告。相同截止时刻不冻结 FIN 后补历史。首页核心指标和趋势保留首页快照；页签显示其独立观察依据。专业下钻携带对应页签的快照。返回后如原快照缺核心模块，将独立恢复首页核心快照，配置和范围匹配时复用原页签结果。

Each face retains its own immutable snapshot and history-observation times. Responses are never combined into one purported frozen result. A common cutoff does not freeze subsequently corrected FIN history. Core indicators and the main trend retain the homepage snapshot. Drill-down uses the active face's snapshot. Returning from a face-only drill-down separately restores the homepage core and reuses the original face where its context still matches.

“完整汇报与导出”显式请求全部模块，之后所有导出只使用该单一完整响应。打开未加载的诊断/来源面板才构建对应明细组件；不改变任何数值、覆盖或清洗规则。

“Complete report and export” explicitly requests every module and exports that single complete response. Closed source/cleaning panels defer their detailed components until first expansion. Numeric, coverage and cleaning semantics remain unchanged.

驾驶舱专用输入在通用 JSON 解码的长期持有前分离 `alarm/job/template` 运营载荷。使用既有 JSON 解析器逐记录验证，仅保留身份、标量及 Ref 兼容头；恢复正文仍保存在 FIN。正常管理、报警、恢复及普通 `/report` 接口继续读取完整记录。保持原 200,000 条目资源预算和 30 秒保护；不得提前转不可变绕过记账。

The private cockpit input separates operational `alarm/job/template` payloads before retaining decoded documents. Existing JSON parsing validates one document at a time; analytical input retains identity, scalar and Ref compatibility headers. Recovery materials remain in FIN. Management, alarming, recovery and ordinary `/report` paths keep their complete records. The 200,000-entry and 30-second guards remain in force.

本任务的浏览器测试为受控接口回放，SDK 测试为隔离源代码验证；实际 FIN 验收及部署由统一发布负责人执行。

Browser tests use controlled transport replay; SDK tests are isolated source verification. The release owner performs actual FIN acceptance and deployment.

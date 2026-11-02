# ALL-59 年度查询有界消费设计审计

状态：待技术核对；不是已实现或已验收结论。2026-11-02。
负责人：开发聊天；沿用冻结的 1:1 驾驶舱 / M4 需求，不增加产品范围。
源码：developer f4394d90；FIN 实际仍为 b3a63083 / 0.14.0。

## 已定位的两个阶段

1. 真实 0.14.0 的 zeda site/main 年度请求均返回 422 PREPARED_READ_LIMIT；同 cutoff 的 cubeTest site/main/leaf、zeda leaf 返回 200。
2. 精确 main 5 源回放：旧版 prepared 141438，Context 再持有 58564 后触发 200002；5470d402 仅对已证明无 known 用量、无区间证据的 strict-null 小时合并 domain，保留 missing / incompleteInterval 区别。改后 prepared 48443、Context 60982，峰值109425。12报告48组业务字段与整段 oracle 一致；8/9模块去掉查询标识后全等，issues 的4条事实集相等但等优先级Top3排序存在既有查询ID影响，未顺带修改。
3. site 精确前缀：当前82主点元数据与实际计划，捕获前17个普通清洗kWh源的187个月度只读片段，共53295去重原始记录。旧版、5470均在 streamPrepare 触发200k，Context尚为0；改后200003。后续未捕获源必抛 CAPTURE_NOT_AVAILABLE，不能当成空历史。3个水点不在该前缀，不能将本次压力归因于水点、高密度归档或协议错误。
4. 因而不能只压缩诊断JSON、重置Context计数或放宽限值。需要真实减少同时活跃的源小时状态。

## 当前消费者和所有权（源码实查）

| 位置 | 当前持有 / 消费 | 必须保持 |
|---|---|---|
| Cockpit.execute | load 后冻结全部 histories，随后顺序生成各报告并在 reports 保留结果 | 一次冻结目录、同一asOf/原时间边界/精确源计划/配置指纹 |
| CockpitStream.prepare / closeHour / finish | out、每源reads、strict与各queryEnd的known、emptyDomains；每小时及费率子边界 | 原生分块与清洗状态、前后边界、来源/类型/质量、闭合区间；不引入额外历史 |
| HistoryData / Context | byPoint 包装、knownReads、dimensionPlans、空域cache、最多256阶梯基线、usedTariffs | 本设备自身主点；量程、单位换算、费率分段和逐表阶梯周期基线 |
| Report.line / meterTotal / finish / coverage | 小时ticks后按period折叠；再次按每表计算selectionTotals；coverage从knownReads汇总 | series/rows/summary/用量合计及每表覆盖不变，min覆盖算法不能变成各源覆盖交集 |
| CockpitMetrics.values / Budget.canonical | 本期和同期energy/cost/co2/aux或面积，预算自身物理边界费用 | 不做跨币种求和，不用本期替代同期，预算/面积计算顺序不变 |
| CockpitFaces | 自身表计profile、daily、scope小时热图、日历workingHours/Days、分项及组织 | 热图完整当地日判定、DST23/25小时；同表集一致 |
| CockpitSpace.project | 可读空间/设备候选报告 | 设备必须自身主点，父空间frontier；未加载与缺测分别保留 |
| Flow.attach / EnergyFlow / FlowOverview | 各设备逐小时值、直属分表关系、覆盖、有限period诊断及图边界 | own主点/总分表/共享/负差额、拓扑时段及非可加判断不变 |
| Efficiency.attach | COP逐小时分子/分母及period line | 同小时质量、单位/边界，先求各量再比值，不能平均COP或拼不同时段 |
| Rules.nonWorking | 逐小时scope值 + 每源known区间资格 | closedOwnPrimaryIntervalsWithinActualHour；不能只用coveredSeconds代替区间资格 |
| Context.knownEvidence / KnownUsage.evidence / Diagnostics | sourceUsage行、每行intervals、最终1000条全包诊断裁剪 | 截断行数/真实未知数/原因可核查；不能因裁剪改变coverage与规则 |

关键引用风险：toImmutable只冻结，不释放原数据；Context结束后report.extra.knownUsage仍可能保留源小时行。当前PreparedBudget.hold多数为累计计数，新增release必须对应真实所有权，不能按报告结束直接归零。

## 最小可执行分解（不是简单更换容器）

### S1 明确全部消费计划与可合并状态

在Cockpit现有计划旁列出consumer：原请求/同期、维度对象集、category/metric、period、queryEnd、费率/日历/COP与区间边界。抽取现有report定义，避免另写一份不同的选择/去重逻辑。所有读对在原计划内；读取后禁止追加FIN范围。

测试：从当前9模块输入生成确定计划；无/有日历、COP、预算、辅助能源、半小时费率及DST。与现有read lookup轨迹逐项比对；不可用能力保留原降级。

### S2 单源扫描与原计算消费缝

将Stream.prepare内一源/一规范化窗口的循环抽为内部consumer回调；当前全量路径保留为基线。一个主点窗口原生读取一次，顺序清洗；在丢弃源状态前，按S1所有消费者计算自身用量、费用、co2及其known/strict与覆盖摘要。阶梯费用保持逐表按时间顺序、完整周期基线。不能先把原始值按月相加再套分时或阶梯。

测试：每个已有prepared pair、每个queryEnd对照整段oracle；0、NA、负差额、reset、替代、跨小时长间隔、非整小时、费率子边界和量程不变。未计划pair仍为streamingReadNotPrepared。

### S3 有界业务fold，不保留源小时副本

新增仅请求内的fold状态，消费后只保留输出所需period业务行、每个消费范围的小时累计/质量计数、每表coverage摘要、最多1000条诊断；不持久化、不写历史、不建立可再次查询的时序库。

必须证明的不同聚合：
- energy/cost/co2/aux：strict与known分别用现有sum/combine顺序和质量规则。来源集合保持原序/去重规则。
- 空间/分项/组织：按冻结frontier把同一设备贡献送到多个视图；不将父总表与子表相加，也不为缺失总表历史用子表替代。
- heatmap / 非工作线索：按原时间点保留scope逐小时聚合和必要资格计数，完成当地日后按原判定输出；规则额外保留每源区间是否完整落在该小时，不能只看合计覆盖。
- COP / 泄漏 / flow：保留原本需要的同小时两侧量与质量，完成关联后再折叠period；不平均比例，不把不同覆盖段拼为完整对比。FlowOverview.periods只属诊断，截断不影响真正业务值。
- coverage：保存原算法的每source coveredSeconds/min、最早起始/最晚结束和complete资格；不能改成覆盖交集或补零。
- 预算、面积、占比、组织树、规则与事件：在相关量冻结后应用现有业务算法，预算不分摊到子对象。

本步骤是主要风险：现有Report把小时循环、knownReads及输出组装绑定；需抽出内部fold接口，而不是写一个全新的通用报告框架。预计触及Report、Context、Cockpit与各face/flow/efficiency/rules适配，约10-15个生产文件；在证明细粒度oracle前不得切换默认读取路径。普通历史报表路径不改。

### S4 真实所有权与统一峰值

每源使用一次性lease，计入prepared索引/strict/各queryEnd known/稀疏domain、所有消费者缓存、未完成的小时关联状态、解包临时对象及保留输出状态。源结束后清空Stream、Context.byPoint/knownReads/cache/baseline与consumer临时引用；最终输出只拥有不反向引用histories的业务行和有界诊断。函数返回后才能释放对应lease；重复释放/负计数必须失败。

200000 prepared+Context共同峰值、50k原始块、200k原始held、20M扫描、30s全请求、1000全包诊断和8MiB输出原样保留。source callback数量与预算统计逐一对应，不以日桶/数组为1条掩藏标量；释放后对象不能被reports/knownReads/闭包保留。最大输出本身超限仍明确拒绝。

测试：199999/200000/200001边界；多源不同时结束、消费者抛错、半成品不泄露、并发请求隔离；验证峰值包括解包和最终输出，引用审计/结构遍历断言。

### S5 渐进接入与实机

先在受控路径接入完整9模块，与原整段引擎比较全部业务字段；过后才接真实FIN调用。首轮使用已捕获的真实5源main与17源site前缀，明确区分离线回放和FIN I/O。然后只读捕获剩余源或在候选实际FIN查询全部82源，不将未捕获/缺测转0。输入/配置变化应单列，不能误判数值差异。

统一候选需要新版本和包哈希。实机重复cubeTest、zeda site/main/leaf本年+去年同截止、固定4816与既有缺测、所有9模块和导出；源计划及unpreparedLookupCount=0；覆盖证据、类型/质量、每表费用、预算/M4和截图一致。readonly按用户暂缓。原同版本30min证据不能替代新候选同进程观察。

## 本轮边界

- f4394d90手机修正已10个Edge场景+14单测+类型/构建通过，仍未部署。
- 5470d402是真实有证明空域的最小优化，不宣称site问题关闭。
- 逐源fold尚未实现。此审计不以文档替代交付；若不能保持上述全部合同，先保持当前明确422，不上线静默降级或假数据。

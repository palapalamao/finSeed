# ALL-59 年度查询有界消费设计审计

状态：已完成数学/所有权合同核对，增量前置已验证；完整有界调度仍未实现或验收。2026-11-02。
负责人：开发聊天；沿用冻结的 1:1 驾驶舱 / M4 需求，不增加产品范围。
源码：developer 0d996c3a；FIN 实际为 da8c8fa4 / 0.14.1。后续源码尚未部署。

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

## 调度选择与已落实的前置

优先评估按时间水位交错扫描各源，保留每源原始/清洗状态并只物化当前消费窗口。原逐源全年方案作为对照，不能以大段跨源小时矩阵逃避200k限制。架构复核记录：current-relations工作区 out/cockpit-one-to-one-20261101/annual-consumption-contract-review.md。

- 0.14.1已实际确认zeda main年度200，约6.24秒；site仍422。固定4816kWh/2799.549228CNY、13HTTP资源hash与同包30min1805秒/181采样已核对。手机275/344CSS宽度中英文四卡/金额及M4控件无越界；PDF受浏览器网址安全检查停止，未通过。
- 592beaa3：来源摘要先detach，5类42方法290校验；真实捕获main回放8个provenance字段、48业务组不变。
- ae96768a：单列修正规则的诊断配额依赖；同输入0/1/1000明细配额都为actual80、2个有效小时、触发1次。完整区间资格在裁剪前计算，未知/跨小时/NA/替代不因此可靠，私有事实仅实际启用的nonWorking消费者准备，新增保留事实逐条计账且默认不发布。差异白名单见 out/cockpit/parity-20261101/rule-diagnostic-correctness-evidence.json。
- 39aa777d：4项19校验冻结原归约树、质量/来源顺序、coverage先每源sum再min、COP先sum操作数再divide。
- 0d996c3a：增量严格/已有量标量fold，保留每原标量顺序，不接受合并块小计，不保留输入Value或可变sources引用，finish独立可继续。76类636方法238840校验通过；捕获main8个provenance/48业务组不变，峰值109425。未切批次扫描。
- S2 单源内部 cursor：暂停原生分块和小时物化，保留未消费 raw/detail、清洗 previous 和跨小时闭合区间；Jan→Sep 闭合端只物化当前所需小时。共享 budget 仅允许一个 cursor，未实现跨源准入或 prepared 回收。关闭会实际清空未消费队列并释放其临时计账，已输出 prepared 状态仍保留/计账。8方法456校验覆盖清洗/NA/回绕、原始两种模式、密度拆分、缓冲所有权、真实EOF、失败及超时。45方法710校验、既有26方法233921校验通过；默认路径捕获main回放8个provenance/48业务组不变，峰值仍109425。新增入口未接全站，也未部署。证据：cursor-final-tests.log、cursor-legacy-stream-regression.log、cursor-seam-parity.json。
- 后续 producer 增量：按所有活跃 cursor 共同计算 raw-held 和读块准入，逐源保留/释放未消费清洗详情与跨小时 interval；不再由各源独立声称200k。私有 withFrame 在消费者返回后使全部借用 reader 失效、清空自身 prepared/domain 引用，再仅释放自身条目；错误和超时也执行该清理。逃逸的旧 prefix 不允许切换释放模式；失效 reader 的 read/known/空域入口明确报错。拒绝的 owned reservation 不形成所有权，不重置其他源/消费者计数。消费者仍必须只保留另行计账的脱离源对象的 fold 或有界诊断，尚未实现 Context/全部业务出口所有权。
- 受控82源各1000小时：原整批表示触发 PREPARED_READ_LIMIT；frame 路径完成82000对，scope82000、每源1000，含模拟外部状态和测试 scalar folds 后每轮保留1440、prepared+temporary峰值9876、raw峰值8391，902次读块回调/82082样本、unprepared0。此项测试 timeout 为30min，不是生产30s或真实FIN、9模块验收。5类32方法3225校验通过，既有3类26方法233921校验通过；默认真实捕获main回放8个provenance/48业务组不变、峰值109425。详见 cursor-owned-parity.json、cursor-owned-final-tests.log、cursor-frame-legacy-regression.log。默认加载路径仍未切换，安装仍0.14.1。
- Report 内部 LineCursor 复用原叶级计算，每次仅产出一个原时间边界 tick；默认 line 仍完整收集原 ticks。LineFold 支持 value/known/baseValue/baseKnown，COP累计操作数后相除、传感器按原时长加权、首次不可靠来源和原浮点顺序，不保留输入 tick/来源数组。默认 Line 四个归约入口已复用；80类659方法241984校验通过，捕获main8个provenance/48业务组相等、峰值109425、unprepared0。证据：line-consumer-full-fantom.log、line-consumer-parity.json。全局消费者计划、Context与输出所有权尚未接入，不能将此当作全站修复。

### 已确认的阶梯前序缓存污染（独立正确性修复，源码通过，未部署）

受控130个独立设备/主点、monthlyBlock恒定单价1、每小时cleaned完整用量1：先查主表00:13→01:00，再查01:00→02:00得到null/missingTariffBaseline；查询129个其他表使256基线缓存淘汰后，相同01:00→02:00变为1/cleaned。Context.cost代码未改；有效结果tier-cache-order-probe-ordered-unique.json。晚注入budget未启用ordered的初次探针不作为证据；非现场费率观察，zeda当前tariff0，所以不是年度422根因。

架构已确认：缓存只能保存经canonical同设备周期前序证明的prefix，按原完整小时序及必要末段严格计算。不得将部分查询的baseline+raw直接当作整段前序；真实前序缺测仍必须使阶梯费用不可判。上述00:13→01仍null，01→02因真实00→01完整应冷/热/淘汰/倒序恒1。此项需单列独立oracle和业务差异白名单，不混入性能零差异声明，不放宽质量或用known小计建tier。

专项已限制 next-prefix 仅由对齐整点、恰好一个原小时的步骤延伸；部分/多小时raw不写作canonical next。原prepared计划补齐阶梯起始小时的hour→queryFrom前缀pair，不扩大原生读域。6类77方法797校验覆盖普通/有budget Context、冷/热/倒序/淘汰、monthly/yearly、不同设备费率、阈值、跨年、真实缺测/NA/reset/negative/maximum及0、Float多小时分组和原分时费率。有效RED见tariff-prefix-red.log，结果tariff-prefix-extended-tests2.log；先前一次选错测试方法的执行不算完整通过。

旧冻结0.14.1包与新隔离SDK的固定9模块对照：累计型135个、清洗型32个逐叶差异已分别列出，仅费用字段/费用资格/费用摘要、预算费用输入与预算规则输入及准备状态证据；未整体忽略任何模块。能耗/碳/强度、非费用报告/模块、来源、原始用量证据、覆盖秒数、币种、配置指纹及时间边界相等。每例同一读域、1次loader/1次原生读适配回调/3样本；unprepared从2变0。累计型恢复17.833333333333332已有费用，仍非完整费用，预算/规则仍不可判；清洗型第一段仍null、第二完整小时10，整个费用仍null。证据tariff-prefix-correctness-evidence.json及两份allowed-field-differences.json，离线包tariff-correctness-offline-test.pod SHA647EE5D38BB6E3DF1460165EFFF2156F0DD1F0F72F0BCB1ADB371D352A3EFDA6。捕获main8个provenance/48业务组不变。

既有quality线索ID含随机query身份，旧冻结包重复执行即会改变等优先级Top3；对照只按业务键匹配全部事实，另存旧/新/旧重复的Top3顺序，不把该字段冒充已通过或归入费用白名单。此项既有排序限制仍未修复。
- 当前离线结构盘点：82计划主点、边界18表、81个space焦点、18 own-profile、18 daily-own、79 balance-own，COP/calendar/tariff均0；focus多源有序energy集合去重1组。原词典序point扫描在该成员序有4处逆序。此盘点尚非完整消费者/峰值证明。

## 最小可执行分解（不是简单更换容器）

Context 私有所有权缝已补齐：长期元数据与单帧动态缓存分属两个 owner，严格／已有量 Context 共享借用历史；bound 的临时元数据、告警和费用快照只存活于当前帧。清空根引用后仅释放自身额度，外部 owner 保持；失效、跨 budget、无租约、同一长期／短期 owner 均明确拒绝。两项准入失败用例先复现失败，再修正注册清理回调的顺序。5类37方法2666校验通过，捕获main8个provenance/48业务组相等（仅归一化periodsCaptureId），峰值109425/unprepared0。证据context-owner-parity.json与context-owner-final-tests.log。普通路径仍未切换，最终输出／覆盖与全消费者调度尚未实现；不是全站年度验收。

阶梯前序私有 cursor 在当前小时消费者结束后，按原完整小时追加本设备主点用量；只保留严格累计标量，必要非整点前缀仍读取当前帧，跨账期重置。真实缺测、NA/reset/量程保留；已有量不能建立阶梯。先复现释放后第二小时应15却null，再以整段oracle验证月／年、不同设备费率、Wh换算、原Float顺序、746小时跨月及未准备步骤不污染状态。长期owner条目不随帧累计增长。完整84类676方法253232校验、专项5类35方法11364校验通过；捕获main8 provenance/48业务组不变，峰值109425/unprepared0，详见tariff-cursor-parity.json。仅内部入口，默认路径和安装包仍0.14.1，尚未接完整消费者。

覆盖秒数专项已按架构确认固定为每唯一point内from/to时间顺序、同边界按nodeId/pointId裁决，比较真实时刻以覆盖DST重复小时；不改变贡献行、别名、过滤、每行秒数、sum后min或complete比较器。原无序Hash与增量时间序的亚秒Float尾差已有独立RED；8个完整闭合源区间端点例旧新对照仅3个coveredSeconds叶值变化，complete无翻转，其余字段逐项相等。已保留一个既有纳秒端点局限：fixture0实际完整、strict有值，但旧新exact Float比较均使complete=false；没有用epsilon或隐藏字段放行，不宣称该完整性问题已修正。私有CoverageFold按同一顺序分帧累计，不保留历史/贡献行；1/7/50/744帧宽逐位相等、长期额度固定、别名/长区间/缺失point/25h DST均覆盖。5类17方法12900校验通过，捕获main8 provenance/48业务组（含coverage）保持相等。证据coverage-order-correctness-evidence.json、coverage-fold-parity.json；仍未接全局业务消费者。

多源帧已接真实Report.openLine叶计算和带所有权的Line/Value folds：同预算、唯一主点与相同消费水位先校验；Context动态根先清除，再退出各源prepared frame。各源可共享已计账的冻结规划目录，独立cursor则在open前为自身目录索引保守准入，清空后释放；满额时更早拒绝且不启动原生读取。6类35方法5306校验、当前精确源码完整87类688方法257148校验通过。受控82源×1000小时为scope82000、每表1000，902读块回调/82082样本、unprepared0、prepared+Context峰值3253、raw峰值8309，在默认30秒内约2.8秒；有限元数据492仍真实计账，不假归零。两源大数例分别保持scope的1e16+4和selection的1e16+2；首次测试错误是原生区间值按结束时刻标记，已补合法前边界样本并修正fixture，未改业务读数算法。捕获main8 provenance/48业务组保持相等，默认峰值109425。证据group-frame-evidence.json与group-frame-full-fantom.log。不是FIN时延、完整9模块报告/输出所有权或zeda site年度完成证据；默认加载仍未切换。

分期消费者保存独立全区间fold及一个当前期fold；输出预留自身Value/来源数组与完成时临时空间后，才复制已脱离tick的结果。输出owner和计算owner分开，前者在后者关闭后仍可读，关闭自身后清根；已有一期输出时最终准入失败也不允许发布或重试半成品。Scope真实82源×1000小时已接两期月输出：61008、20992，总量82000、每表1000；含保留输出后峰值4758、raw8309、902回调/82082样本、unprepared0，默认30秒内约4.5秒。清洗型NA的实际叶计算、分期及覆盖与整段报告相等（严格空、已有量100），2回调/10样本；另覆盖COP、传感器权重、25h DST及跨月Float归约。5类29方法2947校验通过；此增量未重跑完整套件，上述87类完整结果对应前一提交，不混用。私有cursor逻辑小时数0→82000统计缺口已通过功能RED修正；默认prepare统计不变。证据period-consumer-evidence.json；仍未接完整报告DTO、全局诊断及9模块默认路径。

校验脚本纠正：此前新增回放辅助脚本误从根读取provenance字段，已对四组历史回放在正确的provenance容器内要求8个键存在并比较实际值，32项全部一致；缺键即失败。业务报告另要求12个report键相同，比较48槽位中的47个实有组，energy-flow/extra/usageCoverage原本缺省的一槽仍缺省。旧新证据已补入严格复核信息，见strict-provenance-verification.json及strict-business-verification.json。本增量最终回放也使用同一严格规则，不再依赖可选根字段读取。

完整 profile DTO 私有消费缝已接通：复用原 selection/detail 成员选择、叶级小时计算、分期与独立整段 fold，冻结 own-meter totals 后由原 finish 输出图、合计、明细、面积和 coverage。Context 的有序告警按原 line/阶段/小时裁决，保留原去重。原 finish 在 dimensionDetails 前冻结来源及覆盖，初次对照发现新路径提前纳入详情专用分表，已按原阶段修正；同主点别名不会因此重复增加覆盖。Report/Area 索引和线的面积元数据先准入，最终 DTO 保守预留，分期 Value、来源数组和脱离帧的诊断逐项另计；关闭计算 owner 后仍可读输出，关闭输出后清空逃逸行和来源容器，同时保护借用配置。中途输出准入失败不能发布或重试半成品，也不重置其他 owner 的额度。

该增量精确源码完整90类705方法258587校验通过（421308ms；包含显式1800秒预算的旧容量夹具，不作为生产30秒成功证据）。受控82源×1000小时完整月报告 summary/series/rows/coverage 与无 prepared 限制的整段 interval oracle 相等，prepared+Context+保留输出峰值45542、raw8309、902回调/82082样本、unprepared0，默认30秒预算内受控11597ms；长期计算额度不随帧增长。另覆盖NA、缺失、重复引用、跨月Float、分时费用、系数、单位换算、面积、不同分类提示顺序与失败清理。证据 report-consumer-full-fantom.log。

真实捕获 zeda main 的单个 profile 私有回放（无FIN I/O）也通过：9个顶层字段/业务组、5个extra组与先前冻结整段结果零差异，保持原截至14:38:28.503447的末段；生产者只按原对齐小时水位推进，消费者不截短末段。385回调/12094捕获样本、unprepared0、峰值117453、raw691；关闭后temporary/raw均0，35条有限生产者元数据继续如实计账。该项只含当前期一个profile，不能与12报告/同期默认路径作同工作量性能比较。默认整包回放另验证provenance内8个必需键、12报告60槽中的59个实有组（含warnings）相等，仅periodsCaptureId归一化，原缺省energy-flow coverage仍缺省。见 report-consumer-native-main.stats.json、report-consumer-parity.json；SDK冻结包 report-consumer-offline-test.pod SHA59676FFE1D5CAD6E1D93B0D56E0799CEA1C06A50868AB7FBAEA62C158848E2FD。FIN Expert连接器通用离线契约不适配此私有Fantom消费类，仍未通过/目标版本未验证，不冒充SDK编译或FIN实机证明。

此时仍没有完整消费者注册表；日报/时段/用途、空间仅摘要输出、热图、flow/COP/规则与全包公平1000诊断尚未统一接入。当前私有profile的最多1000来源行及1000子区间不等于全包1000配额，未宣称全部输出/全9模块年度通过。普通路径和安装包不切换，版本仍0.14.1；只读账号按用户暂缓。安装包hash本轮复核仍ED905...51A4，但观察到FIN已由其他操作变为PID34644；原PID44028的30分钟观察不能套用于新进程，本开发聊天未执行该重启。

日均负荷与用途已接同一私有消费缝：固定24个本地小时和最多6个峰谷平桶，独立累计小时LineFold与分时ValueFold；严格日均除原样本数、已有量日均除真实数值样本数，COP先累计操作数，传感器保持原时长权重，分时仍为区间总量。全区间四种fold独立保存，daily不再保留根本不输出的逐小时period数组。用途继续使用原EndUse.resolve和原聚合/重叠校验，不借子表补主点。原daily输出仅增加读取已冻结桶的分支，普通报告仍按原ticks计算。

专项5类63方法3795校验通过；用途新增后另2类4方法80校验通过，覆盖缺测/NA、跨日大数、25h DST、部分小时、面积、峰谷平、显式总分混选与用途。当前增量没有再跑完整套件，前述90类完整结果明确对应9191b1e7。真实捕获main的daily和utility私有离线回放，各9个顶层字段及8个extra组与原face-daily/face-endUse零差异；峰值119452/117291、raw691、各385回调/12094样本、unprepared0，关闭后raw/temporary均0，有限元数据35继续计账。末段保持原截至时刻，未将小时均值与分时总量混用。默认整包回放8必需provenance、12报告60槽59实有组再次相等，仅periodsCaptureId归一化。证据daily-consumer-tests.log、utility-consumer-tests.log、daily/utility-consumer-native-main.parity.json及daily-utility-default-parity.json；离线冻结包daily-utility-consumer-offline-test.pod SHA4C19DFE0EE22BC286F4D4F8ECB59D2D3A3C2CCA5518CB6C7641F466F9F2664F9。连接器通用离线契约仍未通过/版本未验证，不替代实际SDK编译与回放。

未部署或切默认：工作时段、空间仅摘要、热图、flow/COP/规则、消费者注册表及全包诊断仍待；当前每报告保守预留完整配置元数据，不能把单个main私有回放外推为81个空间焦点/全9模块共同满足200k。下一步须按实际共享关系和真实新建输出容器建立联合所有权，继续保留全部现有保护，而不是降低小时数据的计账单位。

元数据与输出准入续批：18个own daily对象加1000个无关catalog点已先复现构造阶段PREPARED_READ_LIMIT。去掉未发生的深catalog克隆预留，改为保护向量每新引用先准入、每个line/membership/detail输出对及可变来源/面积/费率容器求界；line.normalizationArea生成图逐项转移到output（包括perArea=false不进DTO的图），没转移则由state清除，只清生成Map不改nativeArea借用值。finish临时来源并集/面积scratch先准入，dropGraph的vals/dup清理空间一直保留至输出关闭；最终保留数据图按identity遍历是下界验证，不冒充临时峰值证明。capture已经限制子区间，最终证据共享其独立行而不再浅clone第二图，诊断内容/配额不变；这仍不是全包1000方案。

新增帧内header RED证实原retain(2)不足覆盖复制的18条header字段。仅owned-frame路径按每slot最大header/裁剪引用和可复用copy scratch准入，保留原重复读取/诊断裁剪顺序，不缓存数值；借用header只在下次node前消费，freezeEvidence独立方法返回后再做detail替换。framed无输出owner的knownEvidence快照明确拒绝，mergeKnown须同frame/budget；legacy计数与prepared小时单位不改。

本批精确源码完整91类718方法260672校验通过（283285ms，旧显式1800秒容量夹具仍不作为生产30秒证明）。专项5类35方法14586校验通过：own保留图37408/输出准入54266/联合峰161726；10个重叠scope保留180对details，为38508/58892/182822；组织服务范围含排除图18594/27411/110783；utility同源40566/51338/128393、兼容alias38376/48775/125359；100小时1000诊断边界50318/66602/174062，near-full拒绝后peer及原catalog不变。state先关后输出仍可读，关闭输出后逃逸行/面积图均清空。82源1000小时完整profile仍与原整段相等，峰59543/raw8309、902回调/82082样本、unprepared0。

捕获main私有profile/daily/utility各9个必需顶层字段及5/8/8个必需extra组零差异，峰91280/93796/91007；各385回调/12094捕获样本、关闭后raw/temporary0，有限元数据35仍计账；默认8必需provenance/12报告60槽59实有组保持相等，仅periodsCaptureId归一化。数据图、scratch及header准入均只覆盖当前七类，不能外推后续flow/COP/working。证据owned-admission-full-fantom.log、owned-admission-final-tests.log、owned-admission-native-parity.json、owned-admission-default-parity.json；离线包owned-admission-offline-test.pod SHA2E1E0069EDA39FF658C7BEDDEE68A28DEE40CA0C150DC4D0E4D64160397B1877。FIN Expert通用连接器离线契约未通过/目标版本仍未验证，与SDK执行证据分开记录。安装/默认路径不切换，完整9模块/全包诊断/联合源注册/实机年度仍未完成。

### S1 明确全部消费计划与可合并状态

在Cockpit现有计划旁列出consumer：原请求/同期、维度对象集、category/metric、period、queryEnd、费率/日历/COP与区间边界。抽取现有report定义，避免另写一份不同的选择/去重逻辑。所有读对在原计划内；读取后禁止追加FIN范围。

测试：从当前9模块输入生成确定计划；无/有日历、COP、预算、辅助能源、半小时费率及DST。与现有read lookup轨迹逐项比对；不可用能力保留原降级。

### S2 单源扫描与原计算消费缝

先建立私有可暂停生产缝，默认prepare不切换，不提前做租约减账。扫描游标和消费小时分离：保留block未消费tail、clean details、clean previous/last、待消费闭合interval、consume hour。仅removeNA遵旧语义不推进关闭；null/NA/拒绝数字仍可更新clean previous，不能统一skip到正常数字。

当前小时可定稿需其所有start归属区间已处理，或原规划读域真实耗尽；读到任意一条下一记录不足以证明区间完整。Jan→Sep闭合端只能在原规范化窗口±既有1day上下文内取得，保持整段秒数归起点一次、内部strict小时incomplete。收到Sep端后不得沿原while循环立即生成Jan→Sep全年prepared矩阵。

block/density split是合法重复callback尝试，原计数如实记录，不承诺每raw仅一次。所有source tails与items/byTime/clean结果须按原raw-held与prepared/Context两类guard分别真实计账，不能合并单位或忽略尚有引用的对象。准入不足时确定性失败，不丢尾重扫、不死循环。必须先证明最大同时存活状态与最小可进展条件，才建真实回收。

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

每个出口固定原归约树：scope先同小时跨表再跨小时，selectionTotals先每表跨小时再跨表；quality同rank保留先者、known首invalid和sources首次顺序不换。coverage是min(per-source sum)，不得改成sum(hourly min)或交集；长区间不能裁3600。COP period=sum(N)/sum(D)，首小时D=0不自动使period无效；Flow整段own总量后相减，不等同逐小时Leak路径。warnings等非数值输出也保留原consumer/line/hour访次优先。

本步骤是主要风险：现有Report把小时循环、knownReads及输出组装绑定；需抽出内部fold接口，而不是写一个全新的通用报告框架。预计触及Report、Context、Cockpit与各face/flow/efficiency/rules适配，约10-15个生产文件；在证明细粒度oracle前不得切换默认读取路径。普通历史报表路径不改。

### S4 真实所有权与统一峰值

每源使用一次性lease，计入prepared索引/strict/各queryEnd known/稀疏domain、所有消费者缓存、未完成的小时关联状态、解包临时对象及保留输出状态。源结束后清空Stream、Context.byPoint/knownReads/cache/baseline与consumer临时引用；最终输出只拥有不反向引用histories的业务行和有界诊断。函数返回后才能释放对应lease；重复释放/负计数必须失败。

200000 prepared+Context共同峰值、50k原始块、200k原始held、20M扫描、30s全请求、1000全包诊断和8MiB输出原样保留。source callback数量与预算统计逐一对应，不以日桶/数组为1条掩藏标量；释放后对象不能被reports/knownReads/闭包保留。最大输出本身超限仍明确拒绝。

测试：199999/200000/200001边界；多源不同时结束、消费者抛错、半成品不泄露、并发请求隔离；验证峰值包括解包和最终输出，引用审计/结构遍历断言。

### S5 渐进接入与实机

先在受控路径接入完整9模块，与原整段引擎比较全部业务字段；过后才接真实FIN调用。首轮使用已捕获的真实5源main与17源site前缀，明确区分离线回放和FIN I/O。然后只读捕获剩余源或在候选实际FIN查询全部82源，不将未捕获/缺测转0。输入/配置变化应单列，不能误判数值差异。

统一候选需要新版本和包哈希。实机重复cubeTest、zeda site/main/leaf本年+去年同截止、固定4816与既有缺测、所有9模块和导出；源计划及unpreparedLookupCount=0；覆盖证据、类型/质量、每表费用、预算/M4和截图一致。readonly按用户暂缓。原同版本30min证据不能替代新候选同进程观察。

## 本轮边界

- f4394d90手机修正已纳入0.14.1，控制层与原生275/344已分别记录；完整同尺寸/PDF验收仍未整体关闭。
- 5470d402是真实有证明空域的最小优化，不宣称site问题关闭。
- 完整有界调度及真实释放尚未实现，默认仍整批prepare。此审计不以文档替代交付；若不能保持上述全部合同，先保持当前明确422，不上线静默降级或假数据。

工作时段/工作日私有消费缝已接：每对象只有两个分类桶，保留严格/已有量各自LineFold、原小时顺序、传感器时长权重与COP操作数归约；全区间四fold独立，空分类为真实0，非空缺测不补零。日历工作日例外、手动空时段、缺日历与面积口径复用原输出。working不保留无用逐小时period；输出value/source图及finish临时图在复制前准入，state/output分离关闭。普通入口/隐藏菜单/安装包不切换。

功能RED为reportConsumerPlan；修正执行参数后的专项5类65方法3991校验通过（working-consumer-final-tests.log），覆盖25h DST、重复小时、非整小时、NA、零分母、失败peer隔离；首次执行误带不存在EnerCubixWorkingTest，记录为无效整套执行，未计通过。18设备+1000无关catalog点的工作日输出保留图下界16868、输出准入25776、联合峰106657。此前完整91类718方法260672校验仍对应39b03c00，本增量未重复完整套件。

捕获main另用独立budget的原整段计算作oracle，带工作日/时段与例外配置；workingHours和workingDays各9个必需顶层及6个extra组完全一致，来源诊断采样不同未作相等声明。私有计算峰90803/raw691、385回调/12094捕获样本、unprepared0，关闭raw/temporary0，有限元数据35继续计账，无FIN I/O。默认整包8必需provenance/12报告60槽59实有组仍相等，原缺省coverage保留，仅periodsCaptureId归一化。working-consumer-evidence.json与working-consumer-native-parity.json；离线冻结包working-consumer-offline-test.pod SHA9B3C52C66CF3DCCF5D97D8F8F59ADBC9F9898FF748ED02124BFE48BE34678C61。全局联合读取/公平1000诊断、空间仅摘要、热图、flow/COP/规则和实机全站年度仍待，未提升为实机验收。

空间仅摘要与热图选择性输出已实现私有缝。81焦点+18主点+1000无关catalog先复现完整小时报告构造PREPARED_READ_LIMIT；summary仅允许profile/energy/non-area物理scope，保留原totals/knownTotals/usageCoverage三个消费组，不生成未使用series/details/诊断；同小时跨表与独立整段归约不变。该受控例输出图下界15228、输出准入75187、私有联合峰126656。逐项对照缺测、NA、别名同源与Wh换算通过。

热图只保留一个本地日的临时点，再输出原规则允许的完整日单元格或排除日原因，保留23/25h DST及重复小时、部分查询/截止、真实零和清洗质量。按原单小时LineFold而非直接复制tick.value；整日输出先准入再转移来源数组，state/output独立，失败不发布/不重试半成品，不接收带历史ticks的定义。初次语义对照发现全字符串Map被Fantom推为Str:Str，与旧Str:Obj?虽同内容但不相等，最小运行复现确认后显式指定类型；没有归一化掉此差异。

本批精确源码完整93类730方法261166校验通过，217501ms（selective-output-full-fantom.log）；其中旧1800秒容量夹具不提升为原生30秒证明。专项4类40方法2149校验通过。真实捕获main离线summary三组等旧profile，峰11336；热图2328格/209排除日等旧time模块，峰36416；各385回调/12094捕获样本、unprepared0、关闭raw/temporary0、有限metadata35继续计账，无FIN I/O。默认整包8必需provenance与12报告60槽59实有组等旧结果，原缺省flow coverage保留，仅periodsCaptureId归一化。证据selective-output-evidence.json/native-parity.json/default-parity.json；冻结离线包selective-output-offline-test.pod SHAD27A9286F131669342FCD6D62F5489EA8D40584D7F85444B32FA085A0C96811A。

所有权边界补记：当前consumer将调用方提供的dim.records视为借入输入；Dimension.make在Context.useOwner前的r.dup/variables复制及索引，尚不属于consumer计数。联合注册时必须共享并为每维度投影单独准入，模型owner覆盖输出借用期；不能将本批私有source/context/output峰外推成全模型、JVM heap或9模块联合证明。注册表、全包公平1000诊断、flow/COP/规则适配与最终候选实机年度尚待；当前安装/默认不切换，只读账号仍按用户暂缓。

共享目录私有所有权已接。功能RED确认canonical记录/variables复制未准入；新增owned投影在复制前准入原始索引、r.dup、变量Map、record/byId引用及有限canonical路径scratch。一个规范化投影的records/byId/originals真实共享给三种维度，只建轻量view，Context共享children，Report共享Area，所有输出共用一个保护向量。原普通Dimension构造沿同一初始化逻辑，不启用owner；默认路径不切换。模型没有历史或持久化缓存。

模型owner覆盖计算和输出借用期：记录绑定owner并在任何owner.entries非0时拒绝释放，包括部分close失败；不依赖早先callback执行便提前减引用。先关fold-state仍可读输出，输出关后才允许清规范化副本；只清新建Map头/variables/索引，不清原冻结配置的子Map。失败、foreign/closed owner、活动frame阻止state关闭、near-limit半构造与别名失败均通过。另功能RED发现metadata-only定义在首帧前丢主点单位，现仅借原主点metadata的单位字符串冻结索引，保持category/record/history优先级，known/bound继承并在过期后断根；无额外点或历史读取。

专项5类88方法2455校验通过，24255ms（shared-catalog-final-tests.log）。1000无关点+三view的新容器图下界21061，model准入23122，峰24102；81焦点+18主点+1000catalog+24h含真实新model后的私有联合峰144530，输出图下界15228、输出准入74087、model23513，非之前借入目录峰。实际捕获main的profile9顶层+5extra/summary三组/热图2328格209排除日均等冻结旧结果；含model峰109365/29421/55882，385回调/12094捕获样本、raw691、unprepared0、关闭raw/temporary0，有限35源元数据仍计账，model关闭前23838/23838/23832。无FIN I/O。默认8必需provenance与12报告59实有组仍相等，原缺省flow coverage保留，仅periodsCaptureId归一化。

证据shared-catalog-evidence.json/native-parity.json/default-parity.json，冻结离线包shared-catalog-offline-test.pod SHAF19946408CA33078A11591679C36F7C9951AC21E32D572333FED31FA816C4934。本增量未重复完整套件，最近完整93类730方法261166校验明确对应d9f40154。原冻结请求目录作为明确借入输入，图遍历仍只是新容器下界，不作JVM heap证明。尚未将全九模块注册及公平1000诊断接通；flow/COP的特殊记录集不能未经兼容性证明便套用同一规范化目录。仍无部署/默认切换，原保护不放宽，只读账号继续暂缓。

# EnergyCubix 功能对照与验收账本

## 当前实现与历史证据边界（2026-10-29）

当前开发和集成以 `developer` 为准，实际版本以 `enerCubix.pod/build.fan`、包清单及安装回读为准。下表大部分证据来自 0.1.0 历史基线，保留其原版本和验证层级，不自动代表当前版本重新验收。

- 自 0.12.9 起，所有设备能耗只读各自明确绑定的主点原生历史；FIN 负责采集与存储，不创建或读取辅助归档替代主点。配置、查询与数据完整性原则见 [README](../README.md) 和[当前接口契约](../contracts/api.md)。
- `TASK-01`、`TASK-02` 的派生重算/计算开关和 `TASK-04` 的派生历史点已退出当前产品；旧接口明确拒绝，不能因为保留旧测试证据而重新启用。`TASK-03` 的源历史采集由 FIN 管理。报警扫描与报警开关仍保留。
- 已有点位、历史和业务配置不得因归档机制停用自动删除、打 trash 或重绑；用户单独授权的历史清理不属于正常运行行为。
- 0.12.9 的主点读取、跨报告、双语导出及部署证据位于 `out/energy-flow-0.12.9/verification.json`；后续界面加载与能流范围交付保留各自版本。用户于 2026-10-29 接受现有查询报表，旧版验收与发布票已在 Linear 结项。
- ALL-11 的安装与构建、ALL-12 的远端 CI、ALL-13 的原生浏览器认证分别核验。受控 API 回放、已安装依赖构建、真实浏览器 Cookie 会话不能互相替代；最终状态以对应 Linear 证据为准。
- 0.12.16 的界面和原生应用标题跟随 FIN 用户语言，由只读 `session` 接口先行初始化；浏览器偏好和旧语言选择不再覆盖。工程分支合并后实际 CI 为 275 项前端测试和 14 项受控浏览器场景通过，见[工程验证记录](team/verification.md)。原生 `admin` 只读和短范围查询已核；当前 `-noAuth` 实例不具备会话失效／负向权限的完整验收条件，ALL-13 保持未完成。

## 原 0.1.0 功能基线（历史）

目标：FIN 5.3.0.2761 / finSeed 0.1.0。来源：`contracts/api.md` 0.1；已批准的旧版范围来自《建筑设施能耗分析系统 SEED 用户手册 1.6》（封面版本 1.6.0，60 个 PDF 页面，印刷第 1 页为 PDF 第 4 页），原文件位于 `\\192.168.0.157\home\Drive\jci\Seed\seed-doc\建筑设施能耗分析系统SEED用户手册1.6.pdf`。旧手册的功能承诺以已批准实施范围为准，章节与页码见 [baseline.md](baseline.md)。此表不把“有按钮”“已编译”或“存在源码”认定为旧版业务等价。下表按实际执行证据更新；“通过”只指列出的测试输入和层级，不能扩大为旧系统全部现场场景认证。

范围排除：旧系统登录、用户、角色、密码和主题管理；这些能力使用 FIN 原生机制。其余业务控制项均保留在下表。

状态中的“离线”指实际SDK测试，“浏览器”指受控API的真实Edge交互，“实机”指独立FIN项目内的实际Folio/历史/HTTP核验。各证据编号、日期、审计ID及验证限制见 [validation.md](validation.md)。

| 编号 | 业务能力 / 粒度 | 验收要点 | 状态 | 证据 |
|---|---|---|---|---|
| CFG-01 | 分组新增、编辑、删除 | 名称/面积/说明、父子关系、占用保护 | 离线/实机通过 | B1；UI-M；N1/N2（复制/移动、mod 冲突、占用保护） |
| CFG-02 | 分组/计量表/总表/传感器四类树节点 | 点位、父节点、单位、位置、分类/分项/能源/费率/表达式 | 离线/实机通过 | B1/B2；UI-M；N1/N2（树、面积、量程/效率等属性往返） |
| CFG-03 | 计量节点业务参数 | 面积、最大值、参与合计、实际/基准效率、报警开关/限值 | 离线/实机通过 | B1/B2；UI-M；N1/N2（树、面积、量程/效率等属性往返） |
| CFG-04 | 树节点复制 | 配置完整复制、引用正确、名称/父节点冲突提示 | 离线/实机通过 | B1；UI-M；N1/N2（复制/移动、mod 冲突、占用保护） |
| CFG-05 | 树节点移动 | 乐观锁、环路拒绝、目标类型/占用约束 | 离线/实机通过 | B1；UI-M；N1/N2（复制/移动、mod 冲突、占用保护） |
| CFG-06 | 删除与并发写保护 | 拒绝被引用/占用记录、过期 mod、重复名称和循环配置 | 离线/实机通过 | B1；UI-M；N1/N2（复制/移动、mod 冲突、占用保护） |
| CFG-06a | 节点名称唯一与空节点删除 | 同一命名范围唯一，只有空且无引用的节点可删 | 离线/实机通过 | B1；UI-M；N1/N2（复制/移动、mod 冲突、占用保护） |
| CFG-06b | 虚拟节点汇总开关与传感器排除 | 虚拟节点默认不计总量，显式开关生效，传感器不计入能耗总值 | 离线/实机通过 | B1/B2；N1（总表、分表、虚表独立预期） |
| CFG-06c | 各分类主表 | 主表按分类确定，总表与子表不重复累计 | 离线/实机通过 | B1/B2；N1（总表、分表、虚表独立预期） |
| CFG-07 | 分类管理 | 分类单位、重复项处理、引用保护 | 离线/实机通过 | B1/B2；UI-M；N1（分类/子类/用途真实 Folio 配置） |
| CFG-08 | 子分类管理 | 所属分类、标煤系数、二氧化碳系数 | 离线/实机通过 | B1/B2；UI-M；N1（分类/子类/用途真实 Folio 配置） |
| CFG-09 | 分项用途管理 | 所属分类及记录引用一致性 | 离线/实机通过 | B1/B2；UI-M；N1（分类/子类/用途真实 Folio 配置） |
| CFG-10 | 固定与绝对时段费率 | 默认单价、起止日期/小时及重叠校验 | 离线/实机通过 | B1/B2；UI-M；N1（周期起点五费率：288/216/264/188/188 元） |
| CFG-11 | 周时段费率 | 工作日、小时边界及跨日规则 | 离线/实机通过 | B1/B2；UI-M；N1（周期起点五费率：288/216/264/188/188 元） |
| CFG-12 | 月阶梯与年阶梯费率 | 累计周期、各阶梯阈值、无上限末档 | 离线/实机通过 | B1/B2；UI-M；N1（周期起点五费率：288/216/264/188/188 元） |
| CFG-13 | 费率例外 | 日期和小时例外优先级、边界与冲突 | 离线/浏览器通过 | B2.testTariffFlatWeeklyExceptionAndAbsolute / testAbsoluteTariffSplitWithinHour；UI-M |
| CFG-14 | 日历管理 | 峰/谷/工作小时、ISO 工作日、指定日期例外 | 离线/实机通过 | B1/B2；UI-M；N1（峰谷与周一工作日；调休例外见 B2） |
| CFG-15 | 表达式管理 | 公式、变量到计量记录映射、非法/循环公式拒绝 | 离线/实机通过 | B1/B2；UI-M；N1（表达式216、COP0.5及来源；非法/循环/零分母见 B1/B2） |
| CFG-16 | COP 配置 | 分子、分母引用与分母为零行为 | 离线/实机通过 | B1/B2；UI-M；N1（表达式216、COP0.5及来源；非法/循环/零分母见 B1/B2） |
| CFG-17 | 报表模板 | 保存/加载完整请求、本周/上周/本月/上月/本年/上年相对时间 | 离线/实机通过 | UI-R 模板预设/路径锁定/退出；N2 真实模板保存、更新、另存、删除 |
| CFG-17a | 模板对象锁定与重置 | 固定对象清单，加载后相对日期重算，重置恢复约定默认 | 离线/实机通过 | UI-R 模板预设/路径锁定/退出；N2 真实模板保存、更新、另存、删除 |
| CFG-18 | 显示配置 | 可见指标与轮播秒数保存和恢复 | 离线/浏览器通过 | UI-C 两分类轮播、保存隐藏；UI-R 20秒及今日/月/年同截止时刻 |
| CFG-19 | 点位绑定 | 能耗/参照/运行时间角色及别名 | 离线/实机通过 | UI-M 批量绑定与角色；UI-V 别名；B3；N2 真实点目录及绑定/解绑 |
| CFG-20 | FIN 点位浏览 | 搜索、分页、单位/类型/历史模式/范围/状态字段 | 离线/实机通过 | UI-M 批量绑定与角色；UI-V 别名；B3；N2 真实点目录及绑定/解绑 |
| RPT-01 | 用能曲线 profile | 多节点、小时/日/月/年、能耗/费用/标煤/CO2、单位面积 | 离线/实机通过 | B2/B3；UI-R/UI-X；N1/N2 profile240、费用288、CO2 136.8、面积0.24 |
| RPT-01a | 四种指标与 N+1 分类视图 | 每类与总计视图可切换，量纲与类别不混算 | 离线/实机通过 | B2/B3；UI-R/UI-X；N1/N2 profile240、费用288、CO2 136.8、面积0.24 |
| RPT-02 | 排名 ranking | 选中节点排序、稳定表格键、空选提示 | 离线/实机通过 | B2.testRankingProportionAndUtilityMissing；UI-R；N1（144/72排名、2/3与1/3占比） |
| RPT-03 | 占比 proportion | 分类/节点构成、总值与分项对应 | 离线/实机通过 | B2.testRankingProportionAndUtilityMissing；UI-R；N1（144/72排名、2/3与1/3占比） |
| RPT-04 | 分项能耗 utility | 根及第一层分组按分项用途汇总、单位与转换系数 | 离线/实机通过 | B2.testUtilityMastersAndUnrelatedSubgroups / testUtilitySharesStayWithinEachSelectedNode；UI-V；N1 utility144 |
| RPT-04a | 按能源汇总与选中对象占比 | group-by-utility 与 selected-proportion 语义分别核验 | 离线/实机通过 | B2.testUtilityMastersAndUnrelatedSubgroups / testUtilitySharesStayWithinEachSelectedNode；UI-V；N1 utility144 |
| RPT-05 | 日均负荷 daily | 24小时平均、峰谷及项目时区日边界、表格与曲线一致 | 离线/实机通过 | B2.testDailyLoadBandsAreIntervalTotals / testDailyWithoutCalendarUsesUnknownBand；UI-D；N1峰20/谷20/平200 |
| RPT-06 | 同比/环比 comparison | 对比区间、时间对齐、缺失值和变化率 | 离线/实机通过 | B2.testExplicitComparisonAndZeroReference / testSameRangeComparisonReferenceIds；UI-R；N1同区间差0 |
| RPT-07 | 一次能源 primary | 原业务转换/汇总语义及品质标识 | 离线/实机通过 | B2.testCoefficientsAndArea / testDefaultTariffCalendarAndMissingCoefficient；UI-R；N1 29.496kgce |
| RPT-08 | COP 效率分析 | 分子/分母同期值、零/缺失分母 | 离线/实机通过 | B2.testCopAggregatesBeforeDividing / testVirtualCycleAndDivisionByZero；UI-R；N1 COP0.5 |
| RPT-09 | 泄漏分析 leak | 总表减子表、缺失子表/负差值/不完整覆盖品质 | 离线/实机通过 | B2.testLeakSignedAndSubgroupMaster；UI-R；N1总240、分216、差24、10% |
| RPT-10 | 工作时间 workingHours | 工作小时筛选、非工作小时与日历例外 | 离线/实机通过 | B2.testCalendarWorkingAndNonworking / testWorkingHoursIsIndependentOfWorkDays；UI-R；N1工作100/非140、周一240/0 |
| RPT-11 | 工作日 workingDays | ISO 星期、工作日例外、工作/非工作日 | 离线/实机通过 | B2.testCalendarWorkingAndNonworking / testWorkingHoursIsIndependentOfWorkDays；UI-R；N1工作100/非140、周一240/0 |
| RPT-12 | 回归 regression | X/Y 选择、配对样本、斜率/截距/R²、常数/缺失边界 | 离线/实机通过 | B2.testCopAndRegression / testRegressionFitLineEndpointsAndUndefinedFit；UI-V；N1 24对、slope0/intercept6 |
| RPT-13 | 趋势 trend | 业务趋势语义、时间分桶、缺失品质显示 | 离线/实机通过 | B2/B3；UI-V 独立纵轴及导出原值；N1原始累计1000与原时间戳 |
| RPT-14 | 总览 dashboard | 明确全量汇总规则、比较指标、显示配置 | 离线/实机通过 | B2.testDashboardGrandTotalsAcrossCategories；UI-C/UI-R；N1总240、费用288、CO2 136.8；同截止时刻请求见 UI-R |
| RPT-14a | 总览轮播与手动切换 | 默认 20 秒轮播、手动切换、显示项目保存 | 离线/实机通过 | B2.testDashboardGrandTotalsAcrossCategories；UI-C/UI-R；N1总240、费用288、CO2 136.8；同截止时刻请求见 UI-R |
| RPT-14b | 总览同截止时刻比较 | 今日与比较日采用相同截止时间，月/年与上年同周期比较 | 离线/实机通过 | B2.testDashboardGrandTotalsAcrossCategories；UI-C/UI-R；N1总240、费用288、CO2 136.8；同截止时刻请求见 UI-R |
| ENG-01 | 累计表历史 | 差值、前置样本、复位/回绕/异常处理 | 离线/实机通过 | B2/B3；N1实际15分钟FIN累计/ENDSTAMP区间历史、上海时区；复位/跨月年见 B2 |
| ENG-02 | 区间表历史 | 区间边界与分桶、不重复计量 | 离线/实机通过 | B2/B3；N1实际15分钟FIN累计/ENDSTAMP区间历史、上海时区；复位/跨月年见 B2 |
| ENG-03 | 采样/COV 历史 | 有效覆盖范围、缺失/非数值不隐式归零 | 离线/实机通过 | B2.testCovAndPartialGaugeAverage；B3；N1缺失前日 null/missing；原生COV补证见验证说明 |
| ENG-04 | 时区与区间 | [from,to)、项目时区、小时/日/月/年边界 | 离线/实机通过 | B2/B3；N1实际15分钟FIN累计/ENDSTAMP区间历史、上海时区；复位/跨月年见 B2 |
| ENG-05 | 数据品质与来源 | null、quality、sourceIds、警告贯穿响应/曲线/表格 | 离线/实机通过 | B2/B3；UI-R/UI-X；N1逐值quality/sourceIds及原始边界1000保持 |
| ENG-06 | 纯函数与源数据保护 | 引擎不修改输入，客户端不自行计算能耗 | 离线/实机通过 | B2/B3；UI-R/UI-X；N1逐值quality/sourceIds及原始边界1000保持 |
| TASK-01 | 历史重算 | 日期范围、任务状态/进度/消息/最近运行持久化 | 离线/实机通过 | B4；UI-M；N1派生24个10kWh原生回读、同范围二次重算完全一致 |
| TASK-02 | 计算开关 | 保存/恢复状态、关闭后不产生新派生计算 | 离线/实机通过 | B4；UI-M；N2计算/报警分别启停及native job配置 |
| TASK-02a | 计算与报警任务独立 | 分别启停，不把报警关闭等同于能耗计算关闭 | 离线/实机通过 | B4；UI-M；N2计算/报警分别启停及native job配置 |
| TASK-03 | 原生同步与派生重算 | 两种动作语义明确，不改原始点历史 | 离线/实机通过 | B3/B4；UI-M；N1只写自有派生点并回读原始1000；上游采集器由FIN负责，未测现场设备同步 |
| TASK-04 | 派生历史点 | finSeed 所有权标记、独立点、重复运行幂等 | 离线/实机通过 | B4；UI-M；N1派生24个10kWh原生回读、同范围二次重算完全一致 |
| ALM-01 | 报警开关与扫描 | 全局与节点限值、扫描结果及任务状态保存 | 离线/实机通过 | B4；UI-M；N1小时阈值24条及原生身份确认；N2真实HTTP确认 |
| ALM-02 | 报警列表与确认 | FIN 当前用户、mod、备注/时间、重复确认边界 | 离线/实机通过 | B4；UI-M；N1小时阈值24条及原生身份确认；N2真实HTTP确认 |
| SEC-01 | 原生认证与权限 | 无独立登录；未登录/非管理员写入被拒绝 | 离线/实机通过 | N2/N3 原生身份、匿名303登录挑战、op写配置/任务/报警403；UI-X 401/403显示 |
| SEC-02 | 同源与 CSRF | finCsrfFetch、错误状态、无演示回退 | 分层通过；浏览器原生会话未验 | B5；UI-X 原生登录HTML与会话失效；N2真实/finStackAuth返回attest；原生Cookie浏览器链路未测 |
| SEC-03 | Folio 持久化 | 原生 Ref 关系、seedConfig、重启后配置恢复 | 离线/实机通过 | N4：重启前后同一Ref、seedConfig、mod完全一致；N1真实Folio读写 |
| UI-01 | 桌面分析工作区 | 侧栏、选择树、筛选器、图表与表格 | 离线/浏览器通过 | UI-M/UI-R/UI-X；桌面/手机布局、各配置表单、错误/空值/会话/冲突 |
| UI-02 | 手机布局 | 导航收拢、筛选与操作可用、无横向溢出 | 离线/浏览器通过 | UI-M/UI-R/UI-X；桌面/手机布局、各配置表单、错误/空值/会话/冲突 |
| UI-03 | 表单完整性 | 所有配置种类可编辑、费率/日历结构化编辑 | 离线/浏览器通过 | UI-M/UI-R/UI-X；桌面/手机布局、各配置表单、错误/空值/会话/冲突 |
| UI-04 | 状态显示 | 加载/空数据/错误/缺失品质/保存冲突可见 | 离线/浏览器通过 | UI-M/UI-R/UI-X；桌面/手机布局、各配置表单、错误/空值/会话/冲突 |
| UI-05 | 原始点多趋势 | 参照/运行时间/能耗别名、独立轴、多点对照、缩放与导出 | 离线/实机通过 | B2/B3；UI-R/UI-V 参考别名、X轴缩放、图例及各单位纵轴；N1原始趋势 |
| PKG-01 | 单一混合 Pod | finSeed 0.1.0、Ext/Lib/lang 索引、菜单/语言/UI 资源 | 包检查/编译通过 | out/final-build.log；out/acceptance.json；最终包SHA见 validation.md |
| PKG-02 | 目标 FIN 实机 | 扩展启停、菜单、资源、认证 API、重启恢复 | 离线/实机通过 | N1/N2/N3/N4；入口302、index/module200及JS MIME、FIN attest、原生权限与重启恢复 |

| EXP-01 | Excel / Word / PDF / 图像导出 | 同一报告快照、真实文件结构、单位/品质/来源 | 浏览器通过 | UI-X 四种非空文件解析；分类过滤与XLSX一致 |
| EXP-02 | 长报告导出 | 1001明细完整、PDF分页、图像范围明确 | 浏览器通过 | UI-X 每行PDF覆盖、XLSX末行1002、PNG高度<5000 |
| EXP-03 | 打印 | 浏览器打印触发、打印布局 | 浏览器通过 | N5 实际240kWh报表触发打印、单页PDF及渲染检查；正常构建包含打印宽度修复 |

UI-M=management.spec.ts；UI-R=reports.spec.ts；UI-X=exports-access.spec.ts；UI-V=visual-controls.spec.ts；UI-C=dashboard-categories.spec.ts；UI-D=daily-bands.spec.ts。B1/B2/B3/B4/B5依次为SeedConfigTest/SeedEngineTest/SeedHistoryTest/SeedJobsTest/SeedRestTest。N1/N2/N3为out/runtime-acceptance.json内计算、真实HTTP、只读权限三部分；N4为out/restart-persistence.json。全部脚本、输入与固定旧版来源均在仓库；实际结果见验证说明，不以源码存在代替实机证明。

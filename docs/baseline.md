# SEED 功能基线

核对日期：2026-10-21。来源目录为 `\\192.168.0.157\home\Drive\jci\Seed`，只读研究，未修改原项目。

| 来源 | 固定版本 |
|---|---|
| seed-web-app | `8fdd75535e8ff10fb85d204fa86ae05ee85f29ef` |
| seed-api | `fdadf78ed06d08e4672053baf75f7ea7e7c6ee87` |
| seed-database | `bf6d944ef75da7d738a1dad17f5dcca4317f9312` |
| seed-windows | `f4a7ab951c2b29d4c1f1dff8547fb94d71533925` |
| 用户手册 | `seed-doc/建筑设施能耗分析系统SEED用户手册1.6.pdf`，60 页，封面 1.6.0 |
| 手册 SHA-256 | `a4b51dd39ec4fdeb5cf4f49971853d1c1b29e116364f9e04ae936f48574be763` |

原归档包含不同时间的 Web、API、Windows 服务版本；本实现采用用户批准的功能范围，并以手册及当前源码的实际业务语义核对，不将它们合称为一个已经部署验证的旧系统版本。Web 自带 help.pdf 为旧的 1.5.0，不作完整功能主基线。

以下页码已经对照手册目录的页面图像核对。印刷页码从 PDF 第 4 页开始，所以 PDF 页码等于印刷页码加 3。

| 功能 | 手册章节 | 印刷页码 | PDF 页码 | FIN Seed 对应 |
|---|---|---|---|---|
| 计算、报警启停 | 3.1 管理工具 | 3–5 | 6–8 | 独立计算/报警开关、原生每小时任务 |
| 点用途分类、批量纳入与历史同步状态 | 3.2 网关数据管理工具 | 6–8 | 9–11 | FIN 点目录、energy/reference/runtime 绑定；采集同步由 FIN 保留 |
| 能耗概览、轮播与同期 | 4.2 | 10–11 | 13–14 | dashboard、显示分类及指标、同截止时刻比较 |
| 分类与分项 | 4.3.1 | 13 | 16 | category/subcategory/utility |
| 五种费率、默认及例外 | 4.3.2 | 14–16 | 17–19 | tariff、边际月/年阶梯 |
| 峰谷、工作时段与调休 | 4.3.3 | 17 | 20 | calendar |
| 管理树及节点属性 | 4.3.4 | 18–23 | 21–26 | group/meter/totalMeter/sensor，复制/移动/引用保护 |
| 点位绑定、参考别名 | 4.3.5 | 24–26 | 27–29 | FIN Ref、物理/表达式绑定、binding.alias |
| 表达式 | 4.3.6 | 27 | 30 | 安全四则解析、变量及依赖环校验 |
| COP 配置 | 4.3.7 | 28 | 31 | numeratorId/denominatorId，先合计再相除 |
| 概览显示项目 | 4.3.8 | 29 | 32 | 保留业务分类/指标显示；主题界面设置按用户要求排除 |
| 模板、公共筛选及导出 | 4.4 公共操作 | 32–34 | 35–37 | 相对时间、路径锁定、保存/更新/另存/退出、四种导出 |
| 能耗报告 | 4.4.1 | 35–42 | 38–45 | profile、四种指标口径、总报告及分类报告、参考曲线 |
| 排名 | 4.4.2 | 43 | 46 | ranking |
| 选中对象占比 | 4.4.3 | 44 | 47 | proportion |
| 分项能耗 | 4.4.4 | 45–46 | 48–49 | utility；根及第一层组；柱图与饼图 |
| 日均负荷 | 4.4.5 | 47 | 50 | daily；24 小时平均及峰谷信息 |
| 两类能耗比较 | 4.5.1 | 48–49 | 51–52 | comparison |
| 一次能源折算 | 4.5.2 | 50 | 53 | primary |
| COP 分析 | 4.5.3 | 50 | 53 | cop |
| 总分表泄漏 | 4.5.4 | 51 | 54 | leak；总表减分表，不采用夜间基荷猜测 |
| 工作时段占比 | 4.5.5 | 52 | 55 | workingHours；每日小时，与工作日独立 |
| 工作日占比 | 4.5.6 | 53 | 56 | workingDays；指定日期例外优先 |
| 回归 | 4.5.7 | 53–54 | 56–57 | regression；散点、拟合端点、方程与 R² |
| 报警确认与记录 | 4.6 | 55 | 58 | 小时阈值、原生用户确认身份及保留日志 |
| 多点趋势 | 4.7 | 55–57 | 58–60 | trend；原始样本、曲线显隐、缩放、纵轴调整 |

源码补证：`seed-windows/SpiderService/EnergyAlert.cs` 读取小时用量并检查组及表阈值，`MySQLDAL/seed_energy_db_tbl_energy_alert.cs` 查询 `tbl_space_hourly` 的 `amount`，因此报警按小时检查。`seed-web-app/js/views/dashboard/dashboard3d-view.js` 按返回项目创建轮播卡、默认 20 秒；`settings/DashboardConfig/dashboardContent-view.js` 保存显示分类。

参考曲线补证（2026-10-30）：上述固定 Web 提交的 `seed-web-app/js/views/energy/profile/profile-chart-view.js`，`generateWidget` 先创建各能源图，再调用 `addSeriesWithAxis`；后者第 218–239 行通过 `chart.addAxis({opposite:true})` 和 `chart.addSeries({type:'line',yAxis:series.name})` 将参考点折线叠加至原图的右侧独立轴。该文件 SHA-256 为 `050F4D88F94A1011EED70482E7A3625DE74202C42354615B35BE0228FAB243E8`。EnerCubix 的 profile 据此将参考曲线加入每个分类／单位的用量图，保留缺测断点和独立轴，不另列参考图或将其计入用量卡片；此处为源码依据，不代表旧 SEED 或新 FIN 实机验收。

分项补证：`seed-windows/SpiderService/CalculateHourly.cs` 的 `CaculateSpaceUtilityHour` 先处理有分项属性的总表，再计算其他分项。FIN Seed 按同分项总表优先，跳过根本不含所查分项的子组；匹配分项而历史缺失的对象仍保留缺测。此规则有独立 144/216/240 预期值测试，普通能耗与泄漏规则保持独立。

差异边界：FIN 原生登录、用户、角色、密码、采集器和原始历史库替代旧独立底座；旧登录宣传图、主题设置及独立账户管理不实现。旧的异常原始历史改写行为不迁移；FIN Seed 保留原始历史，以空值、质量和来源表达异常。

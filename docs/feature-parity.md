# FIN 能源管理 当前功能与验证边界

适用 0.16.0 候选版。旧版本逐项账本与原有未提交文案保存在 [历史原文](../archive/prior-documentation/docs/feature-parity.md)。本页不把旧版本实机结果改写为新版本结果。

| 范围 | 当前源码行为 | 本次证据与限制 |
| --- | --- | --- |
| 产品身份 | finEnergy Pod、类型、Axon、业务标签与 API；中英品牌和原生 locale 资源 | 包构建、版本及静态资源检查；原生菜单待真实 grant 后验收 |
| J2 界面 | Deep Blue／Blue／Aqua、Manrope、临时可替换图标；跟随 FIN 与手动语言切换 | 前端类型、构建、聚焦单测及受控中英桌面／手机场景 |
| 原生授权 | FinExt、FinExtMeta；只读状态及机器码；无旧 RSA／免费额度路径 | SDK 测试；真实 feature、缺失、到期、重启与多项目仍待验 |
| 命名空间迁移 | 预览、修订、冲突、完整备份、分存储日志、同日志续作及按迁移字段回滚 | 独立源码复核、17 定向方法106检查和整合后全量回归；无客户项目迁移冒称 |
| 主点历史和当前关系 | 原生主点历史唯一事实源；当前空间、计量、组织归属 | 33个计算引擎文件仅命名替换，整合后后端全量回归；原生同范围迁移对照待验 |
| 驾驶舱 | 本月默认、自定义、同比／环比、六面、预算与核查、同快照导出 | 新UI回放截图；原版运行记录另保留版本，不替代新版授权运行 |
| 分析工作台 | 趋势／24h负荷参考线、排名、占比环图、分项、能流、差额堆积、费用／COP／折算 | 回归及冻结导出场景；异常和覆盖条件按实际结果呈现 |
| 清洗 | 读时过滤、值/NA替代、已知周期回卷、诊断与覆盖；不覆盖原始历史 | 回归和新UI预览；扩展停用后的普通/raw历史与回调仍需实机 |
| 原生报警 | 完整小时能耗判断、持续事件合并、确认与恢复状态 | 既有逻辑回归；迁移后实际报警存储核对待原生环境 |
| 文档和视频 | J2原始素材、完整新UI、双语业务名称、原生FIN建树教学图、自然配音 | 逐图来源及逐文件版本/哈希；发布清单记录最终生成与审阅状态 |

编译与测试是候选证据，集成不是部署，旧图不是新实机证明。维护过程中持续暂停能源任务及配置编辑，直到原迁移日志 `complete` 或 `rolledBack`。客户交付依赖见 [计划](../specs/fin-energy-hq-20261120/plan.md)。

## English verification boundary

The 0.16.0 candidate covers the new namespace, J2 UI, native feature gate and reversible migration. Integrated SDK tests passed 124 classes, 1,026 methods and 300,163 checks. Type/build and controlled browser evidence are recorded separately. Native activation, missing/expired licenses, cleaning callback availability, upgrade query parity and customer-platform acceptance remain pending HQ's genuine grant and target environment. Prior-version runtime evidence is retained with its original version.

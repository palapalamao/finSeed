# FIN 能源管理

FIN Energy is a native FIN Framework Pod for building energy analysis in new projects and retrofits. 中文品牌为 **FIN 能源管理**，英文为 **FIN Energy**。它复用 FIN 的设备、主点历史、身份和报警服务，提供经营驾驶舱、分析工作台、数据清洗、费用、面积强度及事件核查。

当前为 **FIN 能源管理双发行**，中国版采用自有授权，总部版采用 FIN 原生授权。`developer` 是唯一开发与集成基线，`main` 用于稳定发布。总部已确认原生功能标识 `finenergy`。FIN 测试许可证及比利时客户完整 FIN 构建号和操作系统尚待提供。候选构建、受控界面验证与实际 FIN 发布分别记录。

## 现行文档 Current documentation

- [中文与英文文档索引](docs/CURRENT.md)
- [中文架构设计](docs/finenergy-architecture-design.md) · [Architecture](docs/finenergy-architecture-design.en.md)
- [中文接口契约](contracts/api.zh-CN.md) · [API contract](contracts/api.md)
- [中文系统要求](docs/finenergy-system-requirements.md) · [System requirements](docs/finenergy-system-requirements.en.md)
- [中文升级与回滚](docs/finenergy-upgrade.md) · [Upgrade and rollback](docs/finenergy-upgrade.en.md)
- [原生授权说明 Native licensing](docs/finenergy-licensing.md)
- [功能与验证边界](docs/feature-parity.md) · [本次交付计划](specs/fin-energy-hq-20261120/plan.md)

Brochure、Onepage、图文操作手册、技术资料及两版三分钟宣传片统一整理到本次交付目录，实际文件、源码和包哈希以该目录清单为准。旧资料保留在历史归档，不作为新版实机证明。

## 数据与业务原则

FIN 负责点位采集、原始历史存储和访问。FIN 能源管理负责业务配置、只读查询、计算和展示，不另建时序事实库。物理表、实测表及虚拟表都只读取各自明确绑定的主能耗点历史；缺测保持缺测，不以分表合计、公式输入或旧批次替代。

所有查询采用当前生效的空间、计量和组织关系。选定范围先解析有效表计和统计边界，同源和父子边界不重复合计。分项查询按当前关系展开合资格成员；驾驶舱用途面沿用其已冻结的规范集合。已有量、完整区间、NA、零值和规则替代分别说明。

经营驾驶舱默认按 FIN 项目时区查询本月，支持今日、本年和自定义，提供同比与环比选择。焦点定位与明确应用统计范围分开。六面观察、趋势、能流、明细和导出使用同一成功快照。报警需满足启用、阈值、完整小时历史和扫描条件；持续超限合并并同步原生报警。

清洗方案按读取时规则过滤、替代或修正已知周期回卷，显示覆盖和处理诊断，保留 FIN 原始历史。楼宇和楼层面积在应用中编辑，保存到原生 `area`；表计支持引用服务空间或自定义面积。单位面积结果保留分母来源，普通能耗不要求面积。

## 品牌与语言

UI 使用 J2 Deep Blue、Blue、Aqua 与品牌辅助色，随包提供 Manrope，中文采用微软雅黑等系统回退。正式产品 logo 到达前使用可替换的临时图标和普通字体名称。原生菜单通过 `toLocale` 和 `locale/*.props` 跟随 FIN 用户语言；应用默认跟随当前用户，保留手动中文／English 切换。用户输入名称保持原文。

## 授权与升级

技术名统一为 `finEnergy`：Pod、`FinEnergy*` 类型、`finEnergy*` Axon、业务标签及 `/api/{project}/ext/finEnergy/v1`。新项目直接使用新名，既有项目通过管理员预览、冲突检查、备份、明确应用、原日志续作及保护回滚迁移。保留原对象 ID、主点历史和报警确认；维护期间停用旧任务及配置写入，结束后只运行一套任务。

总部版继承 `fin::FinExt`，由 `@FinExtMeta.licFeature` 声明总部确认的功能标识 `finenergy`。实机验收需要包含该功能的 FIN 测试许可证。中国版使用实例级自有授权，兼容现有签名文件，支持导入、删除、机器绑定、限时培训和每项目 10 表免费额度。发行版在构建时确定，安装后的授权页显示当前模式。

## 本地构建

SDK 基线为 FIN 5.3.0.2761。客户侧不需要 Node.js 或独立数据库；从源码构建需要 Node.js/npm、匹配的 FIN SDK 与其 Java 环境。

```powershell
npm --prefix finEnergy.pod/ts ci
.\scripts\build.ps1 -Edition HQ
.\scripts\build.ps1 -Edition China -LicenseKeyring <公开验签密钥JSON>
node scripts/check-versions.mjs
.\scripts\acceptance.ps1 -Edition China
```

构建生成 `out/china/finEnergy.pod` 或 `out/hq/finEnergy.pod`。每次构建使用独立目录及静态 FIN SDK。对于单独递增版本的发行包，可传 `-ReleaseVersion`，同次构建的所有版本保持一致。使用 `scripts/test.ps1 -Edition China -SkipBuild` 或 `-Edition HQ -SkipBuild` 验证对应冻结构建。FIN 原生运行验收单独记录。

## 验证与交付

本次合并后 SDK 后端全量通过 124 类、1,026 方法、300,163 验证；前端类型和正式构建通过。中英文桌面／手机、原生授权呈现、分项能流、清洗及冻结导出的浏览器证据与新界面截图，分别注明受控数据和保存的 FIN 响应来源。完整证据、剩余运行验收与包哈希见本次交付记录。

总部版正式发布前，使用真实许可证验证功能有效、缺失、到期、重启、多项目、原生菜单、普通/raw 历史与清洗回调，并按冻结条件核对迁移前后统计一致。Linux、Desigo Optic 及其他 FIN 构建的兼容范围须以目标环境验收为准。

## English overview

FIN Energy reuses FIN's native equipment, designated primary histories, identity and alarms. The operations cockpit and analysis workspace cover trends, reference curves, shares, end uses, energy flow, meter differences, tariffs, intensity and data-quality diagnostics. Queries use current relationships and preserve missing data.

FIN Energy 0.16 introduces the `finEnergy` namespace, J2 branding and native FIN feature gating, with explicit recoverable migration. The HQ edition requires the exact native feature ID `finenergy`. A genuine test grant and the Belgian customer's full environment remain release prerequisites. SDK, controlled browser, package and native runtime evidence are kept distinct. See the English documents above for deployment and operational details.

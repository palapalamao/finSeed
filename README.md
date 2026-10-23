# 能源魔方（EnerCubix）

面向楼宇设施的多维能源分析平台。界面采用顶部导航和空间、计量、组织视角切换；对外品牌统一为能源魔方。从 0.7.0 起，安装包和扩展标识统一为 `enerCubix`；现有 `seed*` Axon 函数、业务标签及记录标识保留兼容。源码目录暂保留 `finSeed.pod/`，构建产物为 `enerCubix.pod`。历史验证文档中的旧名称保留作为来源记录。

`0.6.0` 启用能源魔方 / EnerCubix 品牌和立方体标识，重构顶部导航、分析工作台及移动布局。对象选择与表计详情改为抽屉，分析主题分组展示；保留现有报表、模板和导出能力。

`0.5.0` 新增中英文自动识别、手动语言切换及偏好记忆，统一导航、表单、日期控件、图表和导出语言；语言列表集中注册，支持后续加入法文。后续新增功能与页面必须支持多语言，见 [项目约定](AGENTS.md)。

界面支持中文与英文。右上角语言按钮提供“跟随系统、中文、English”；手动选择会保存在当前浏览器，选择“跟随系统”恢复自动识别。切换会刷新当前页面，保留项目与页面地址；浏览器禁止保存设置时，通过当前页面地址保留选择。自动模式按浏览器首选语言选择（浏览器通常继承操作系统语言）：`zh`、`zh-CN`、`zh-TW`、`zh-HK` 等中文环境使用简体中文，其他语言使用英文。浏览器未提供首选语言时回退到运行环境的默认区域语言，无法识别时默认英文；浏览器单独设置语言时，以浏览器为准。导航、表单、日期控件、图表与报表导出使用同一语言；项目中的设备名称、能源分类名称和用户输入保留原文。修改浏览器语言后刷新页面生效。

语言注册集中在 `finSeed.pod/ts/src/i18n.ts` 的 `languageDefinitions`。后续增加法文时，补齐界面与服务提示的法文词库、注册 Day.js 法文语言包，并在 `App.tsx` 的 `componentLocales` 中增加 Ant Design 法文语言包；按钮列表及自动语言匹配随注册更新。当前未提供法文选项。

`0.4.0` 统一能源对象为 FIN 原生设备。主能耗点、计量上级、能源、用途、组织和计量范围直接存为设备的 `seed` 业务标签；三个视图共用设备 ID，不再维护物理表计副本。设备本身与原始历史保留，“删除表计”改为取消纳入，复制配置需要指定已有目标设备。迁移先预览和备份，核对报告后清理旧物理档案；保留旧 ID 映射、只读分组口径和冲突保护回滚。以下旧版本说明属于升级前行为，接口差异见 [contracts/api.md](contracts/api.md)。

`0.4.0.1` 限制空间目录为开启历史的点位，非空间报告直接读取能源设备配置；日常查询不解码迁移恢复材料，以减少内存占用。

FIN 5.3.0.2761 的单 Pod 能源管理扩展，后端 Fantom、前端 React/TypeScript。扩展名与 Pod 均为 `enerCubix`。当前 `0.7.0` 的日均负荷默认按表计配色，可切换峰谷平配色；支持泄漏分析的总表与分表堆叠对照、周汇总。空间树直接读取 FIN 原生设备树，每次加载或刷新同步名称、层级、设备与点位；计量与组织仍独立配置，页面底部显示版本号。构建版本以 `finSeed.pod/build.fan` 为准。使用 FIN 原生登录身份，写操作限管理员；没有独立账号系统。

本地构建产物为 `out/enerCubix.pod`，源码位于本仓库；本次已安装包的固定路径及哈希记录在 `out/native-space-0.2.6-validation.json`。[三树验收与安装说明](docs/three-tree-validation.md) 记录 0.2.2 的独立 FIN 实机验收及 zeda 部署结果；本次同步验证见 `out/native-space-0.2.6-validation.json`，0.2.5 界面证据见 `out/three-only-0.2.5-validation.json`，旧版本验收见 [docs/validation.md](docs/validation.md)。0.1.1 起支持在 Seed 内配置历史读数类型，不修改原点位和历史。

## 三树与旧配置

空间树以 FIN 当前设备导航为准，包含原有目录和嵌套设备，点位仅显示已开启历史（his）的项；在 FIN 中维护后刷新即可更新，Seed 不复制创建数千条空间记录，也不修改原始 FIN 设备或历史。未纳入分析的点仅供浏览，可在详情点击“纳入分析”；同一个已绑定点显示同一份计量档案。物理表随 FIN 点位自动定位；计量上下级与组织归属保持独立。原点删除或不可见时保留档案并提示缺源。新空间报表使用实时归属，旧模板保留原统计口径。

`0.2.2` 将空间覆盖、计量上下级与组织核算分开：空间和组织分别建立同类父子关系，表计通过 `spaceId`、`meterParentId`、`organizationId` 关联，均保存为项目中的原生 Folio Ref。多个旧对象绑定同一物理点时，以一个计量主档案和 `canonicalId` 兼容引用保留历史配置。移动某个维度只改变该维度的归属；复制表计会清除数据绑定并默认不计入合计。

旧分组仅保留在后台兼容历史报表，页面不再提供旧分析树入口。报表请求不传 `dimension` 或传入 `legacy`，继续使用原来的 `parentId`、总分表与合计规则；已有报表和模板无需强制迁移。新报表只能选择空间、计量和组织；历史模板使用原口径，退出模板或切换报表后恢复空间视图。选择新维度后，按确认的空间、组织和计量关系统计，同源兼容引用与已包含总表的下级表不会重复加入同一范围。覆盖关系或核算归属不完整时，汇总返回空值与质量原因，明细仍保留各表读数和原始来源。

管理员可先预览迁移，再明确接受建筑/楼层和批量上下级建议，或为功能分组选择实际空间。原生楼层名称可能是功能分组，不会直接当作真实楼层；空分组保持未绑定。应用时同时检查配置与来源版本，在一次提交中保存变更和迁移前后快照。回滚要求当前记录仍符合迁移后快照，并检查新增引用，迁移任务和快照持续保留。迁移只调整 Seed 配置，不改写原始 FIN 点位、设备或历史。完整字段、维度操作与迁移接口见 [contracts/api.md](contracts/api.md)。

## 本地构建

计量对象管理采用左树、中央列表、右侧表计详情；手机使用详情抽屉。显示父级路径、直接子级或全部下级，支持三步新增向导、拖动移动、批量分配，以及带外部引用和并发检查的删除预览。空间、上级表和组织独立维护，能源与分项作为属性和筛选条件。

需要 Node.js/npm、Java 11 与已安装的 FIN SDK。首次在 `finSeed.pod/ts` 安装前端依赖：

```powershell
npm --prefix finSeed.pod/ts install
.\scripts\build.ps1
.\scripts\test.ps1 -SkipBuild
.\scripts\acceptance.ps1
```

可传 `-SdkPath 'D:\FIN-SDK'`，或设置 `FINSEED_SDK`；默认读取 `C:\Program Files (x86)\FIN\FIN 5.3.0.2761`。脚本只复制编译所需静态文件到 `.local/sdk`，不复制 `var`、项目库、用户认证或许可文件，不写入源 FIN 安装目录。SDK 源代码版本变化时，使用新的本地工作目录重新建立副本。

`build.ps1` 先构建前端，再用 `finBuild::BuildFinPod` 编译，生成 `out/enerCubix.pod`。`test.ps1` 执行 Pod 测试、前端测试与类型/生产构建。`acceptance.ps1` 核对 Pod 名称、版本、入口索引、菜单/语言/UI 资源，输出 `out/acceptance.json`（SHA-256 和资源清单）。该报告不代表 FIN 运行验收通过。

## 安装与打开

先在有可用测试许可、独立 `var`/项目库与独立监听端口的 FIN 测试实例安装 `out/enerCubix.pod`，按 FIN 标准扩展管理流程启用 `enerCubix`，重新登录后从 FIN 应用菜单打开。仓库提供下述隔离实例更新脚本；生产安装、服务重启与回滚仍须另行安排，脚本不操作生产 FIN 服务。

升级旧项目时，先备份原 `finSeed.pod` 和扩展配置，在 FIN 中停用 `finSeed`，停服后将旧包移出 `lib/fan`，再安装 `enerCubix.pod`、重启并启用 `enerCubix`；禁止同时加载两个包。旧页面书签须更新为下述新地址。已有语言和树宽度偏好保持兼容。

接口使用 `/api/{project}/ext/enerCubix/v1`，页面资源为 `/pod/enerCubix/res/web/seed/index.html`。项目标识保留在页面 hash 参数中；直接打开资源时需使用 `#/profile?project=项目名`。配置写入项目 Folio，历史读取原始 FIN 历史，计算结果只写 finSeed 自有派生点。源点历史不被改写。

已配置 FIN Expert 的环境可用 `scripts/register-fin-expert.ps1` 注册本机隔离验收连接。它经官方 CLI 的隐藏输入读取 `.local/runtime-credentials.json`，不把密码放进命令参数，并校验旧连接保持不变。随后只通过 `fin_live_*` 或 `scripts/audited-fin.ps1` 执行验收；后者调用与 MCP 相同的 FIN Expert `ToolRegistry`，固定目标为 `127.0.0.1:38085 / finseed_acceptance`，输出审计 ID。请求 JSON 的 `operation` 为 `test`、`read` 或 `axon`；其他字段遵循对应 `fin_live_*` 工具参数。发生 `outcome_unknown` 时先用只读操作核对，不重试写入。

## 范围与验证边界

接口与计算约定见 [contracts/api.md](contracts/api.md)，逐项迁移/验收账本见 [docs/feature-parity.md](docs/feature-parity.md)。无数据、缺失历史和权限错误应明确显示，不使用演示数据兜底。编译、离线测试、静态包检查与 FIN 运行验收分别记录，未获实机证据的项目保持待验证。

`scripts/prepare-runtime.ps1` 可准备独立测试目录所需的静态品牌资源；不会启动服务。构建 home 为 `.local/sdk`，运行 home 为静态快照 `.local/runtime-sdk`，项目数据为 `.local/runtime-var`。原生启动参数为 `finStackHost -var <独立绝对目录>`，端口与回环地址使用原生 HTTP 设置记录。启动前仍需通过 FIN 原生 setup 创建新的管理员身份并取得测试实例可用许可。FIN bootstrap 在处理 `-var` 前会读取 home 的 `var/brand/brand.zip` 与 `var/lic`，因此仅更换 `-var` 并不足以隔离原安装。

更新隔离测试实例时，先完成构建，再用 `scripts/restart-runtime.ps1 -ExpectedSha256 <稳定包SHA256>`。脚本核验回环端口、进程 home/var 后只停止隔离进程，将稳定 Pod 复制到运行快照并启动。后续构建不会覆盖运行 home；该脚本不会操作 Windows FIN 服务。

独立运行 FIN 还需要发行版匹配的原生库、静态品牌资源和按授权正常接受的测试许可。项目库与认证数据库保持独立，不复制生产项目或用户，不降低安全配置或绕过许可校验。

## 分层验收

离线测试与 `acceptance.ps1` 只验证代码及包结构。独立 FIN 运行验收要求 `127.0.0.1:38085` 上的 `finseed_acceptance` 项目已初始化、稳定 Pod 已安装并启用，且官方 FIN Expert 已注册管理员连接 `finseed-acceptance-local` 与原生只读连接 `finseed-acceptance-reader`：

```powershell
.\scripts\runtime-acceptance.ps1
```

该脚本经官方审计通路依次执行 `seedAcceptance()`、`seedThreeTreeAcceptance()`、`seedEngineeringAcceptance()`、`seedTransportAcceptance()`、`seedPermissionAcceptance()`，会写入隔离项目的测试配置、历史及任务等数据。它检查计算、三树关系、迁移回滚、原子操作、持久化、原生 HTTP 业务路由与读权限；全部步骤通过后才生成 `out/runtime-acceptance.json`，分步响应保存在 `out/native/`。报告关联运行 Pod 的 SHA-256，不能将旧包结果当作新包验收。

普通浏览器测试使用受控接口数据验证界面交互、导出与错误状态；未设置 `FINSEED_NATIVE=1` 时，原生业务测试会跳过：

```powershell
npm --prefix finSeed.pod/ts run build
npm --prefix finSeed.pod/ts run test:e2e
```

要让真实 Edge 页面使用隔离 FIN 的业务响应，先完成上述运行验收，再在另一终端启动桥。以下路径需指向已配置连接的 FIN Expert 环境：

```powershell
& 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile\.venv\Scripts\python.exe' .\scripts\native-ui-bridge.py --origin http://127.0.0.1:4178
```

桥只监听 `127.0.0.1:4179`，限定测试项目、账号与业务路由，所有 FIN 操作均经官方 `ToolRegistry.live_execute_axon` 审计；桥不直接请求 FIN HTTP，不返回认证头，遇到 `outcome_unknown` 显示失败且不自动重试。审计元数据写入 `out/native-browser-audit.jsonl`。隔离 FIN 重启后需重启桥以更新其认证会话。

```powershell
$env:FINSEED_NATIVE = '1'
try {
    npm --prefix finSeed.pod/ts run test:e2e -- native-fin.spec.ts
} finally {
    Remove-Item Env:FINSEED_NATIVE -ErrorAction SilentlyContinue
}
```

Playwright 自动启动 `127.0.0.1:4178` 的生产构建预览，该端口须空闲；本机需安装 Edge。原生业务用例检查真实报表及导出、配置增删与刷新后的持久化、只读账号的禁用控件与写入拒绝，响应证据保存在测试附件中。页面认证入口由测试拦截，业务请求经审计桥转发，因此这层不能证明原生浏览器 Cookie 登录、CSRF/attest 握手或完整菜单入口已通过；这些须单独记录原生 HTTP 与浏览器证据。上述命令与测试范围也不代表用户手册全部功能或生产环境已验收，逐项状态以功能账本为准。

对比分析默认本月至今对比上月同期，日期包含结束日；自定义区间联动保持等长，按周从各自起点每 7 天对齐。上月天数不足时同时取两期共有天数并提示。整月模式保留各月实际天数，以月份为一组。不同能源与单位分别绘制本期／对比期并排柱，缺测留空；旧模板保留原始区间口径。

同一时段的对象对比统一在对象树勾选，再从已选对象中明确指定基准；差值为对象用量减基准用量，变化率以基准用量为分母。基准不随勾选顺序改变，移除基准需重新选择。模板保存基准，旧模板的额外表计对象合并显示，原始参考点按旧口径保留并提示。

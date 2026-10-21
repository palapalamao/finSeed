# FIN Seed

FIN 5.3.0.2761 的单 Pod 能源管理扩展，后端 Fantom、前端 React/TypeScript。扩展名与 Pod 均为 `finSeed`。当前 `0.2.6` 的空间树直接读取 FIN 原生设备树，每次加载或刷新同步名称、层级、设备与点位；计量与组织仍独立配置，左下角常驻显示版本号。构建版本以 `finSeed.pod/build.fan` 为准。使用 FIN 原生登录身份，写操作限管理员；没有独立账号系统。

本地构建产物为 `out/finSeed.pod`，源码与交付包为 `out/finSeed-0.2.6.zip`。[三树验收与安装说明](docs/three-tree-validation.md) 记录 0.2.2 的独立 FIN 实机验收及 zeda 部署结果；本次同步验证见 `out/native-space-0.2.6-validation.json`，0.2.5 界面证据见 `out/three-only-0.2.5-validation.json`，旧版本验收见 [docs/validation.md](docs/validation.md)。0.1.1 起支持在 Seed 内配置历史读数类型，不修改原点位和历史。

## 三树与旧配置

空间树以 FIN 当前设备导航为准，包含原有目录和嵌套设备，点位仅显示已开启历史（his）的项；在 FIN 中维护后刷新即可更新，Seed 不复制创建数千条空间记录，也不修改原始 FIN 设备或历史。未纳入分析的点仅供浏览，可在详情点击“纳入分析”；同一个已绑定点显示同一份计量档案。物理表随 FIN 点位自动定位；计量上下级与组织归属保持独立。原点删除或不可见时保留档案并提示缺源。新空间报表使用实时归属，旧模板保留原统计口径。

`0.2.2` 将空间覆盖、计量上下级与组织核算分开：空间和组织分别建立同类父子关系，表计通过 `spaceId`、`meterParentId`、`organizationId` 关联，均保存为项目中的原生 Folio Ref。多个旧对象绑定同一物理点时，以一个计量主档案和 `canonicalId` 兼容引用保留历史配置。移动某个维度只改变该维度的归属；复制表计会清除数据绑定并默认不计入合计。

旧分组仅保留在后台兼容历史报表，页面不再提供旧分析树入口。报表请求不传 `dimension` 或传入 `legacy`，继续使用原来的 `parentId`、总分表与合计规则；已有报表和模板无需强制迁移。新报表只能选择空间、计量和组织；历史模板使用原口径，退出模板或切换报表后恢复空间视图。选择新维度后，按确认的空间、组织和计量关系统计，同源兼容引用与已包含总表的下级表不会重复加入同一范围。覆盖关系或核算归属不完整时，汇总返回空值与质量原因，明细仍保留各表读数和原始来源。

管理员可先预览迁移，再明确接受建筑/楼层和批量上下级建议，或为功能分组选择实际空间。原生楼层名称可能是功能分组，不会直接当作真实楼层；空分组保持未绑定。应用时同时检查配置与来源版本，在一次提交中保存变更和迁移前后快照。回滚要求当前记录仍符合迁移后快照，并检查新增引用，迁移任务和快照持续保留。迁移只调整 Seed 配置，不改写原始 FIN 点位、设备或历史。完整字段、维度操作与迁移接口见 [contracts/api.md](contracts/api.md)。

## 本地构建

计量对象管理采用左树、中央列表、右侧表计详情；手机使用详情抽屉。显示父级路径、直接子级或全部下级，支持三步新增向导、拖动移动、批量分配，以及带外部引用和并发检查的删除预览。空间、上级表和组织独立维护，能源与用途作为属性和筛选条件。

需要 Node.js/npm、Java 11 与已安装的 FIN SDK。首次在 `finSeed.pod/ts` 安装前端依赖：

```powershell
npm --prefix finSeed.pod/ts install
.\scripts\build.ps1
.\scripts\test.ps1 -SkipBuild
.\scripts\acceptance.ps1
```

可传 `-SdkPath 'D:\FIN-SDK'`，或设置 `FINSEED_SDK`；默认读取 `C:\Program Files (x86)\FIN\FIN 5.3.0.2761`。脚本只复制编译所需静态文件到 `.local/sdk`，不复制 `var`、项目库、用户认证或许可文件，不写入源 FIN 安装目录。SDK 源代码版本变化时，使用新的本地工作目录重新建立副本。

`build.ps1` 先构建前端，再用 `finBuild::BuildFinPod` 编译，生成 `out/finSeed.pod`。`test.ps1` 执行 Pod 测试、前端测试与类型/生产构建。`acceptance.ps1` 核对 Pod 名称、版本、入口索引、菜单/语言/UI 资源，输出 `out/acceptance.json`（SHA-256 和资源清单）。该报告不代表 FIN 运行验收通过。

## 安装与打开

先在有可用测试许可、独立 `var`/项目库与独立监听端口的 FIN 测试实例安装 `out/finSeed.pod`，按 FIN 标准扩展管理流程启用 `finSeed`，重新登录后从 FIN 应用菜单打开。仓库提供下述隔离实例更新脚本；生产安装、服务重启与回滚仍须另行安排，脚本不操作生产 FIN 服务。

接口使用 `/api/{project}/ext/finSeed/v1`，页面资源为 `/pod/finSeed/res/web/seed/index.html`。项目标识保留在页面 hash 参数中；直接打开资源时需使用 `#/profile?project=项目名`。配置写入项目 Folio，历史读取原始 FIN 历史，计算结果只写 finSeed 自有派生点。源点历史不被改写。

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

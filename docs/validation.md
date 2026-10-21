# FIN Seed 0.1.0 验证记录

验证日期：2026-10-21。范围为已批准计划的实现和下列自动化输入；功能账本见 [feature-parity.md](feature-parity.md)，手册及源码固定版本见 [baseline.md](baseline.md)。

最终包：`out/finSeed.pod`，SHA-256 **946862a2ec09fb17860e744d4d16c4c011ae3b7ad650cb9e98431f01cf202a54**。隔离运行目录安装包与交付包一致；原生全套验收在此最终包上通过。

## 环境与隔离

- 发行版 SDK 和运行 Pod 来源：FIN 5.3.0.2761；已读取运行目录 `finStackHost.pod` 元数据确认版本 `5.3.0.2761`。底层 `skyarcd` 模块版本是 `3.1.5`，不将它混同为 FIN 发行版号。
- 构建目录 `.local/sdk`；运行快照 `.local/runtime-sdk`；数据目录 `.local/runtime-var`；仅监听 `127.0.0.1:38085`，项目 `finseed_acceptance`。
- 新建原生测试管理员与 op 只读账号，未复制生产项目或用户认证库。生产 FIN5 服务保持运行，未部署本扩展到生产。
- FIN 操作经注册 FIN Expert 通道审计，测试桥不返回密码、Cookie、bearer 或认证头。测试专用函数拒绝在其他业务项目运行。

## 已执行的证据

| 编号 | 内容 | 结果与证据 |
|---|---|---|
| B1–B5 | 完整目标 SDK Pod 测试 | 5 类、60 方法、357 断言通过；`out/backend-tests.log`。引擎35方法/283断言，其他为配置、历史适配、任务及HTTP请求体 |
| UI | 前端单测、类型与生产构建 | 27 单测通过；`finSeed.pod/ts/validation-logs/2026-10-21-unit.log` 及 `2026-10-21-build.log` |
| UI | 受控接口的真实 Edge 场景 | 39 个场景分批通过。最终37例见 `2026-10-21-final-fixture-e2e.log`；另外2例为未改动导出逻辑的四格式及1001行长表，见 `2026-10-21-fixture-e2e.log`。未把两批称为一次全跑 |
| N1 | 原生 Folio、历史和计算 | `out/runtime-acceptance.json` 的 calculation-persistence-history 部分，包含14类报告、243条检查；按独立期望值核对数值、质量和来源。审计 `0442589c-cd73-42db-974a-9e057566ee13` |
| N2 | 实际 FIN HTTP 路由 | 同报告 real-http-business-routes 部分：入口302、index/module200和JS MIME、原生attest、点目录、配置移动/属性/绑解绑、mod冲突、模板、报警确认、独立任务开关。审计 `74c78df6-dee3-46fd-ad54-34ef7889d7fd` |
| N3 | 原生身份与只读权限 | 同报告 native-readonly-permissions 部分：op可读取，配置/任务/报警写入403；匿名请求303进入FIN原生登录挑战。审计 `e5b32c14-8d16-4d45-a360-ce16068e8b81` |
| N4 | 重启后 Folio 持久化 | `out/restart-persistence.json`：同一Ref、seedConfig及mod逐值一致，审计 `128e3e4a-275d-4367-9992-ef47a29434c3` → `34decbd5-5b81-4acd-9f78-26b912a01964` |
| N5 | 真实 FIN 业务响应的 Edge 流程 | 3例通过，49.2秒；`2026-10-21-native-e2e-print-fixed.log`。240kWh及原源点Excel、打印PDF、唯一321m²配置创建/刷新/删除、真实op写入403；每例实际响应/审计ID/截图在`validation-logs/native-results/` |

典型独立期望值：总表240kWh、费用288元、CO2 136.8kg、面积归一0.24kWh/m²、分表含子组216kWh、泄漏24kWh/10%、COP0.5、虚表216kWh、分项144kWh、标准煤29.496kgce。峰/谷/平区间总量20/20/200kWh，日均24小时点每小时10kWh；工作时段100、非工作时段140kWh；周一工作日240/0；同区间比较差值0。

五类费率使用单独的原生验收源，从2026-01-01计费周期起点开始，每小时6kWh、共144kWh；固定、绝对时段、周时段、月阶梯、年阶梯期望费用依次288、216、264、188、188元。没有假设10月源在1月至10月间用量为零。

派生结果真实回读24个FIN ENDSTAMP点，每点10kWh；再次重算后时间、数值、单位及点数一致，原始总表边界仍为1000。组分类阈值与表级阈值分别产生24条小时事件，原生身份确认通过。fixture源仅在独立项目且带专有所有权标记时写入；这与产品从不改写业务源历史的约束分开。新建的复制树验收记录在检查后按子到父顺序清理。

额外原生COV诊断确认：有前后样本、请求区间内无样本时，FIN实际Folio3仍返回边界样本。只读审计 `2f930a8b-f72b-4ab5-94bb-bb109a3ba0b3`；未将临时离线HxFolio的差异当作FIN运行故障。

## 文件与图表

Excel、Word、PDF、PNG均检查了真实非空格式；分类过滤、明细、图表和导出使用同一不可变结果快照。1001行报告核验每行PDF分页覆盖、XLSX最后一行及PNG尺寸。PNG明确为图表与摘要；完整明细使用Excel/Word/PDF。导出证据保留在 `finSeed.pod/ts/validation-logs/test-results/`。

打印验证触发`window.print`、检查打印媒体几何与导航隐藏，并生成80,802字节单页横向PDF；已渲染检查中文、240kWh、曲线、明细及来源，未见裁切。预览为`out/native-print-preview.png`。打印修复仅增加`width:auto!important`，对已验证CSS逐字节比较无其他差异。最终正常前端构建见`2026-10-21-print-fix-build.log`，未采用增量资产替代构建。

N5加载最终UI构建（`index-BLxBmEqR.js` / `index-D8yV1CH7.css`），业务API由前一隔离安装包提供；产品后端代码未再修改。随后最终打包、重启及N1–N4重新通过，避免把旧包原生验收冒充最终包。测试机曾耗尽提交内存；最终Fantom构建使用256MiB有界堆，隔离运行使用384MiB有界堆，生产服务参数未修改。这是本次测试条件，不是现场容量建议。

## 验证限制

- 原生HTTP入口、attest和接口权限已测；真实业务浏览器通过审计桥验证，没有覆盖FIN原生Cookie登录、菜单实际点击或会话失效的整个浏览器链路。登录HTML/401/403界面状态另有受控浏览器测试。账户及登录实现沿用FIN。
- 未连接生产采集设备，也未验证现场采集器的历史同步；FIN原始采集与本扩展派生重算是独立能力。未执行生产部署、数据迁移或历史改写。
- 未启动旧版SEED在线环境逐条对拍；业务基线来自固定用户手册、源码规则和独立预期值。这些自动化通过不等于所有现场数据与边角行为获得1:1认证。

上述边界保留为未完成的正式现场验收事项，不以静态审查、编译成功或受控接口测试替代。

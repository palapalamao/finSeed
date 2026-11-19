# 能源魔方系统要求 / EnerCubix system requirements

适用于能源魔方 v0.15.2，更新于 2026-11-14。  
Applies to EnerCubix v0.15.2. Updated November 14, 2026.

## 中文

### FIN 版本与兼容性

| FIN Framework 版本 | 当前 Pod |
| --- | --- |
| **5.3.0.2761** | 最低支持版本，已在 Windows 11 64 位环境部署并验收。请核对完整构建号。 |
| 低于 5.3.0.2761，包括 5.2.x 和 5.1.x | 当前安装包的 FIN 依赖要求为 5.3.0.2761。部署前需升级 FIN。 |
| 5.3.1 | 需要使用 5.3.1 SDK 重新编译并完成兼容性验收后才能交付。 |
| 其他 FIN 版本、Linux、嵌入式设备及 OEM 发行版 | 需在目标发行版和设备上完成能源魔方验收后确认支持。 |

当前 Pod 的 FIN 原生核心和报警依赖为 `finStackCoreExt`、`alarmExt`，最低版本均为 `5.3.0.2761`。FIN 5.3.1 对含 Fantom 代码的自定义 Pod 有重新编译要求。[Pod 构建清单](../enerCubix.pod/build.fan) · [FIN 5.3.0 发布说明](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/34227978248/FIN%2B5.3.0) · [FIN 版本迁移指南](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/33872281614/Migrations)

### 部署条件

| 项目 | 要求 |
| --- | --- |
| FIN 服务器 | 使用符合目标 FIN 版本要求的运行环境。J2 的服务器配置参考为 2 GHz 或以上的 x86-64 CPU、4 GB 内存和 32 GB SSD，推荐内存 8–16 GB 或以上。实际配置按 FIN 总点位数、历史留存、查询范围和并发量确定。 |
| Java | 复用 FIN 的 64 位 Java 运行环境，当前实机使用 Java 21.0.12。新服务器可按 J2 当前系统要求优先采用 64 位 OpenJDK 21，存量服务器以所用 FIN 发行版的兼容要求为准。 |
| 浏览器 | 使用当前受维护的 Microsoft Edge 或 Google Chrome。能源魔方的浏览器回归使用 Edge，尚未确定最低浏览器版本号。 |
| FIN 项目与数据 | 存量改造和新项目均可部署。具备安装权限的人员安装 Pod，并在目标项目启用扩展。分析时，每块纳管表需明确绑定已启用历史的主能耗点，且单位与能源类型匹配。历史数据由 FIN 采集和保存。 |
| 授权 | 每个 FIN 项目有 10 块表的免费额度。需要超额运行时，FIN 超级用户导入有效授权。授权可离线校验。 |
| 独立签发后台 | 仅签发方部署，使用 Node.js 22.22、SQLite 和 HTTPS。客户侧 Pod 复用 FIN 的运行环境和项目数据，无需另装 Node.js、数据库或签发服务。 |

[FIN 官方系统要求](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/770708327) · [FIN 官方 Windows 安装指南](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/770709455/Windows%2BInstallation) · [浏览器验收配置](../enerCubix.pod/ts/playwright.config.ts) · [授权与签发说明](enercubix-licensing.md)

## English

### FIN versions and compatibility

| FIN Framework version | Current Pod |
| --- | --- |
| **5.3.0.2761** | Minimum supported build, deployed and verified on 64-bit Windows 11. Check the full build number. |
| Earlier than 5.3.0.2761, including 5.2.x and 5.1.x | The current package requires FIN dependencies at 5.3.0.2761. Upgrade FIN before deployment. |
| 5.3.1 | Requires recompilation against the FIN 5.3.1 SDK and compatibility testing before delivery. |
| Other FIN versions, Linux, embedded devices, and OEM distributions | EnerCubix support is subject to verification on the target distribution and hardware. |

The Pod requires FIN's `finStackCoreExt` and `alarmExt` modules, both at version `5.3.0.2761` or newer. FIN 5.3.1 requires recompilation of custom Pods that contain Fantom code. [Pod build manifest](../enerCubix.pod/build.fan) · [FIN 5.3.0 release notes](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/34227978248/FIN%2B5.3.0) · [FIN migration guide](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/33872281614/Migrations)

### Deployment requirements

| Item | Requirement |
| --- | --- |
| FIN server | Use an environment supported by the target FIN release. J2's server sizing reference calls for a 2 GHz or faster x86-64 CPU, 4 GB of RAM and a 32 GB SSD, with 8–16 GB or more RAM recommended. Size the system for FIN point count, history retention, query range, and concurrent usage. |
| Java | Use the 64-bit Java runtime configured for FIN. The verified installation runs Java 21.0.12. For new servers, prefer 64-bit OpenJDK 21 in line with J2's current system guidance. For existing servers, follow the requirements of the installed FIN release. |
| Browser | Use a maintained version of Microsoft Edge or Google Chrome. EnerCubix browser regression tests run on Edge. A minimum browser version has yet to be established. |
| FIN project and data | Deploy on new or existing projects. A user with installation rights installs the Pod and enables the extension in the target project. For analysis, each enrolled meter needs an explicitly assigned primary energy point with history enabled and a unit compatible with the energy type. FIN collects and stores the history. |
| License | Each FIN project has a free allowance of 10 meters. A FIN superuser imports a valid license when the project needs to operate above that allowance. Verification works offline. |
| Standalone license issuer | The issuer operates its own service with Node.js 22.22, SQLite, and HTTPS. The customer Pod uses the FIN runtime and project data and requires no separate Node.js installation, database, or issuer service. |

[FIN system requirements](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/770708327) · [FIN Windows installation guide](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/770709455/Windows%2BInstallation) · [Browser test configuration](../enerCubix.pod/ts/playwright.config.ts) · [EnerCubix licensing](enercubix-licensing.md)

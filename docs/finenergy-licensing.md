# FIN 能源管理 原生授权说明

FIN 能源管理总部版将激活、到期与功能授权交由 FIN 原生授权系统管理。本说明适用于 FIN 5.3.0.2761 开发基线。0.16.12 总部候选版使用总部确认的功能标识 `finenergy`。正式交付前须使用包含该功能的 FIN 测试许可证完成运行验收。

## 中文

### 授权流程

1. FIN 管理员在原生 **Host → Licenses → Host Info** 核对机器码及实例信息，向 J2 授权团队申请能源功能。
2. 总部在原生 Licensing Server 中配置产品和对应功能，并把功能加入客户的 FIN 许可证。Pod 不负责签发 FIN 许可证。
3. 管理员使用 FIN 原生授权界面安装或更新许可证，按 FIN 要求停止／重启服务后，再启用 `finEnergy` 扩展。
4. 扩展正常运行后，项目管理员可在 **设置 → 授权管理** 查看功能状态、功能标识与 FIN 机器码。授权更新、删除和恢复均在 FIN 原生界面操作；FIN 能源管理 不提供删除整个 FIN 许可证的按钮。

扩展继承 `fin::FinExt` 并声明 `@FinExtMeta { licFeature="finenergy" }`。许可证中的功能标识须精确匹配，使用全小写且无空格的 `finenergy`。

### 不可访问时如何处理

缺少对应功能时，FIN 会使整个扩展保持停用。此时不能假定 FIN 能源管理 的页面、状态接口、迁移函数或清洗回调可用；请直接从 FIN 原生 Host 授权入口处理。项目内的设置页只有在原生扩展可用时才能作为辅助查看入口。

原生授权变化可能影响 `hisFunc` 的解析和调用。原始历史仍由 FIN 持有，不能把“源历史保留”解释为“停用后所有清洗历史查询均已证明可用”。有效、缺失、到期和重启场景的清洗查询行为，列入真实 FIN 验收。

### 旧版机制与商业规则

旧版独立 RSA 签发文件不为 FIN 原生能源功能授权。原签发源码保存在 [历史归档](../archive/enercubix-license-issuer/ARCHIVE.md)，只用于现有旧版本追溯及回滚，不包含签发密钥。此次源码更新不改变正在运行的旧签发服务或已安装授权。

每项目免费 10 块表和不绑定机器码的培训授权仍属提交总部的商业建议，0.16.0 原生候选不启用这些规则。培训、试用、续期、有效期及实例覆盖范围由总部原生授权方案确定。不得通过应用开关、旧授权文件或自建签发器绕开原生功能检查。

## English

The FIN Energy HQ edition delegates activation, expiry and feature validation to FIN's native licensing system. The development baseline is FIN 5.3.0.2761. The 0.16.12 HQ candidate uses the feature ID confirmed by HQ, `finenergy`. Customer release requires native runtime acceptance with a genuine FIN test license containing that feature.

### Activation workflow

1. The FIN administrator checks the machine identity in **Host → Licenses → Host Info** and requests the energy feature from J2's licensing team.
2. HQ configures the product and feature in its native Licensing Server and adds it to the customer's FIN license. The Pod does not issue FIN licenses.
3. The administrator installs or updates that license through FIN's native interface restarts FIN as required by its licensing workflow, and enables the `finEnergy` extension.
4. Once the extension is running, project administrators can inspect the native feature state and machine identity in **Settings → License management**. License replacement, deletion and recovery remain FIN administration operations.

The extension extends `fin::FinExt` and declares `@FinExtMeta { licFeature="finenergy" }`. The native license must contain the exact lowercase feature ID `finenergy`, with no spaces.

### When the extension is unavailable

FIN keeps an extension inactive if the required feature is absent. Do not assume that the application's license page, status route, migration functions or cleaning callbacks remain callable. Use FIN's native Host licensing interface directly.

FIN retains the original history. This does not prove that every history query using an application `hisFunc` continues to work after native deactivation. Cleaning callback availability must be checked with genuine active, missing, expired and restarted native-license scenarios.

### Legacy files and commercial proposals

Legacy RSA files do not activate the native FIN energy feature. The original issuer source is retained in the [historical archive](../archive/enercubix-license-issuer/ARCHIVE.md) for existing deployments and rollback, without private keys. This source update does not alter a running legacy issuer service or an installed license.

The ten-meter free allowance and host-independent training license remain proposals awaiting HQ agreement. They are not enabled in this native candidate. Trial, training, renewal, expiry and instance coverage follow the native licensing solution agreed with HQ. There is no application bypass.

## 实现与依据 Implementation and evidence

- [Extension facet](../finEnergy.pod/editions/hq/fan/FinEnergyExt.fan) and [native status service](../finEnergy.pod/editions/hq/fan/FinEnergyNativeLicense.fan).
- [Giovanni Casagrande — OEM Custom Pod License Feature Gating](https://finproducts.atlassian.net/wiki/spaces/FINFramework/pages/34410561552/OEM%2BCustom%2BPod%2B-%2BLicense%2BFeature%2BGating).
- SDK compilation and unit tests establish a candidate; they do not establish licensed native runtime acceptance. See the [delivery plan](../specs/fin-energy-hq-20261120/plan.md).

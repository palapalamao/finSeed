# FIN Energy 能源管理授权 / FinEnergy licensing

## 中文

### 申请与激活

1. 项目管理员打开 **设置 → 授权管理**，复制 FIN 机器码或下载 `finenergy-request.json`。机器码可在 FIN 的 **Host → Licenses → Host Info** 核对。申请文件包含产品、格式版本、机器码和申请时间。
2. 签发人员登录[独立签发后台](../license-issuer/README.md)，选择授权类型。机器绑定授权需要上传申请或粘贴机器码。培训授权只需填写有效期。确认时区和时间后签发，并下载已保存的授权文件。续期或换机均签发新文件，后台保留原签发记录。
3. FIN 超级用户在 **授权管理 → 添加授权** 选择并导入文件。有效文件会替换当前授权并即时生效，覆盖同一 FIN 实例的全部项目。页面显示授权类型、有效期和当前项目表计数。到期时间按 FIN 服务器时钟判断。
4. FIN 超级用户可选择 **删除授权** 并确认。删除后，各项目立即恢复各自的免费额度。可从签发后台重新下载原文件，并在有效期内重新导入。

两种授权有效期间均无表计、点位或设备数量上限。机器绑定授权还会检查本机机器码。培训授权可在不同机器上导入，适合期限明确的培训环境。两种文件都需使用受信任的签发密钥签名，FIN 可离线校验。

### 免费额度与恢复

未激活、授权失效或到期时，每个 FIN 项目有 10 块表计额度。各能源类型共用额度，实体表、总表和虚拟总表均计入，有效别名合并计数。参考点、传感器与未纳管的原生设备不计入。

已有超过 10 块的项目可查看设置、配置及历史报警。项目的新查询、当前值合计和能耗报警扫描会暂停。导入有效授权，或将纳管表减至 10 块以内即可恢复。FIN 的原生采集与历史访问继续运行。

### 生成可验签的 Pod

签发后台在签发主机读取 RSA 3072 位私钥。将 `export-key` 导出的公钥 JSON 交给 Pod 构建人员，在 Windows 仓库根目录运行：

```powershell
./scripts/build.ps1 -LicenseKeyring C:\release\public-keyring.json
```

构建输出为 `out/finEnergy.pod`。发布前核对 Pod 公钥的 `keyId` 和后台配置一致。测试与正式构建分别使用对应的公钥。省略 `-LicenseKeyring` 会生成只支持免费额度的开发包。实例授权文件存放在 FIN 实例 `var/finEnergy/license.json`，可随实例备份。

## English

### Request and activate

1. A project administrator opens **Settings → License management**, copies the FIN machine code, or downloads `finenergy-request.json`. Compare the code with **Host → Licenses → Host Info** in FIN. The request contains the product, format version, machine code, and request time.
2. An issuer signs in to the [standalone issuance service](../license-issuer/README.md) and selects a license type. For a machine-bound license, upload the request or paste the machine code. For a training license, enter a validity period. Verify the time zone and dates, issue the license, and download the saved file. Renewal and machine replacement create new signed files and preserve the previous records.
3. A FIN superuser selects and imports the file in **License management → Add license**. A valid file replaces the current license and takes effect immediately for all projects on that FIN instance. The page displays its type and validity period alongside the current project's meter count. FIN uses the server clock to determine expiry.
4. A FIN superuser can select **Delete license** and confirm. Each project immediately returns to its free allowance. The issuer can download the original file again for reimport during its validity period.

Both license types allow unlimited meters, points, and equipment during their validity period. A machine-bound license also checks the local machine code. A training license can be imported on different machines for a time-limited training session. Both types require a signature from a trusted issuer and can be verified offline.

### Free allowance and recovery

Each FIN project has a free allowance of 10 meters whenever there is no valid active license. All energy types share the allowance. Physical meters, total meters, and virtual total meters count, with valid aliases counted once. Reference points, sensors, and native equipment outside FinEnergy are excluded.

An existing project above 10 meters can open settings, read its configuration, and access existing alarms. New queries, current-value rollups, and energy alarm scans pause. Import a valid license or reduce the enrolled meter count to 10 or fewer to resume. Native FIN collection and history access continue.

### Build a Pod with signature verification

The issuance service reads the RSA 3072-bit private key on the signing host. Pass the public JSON produced by `export-key` to the Pod builder, and run this command from the repository root on Windows:

```powershell
./scripts/build.ps1 -LicenseKeyring C:\release\public-keyring.json
```

The build writes `out/finEnergy.pod`. Check that the Pod's public `keyId` matches the issuer configuration. Build test and production packages with their respective public keys. Omitting `-LicenseKeyring` produces a development package with the free allowance only. The instance license lives in `var/finEnergy/license.json` and can be included in the FIN instance backup.

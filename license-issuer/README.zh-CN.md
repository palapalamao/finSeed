# FIN Energy 能源管理授权签发后台

[English](README.md)

签发后台独立运行于 Node.js 22.22，使用 SQLite 保存签发账号、记录及原始授权文件。客户可在离线 FIN 环境中导入FIN Energy 能源管理授权。

## 配置签发后台

将 SQLite 数据库、签发私钥和 TLS 私钥存放在仓库之外的受保护目录。Windows 部署时，先为运行后台的账号配置该目录的 NTFS 权限。测试后台使用单独的目录、签发密钥和密钥编号。

运行管理命令和启动服务前，设置以下环境变量。

| 变量 | 值 |
|---|---|
| `ISSUER_DB_PATH` | SQLite 数据库绝对路径 |
| `ISSUER_PRIVATE_KEY_FILE` | RSA 3072 位签发私钥的绝对路径，采用 PKCS#8 PEM 格式 |
| `ISSUER_KEY_ID` | 写入授权文件的签发密钥编号 |
| `ISSUER_TLS_CERT_FILE` | PEM 格式 HTTPS 证书链绝对路径 |
| `ISSUER_TLS_KEY_FILE` | PEM 格式 HTTPS 私钥绝对路径 |
| `ISSUER_ORIGIN` | 浏览器访问的 HTTPS 源地址，去掉路径和末尾斜杠 |
| `ISSUER_BIND` | 监听地址，默认为 `127.0.0.1` |
| `ISSUER_PORT` | 监听端口，默认为源地址端口或 443 |

首次运行时生成签发私钥。目标文件已存在时，命令会拒绝覆盖。用 PowerShell 7 的遮蔽输入创建签发账号。

```powershell
node license-issuer/cli.mjs create-key
Read-Host '签发账号密码' -MaskInput | node license-issuer/cli.mjs account operator
node license-issuer/cli.mjs export-key
node license-issuer/server.mjs
```

账号使用小写字母、数字、点、下划线和连字符。密码长度为 12 至 256 个字符。再次为相同账号执行命令会修改密码并结束旧会话。公钥导出命令输出 JSON，提供给 Pod 构建用于验证该签发方的授权。服务通过配置的证书提供 HTTPS。每个数据库运行一个签发后台实例。

## 签发与续期

1. 登录后选择授权类型。选择**机器绑定**时，粘贴 FIN 机器码或导入FIN Energy 能源管理导出的申请文件。选择**培训授权**时直接设置有效期，授权在有效期内可在任意 FIN 主机使用。
2. 按页面显示的浏览器时区填写生效及到期时间。在签发确认页核对转换后的 UTC 时间。到期时间是授权失效的起点。
3. 点击**生成授权**。服务端记录签发人和签发时间，保存原始签名文件后提供下载。
4. 将 `.finenergy-license` 文件交给客户的 FIN 超级用户，在有效期内从FIN Energy 能源管理**设置 → 授权管理**导入。
5. 通过**签发记录**重新下载原文件或续期。换机时选择**续期或换机**，输入新机器码。新记录会关联原授权编号。

通过签发方受保护的存储备份数据库和私钥。复制 SQLite 数据库前停止签发后台，以保留完整事务。

## 文件格式与验证

申请文件包含 `version`（1）、`product`（`finEnergy`）、`hostId` 和 `requestedAt`。授权文件包含 `keyId`、`payload` 和 `signature`。数据和签名采用标准 Base64。签发端使用 RSA PKCS#1 v1.5 与 SHA-256 对原始 UTF-8 JSON 字节签名。签名内容包括 `version`、`product`、`type`、`licenseId`、`issuedAt`、`notBefore` 和 `expiresAt`。`host` 类型还包含 `hostId`。`training` 类型只按有效期使用，授权内容不含机器码。签名时间字段使用 UTC ISO 8601。

导出的公钥表按密钥编号索引，公钥采用 DER SubjectPublicKeyInfo 格式并以 Base64 编码。

```powershell
node --test license-issuer/issuer.test.mjs
```

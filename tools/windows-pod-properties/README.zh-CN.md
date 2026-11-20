# Windows FIN Energy Pod 文件属性

[English](README.md)

该原生 x64 属性处理器让 FIN Energy Pod 在资源管理器 **属性 → 详细信息** 中显示产品名称、产品版本、发行版和授权方式。也可通过 Windows 属性存储接口读取。系统字段名称随 Windows 语言显示，自定义字段和值采用中英并列。

仅识别 ZIP 根目录 `meta.props` 的 `pod.name=finEnergy`。`pod.version` 须为三或四段数字，`finEnergy.edition` 须为 `china` 或 `hq`。可选的 `finEnergy.licenseMode` 须分别为 `selfManaged` 或 `finNative`。缺少发行版信息的旧包不返回这些产品字段。文件名不参与识别。

## 构建

需要 x64 Windows、Rust MSVC、Visual Studio C++ Build Tools 和 Windows SDK 导入库。依赖版本固定在 `Cargo.lock`。在本目录运行：

```powershell
./build.ps1
```

SDK 库未安装到标准目录时，传入 `-SdkLibraries <包含um/x64和ucrt/x64的目录>`。本次构建从 Microsoft 官方 NuGet 的 `Microsoft.Windows.SDK.CPP.x64` 包 `10.0.26100.9457` 提取导入库到被忽略的 `.local/sdk/c`，归档 SHA256 为 `52bd17c63d3b6d268f385c358f34d0eb595b9c1deb3273855abd2ec5c095d132`。下载地址及英文说明见 README.md。没有修改系统 SDK。构建使用静态 MSVC 运行库，产物、脚本、schema 和哈希输出到 `dist/`。

## 安装前检查

```powershell
./dist/inspect.exe --direct <dist内DLL的绝对路径> <Pod绝对路径>
```

程序直接调用 DLL 的真实 COM `IClassFactory`、`IInitializeWithStream`、`IPropertyStore` 和 `IPropertyStoreCapabilities`，打印属性并检查写操作被拒绝。两种发行包均须检查。此检查不改注册表，其结果不能代替资源管理器实际显示验收。

## 安装与验收

发布负责人审阅脚本后，在 **64 位管理员 PowerShell** 中运行。安装和卸载均支持 `-WhatIf`：

```powershell
./dist/install.ps1 -WhatIf
./dist/install.ps1
./dist/inspect.exe --registered <Pod绝对路径>
```

分别打开中国版和总部版的 **属性 → 详细信息**，检查产品、精确版本、发行版和授权方式。安装后重新打开属性窗口。再确认其他 Pod 仍使用此前的默认应用打开。

安装会注册原生 DLL、自定义属性 schema 和 `.pod` 的补充 `FullDetails` 列表。发现现有属性处理器、相同 CLSID、现有自定义 schema 或既有安装记录时会停止。既有补充 Details 列表会保留并追加，原值和文件哈希保存到受保护的安装记录。文件位于 `%ProgramFiles%/FIN Energy Pod Properties`，记录位于 `%ProgramData%/FIN Energy Pod Properties`。不会修改 `.pod` 的默认打开应用。DLL 采用隔离流初始化，线程模型为 `Both`。

## 卸载

```powershell
./dist/uninstall.ps1 -WhatIf
./dist/uninstall.ps1
```

只有当前注册值仍等于本次安装值时才恢复原值，保留后续其他软件的更改。卸载只删除记录中名称和哈希均匹配的本工具文件。如果资源管理器占用 DLL，请关闭窗口或注销登录，然后从原 `dist` 目录重新运行卸载。工具不会自动结束资源管理器。

## 读取边界

只读取 ZIP 尾部、中央目录和精确的 `meta.props` 成员。归档最大 1 GiB，中央目录最大 4 MiB、最多 8,192 项，压缩和解压后的 metadata 均最大 64 KiB。成员名称最大 1,024 字节，附加区和注释均最大 4,096 字节。拒绝 ZIP64、分卷和加密 metadata，校验 CRC 和长度，限制解压输出。不会把成员解压到磁盘，也不会执行 Pod。属性显示的是包声明的构建信息，不代表包签名或授权已被认证。

已自动验证 stored／deflate、两种发行版、可选授权字段、冲突和重复字段、其他产品、CRC 损坏、截断、超大 metadata 和真实 COM 只读行为。注册后的属性存储、资源管理器显示以及安装／卸载恢复，须由发布负责人执行机器级验收，目前待安装后完成。

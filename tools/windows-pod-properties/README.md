# FIN Energy Pod properties for Windows

[简体中文](README.zh-CN.md)

This x64 native Windows property handler adds product name, product version, edition and licensing mode to Explorer **Properties → Details** for FIN Energy Pods. It also works with the Windows property store API. Standard property labels follow Windows' language. The two custom labels and edition/licensing values contain Chinese and English together.

The handler accepts only ZIP files with root `meta.props` containing `pod.name=finEnergy`, a three- or four-component numeric `pod.version`, and `finEnergy.edition=china` or `hq`. The optional `finEnergy.licenseMode` must match the edition (`selfManaged` or `finNative`). Older Pods without edition metadata provide no product properties. File names do not determine the edition.

## Build

Use x64 Windows, Rust MSVC, Visual Studio C++ Build Tools, and Windows SDK import libraries. All dependencies are pinned in `Cargo.lock`. Run from this folder:

```powershell
./build.ps1
```

For an unpacked Microsoft SDK library layout, pass `-SdkLibraries <folder>` containing `um/x64` and `ucrt/x64`. This task's local build used Microsoft's `Microsoft.Windows.SDK.CPP.x64` NuGet package `10.0.26100.9457`, archive SHA256 `52bd17c63d3b6d268f385c358f34d0eb595b9c1deb3273855abd2ec5c095d132`, extracting only import libraries into the ignored `.local/sdk/c` folder. The source URL is `https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.cpp.x64/10.0.26100.9457/microsoft.windows.sdk.cpp.x64.10.0.26100.9457.nupkg`. Nothing is added to the global SDK installation. The build links the MSVC runtime statically and writes the DLL, verification utility, schema, scripts and hashes to `dist/`.

## Verify before installation

```powershell
./dist/inspect.exe --direct <absolute-path-to-dist/fin_energy_properties.dll> <absolute-Pod-path>
```

This loads the trusted handler DLL and uses its actual COM `IClassFactory`, `IInitializeWithStream`, `IPropertyStore` and `IPropertyStoreCapabilities` interfaces. It prints the properties and confirms write attempts are denied. Run against both release editions. A failed parse returns an error. This direct test leaves registration untouched. It does not establish that Explorer's registered Details tab has rendered correctly.

## Install and verify Explorer

The release owner reviews the scripts and runs the following from an administrator **64-bit PowerShell** window. The install and uninstall scripts support `-WhatIf`.

```powershell
./dist/install.ps1 -WhatIf
./dist/install.ps1
./dist/inspect.exe --registered <absolute-Pod-path>
```

Open the file's **Properties → Details** and inspect both china and hq packages. Close and reopen the window after registration. Confirm product name, exact version, edition and licensing values. Check an unrelated `.pod` still opens with its previous application. Changing `.pod`'s default application is outside the installer.

The installer registers the native DLL, custom `.propdesc` schema, and `.pod`'s supplemental `FullDetails` list. It fails before registration if an existing property handler, handler CLSID, schema or installation state exists. It appends to an existing supplemental Details list and records every prior value and file hash. Files are installed under `%ProgramFiles%/FIN Energy Pod Properties`, with protected machine installation state under `%ProgramData%/FIN Energy Pod Properties`. The DLL uses the default isolated stream initialization model and registers `ThreadingModel=Both`.

## Uninstall

```powershell
./dist/uninstall.ps1 -WhatIf
./dist/uninstall.ps1
```

Uninstallation restores a registry value only when its current value still equals this installation's value. Later changes and unrelated association values are preserved. It unregisters the owned schema and removes only files with their recorded names and hashes. If Explorer is holding the DLL open, close Explorer windows or sign out, then rerun the uninstall script from the original `dist` folder. The tool never terminates Explorer automatically.

## Read limits and verification scope

Only the end record, central directory and exact `meta.props` member are read. Limits are 1 GiB archive size, 4 MiB central directory, 8,192 entries, 64 KiB compressed/uncompressed metadata, 1,024-byte member names and 4,096-byte extra/comment fields. ZIP64, multi-volume and encrypted metadata are rejected. CRC and lengths are checked. Deflate output is bounded. No archive entry is extracted to disk, no Pod is executed, and metadata is read only. The handler shows declared build metadata, so it does not authenticate a package signature or certify licensing.

Automated verification covers stored/deflated metadata, both editions, optional licensing field, mismatched and duplicate fields, other products, bad CRC, truncation, oversized metadata and direct COM read-only behavior. Registered property-store behavior, Explorer rendering and install/uninstall restoration require the release owner's machine-level acceptance. Those checks are pending until authorized installation.

The implementation follows Microsoft's [stream initialization](https://learn.microsoft.com/en-us/windows/win32/properties/building-property-handlers-property-handlers), [property handler registration](https://learn.microsoft.com/en-us/windows/win32/properties/prophand-reg-dist), [read-only handler guidance](https://learn.microsoft.com/en-us/windows/win32/properties/prophand-bestprac-faq) and [custom property schema](https://learn.microsoft.com/en-us/windows/win32/properties/building-property-handlers-property-schemas).

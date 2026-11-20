param([string]$SdkLibraries)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Install Visual Studio C++ Build Tools for x64.' }
$vc = Get-ChildItem -LiteralPath (Join-Path $vs 'VC\Tools\MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1
$sdk = $SdkLibraries
if (!$sdk) {
    $nativeLib = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Lib'
    $version = Get-ChildItem -LiteralPath $nativeLib -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($version) { $sdk = $version.FullName }
}
if (!$sdk) { throw 'Provide Windows SDK import libraries via -SdkLibraries. See README.' }
$sdk = (Resolve-Path -LiteralPath $sdk).Path
$previousPath = $env:PATH
$previousLib = $env:LIB
try {
    $env:PATH = (Join-Path $vc.FullName 'bin\Hostx64\x64') + ';' + $env:PATH
    $env:LIB = (Join-Path $sdk 'um\x64') + ';' + (Join-Path $sdk 'ucrt\x64') + ';' + (Join-Path $vc.FullName 'lib\x64')
    Push-Location $root
    try {
        cargo test --locked --jobs 1
        if ($LASTEXITCODE) { throw 'Native tests failed.' }
        cargo build --release --locked --jobs 1
        if ($LASTEXITCODE) { throw 'Native build failed.' }
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist') | Out-Null
        foreach ($file in @('fin_energy_properties.dll','inspect.exe')) {
            Copy-Item -LiteralPath (Join-Path $root "target\release\$file") -Destination (Join-Path $root "dist\$file") -Force
        }
        foreach ($file in @('FinEnergy.propdesc','Registration.ps1','install.ps1','uninstall.ps1','README.md','README.zh-CN.md')) {
            Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $root "dist\$file") -Force
        }
        Get-ChildItem -LiteralPath (Join-Path $root 'dist') -File | Where-Object Name -NE 'sha256.json' | ForEach-Object {
            [ordered]@{ name=$_.Name; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'dist\sha256.json') -Encoding UTF8
    } finally { Pop-Location }
} finally { $env:PATH=$previousPath; $env:LIB=$previousLib }

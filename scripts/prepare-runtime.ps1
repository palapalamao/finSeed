param([string]$SdkPath)
. "$PSScriptRoot\sdk.ps1"
$enerCubixRoot = Get-EnerCubixRoot
if (-not $SdkPath) { $SdkPath = $env:ENERCUBIX_SDK }
if (-not $SdkPath) { $SdkPath = 'C:\Program Files (x86)\FIN\FIN 5.3.0.2761' }
$enerCubixSource = (Resolve-Path -LiteralPath $SdkPath).Path
$enerCubixSdk = Get-EnerCubixSdk -SdkPath $SdkPath
$enerCubixRuntimeSdk = Get-EnerCubixSdk -SdkPath $enerCubixSdk -DestinationPath (Join-Path $enerCubixRoot '.local\runtime-sdk')
$enerCubixVar = Join-Path $enerCubixRoot '.local\runtime-var'
$enerCubixBrand = Join-Path $enerCubixSource 'var\brand\brand.zip'
if (-not (Test-Path -LiteralPath $enerCubixBrand)) { throw 'Source SDK has no static var\brand\brand.zip.' }
# Native FIN bootstrap reads branding and licenses relative to home before parsing -var.
# Copy branding only. Never copy lic, db, proj, auth, config, certs or keys.
foreach ($enerCubixDir in @((Join-Path $enerCubixSdk 'var\brand'), (Join-Path $enerCubixSdk 'var\lic'), (Join-Path $enerCubixRuntimeSdk 'var\brand'), (Join-Path $enerCubixRuntimeSdk 'var\lic'), (Join-Path $enerCubixVar 'brand'))) {
    New-Item -ItemType Directory -Force -Path $enerCubixDir | Out-Null
}
Copy-Item -LiteralPath $enerCubixBrand -Destination (Join-Path $enerCubixSdk 'var\brand\brand.zip') -Force
Copy-Item -LiteralPath $enerCubixBrand -Destination (Join-Path $enerCubixRuntimeSdk 'var\brand\brand.zip') -Force
Copy-Item -LiteralPath $enerCubixBrand -Destination (Join-Path $enerCubixVar 'brand\brand.zip') -Force
# Only licenses already authorized and copied to the local build SDK may be reused.
Get-ChildItem -LiteralPath (Join-Path $enerCubixSdk 'var\lic') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $enerCubixRuntimeSdk "var\lic\$($_.Name)") -Force
}
$enerCubixLauncher = @'
$ErrorActionPreference = 'Stop'
$env:FAN_HOME = Join-Path $PSScriptRoot 'runtime-sdk'
$enerCubixVar = Join-Path $PSScriptRoot 'runtime-var'
Push-Location $env:FAN_HOME
try { & '.\bin\fan.bat' finStackHost -var $enerCubixVar }
finally { Pop-Location }
'@
[IO.File]::WriteAllText((Join-Path $enerCubixRoot '.local\run-native.ps1'), $enerCubixLauncher, [Text.UTF8Encoding]::new($false))
Write-Host "Static runtime prerequisites prepared. Isolated home: $enerCubixRuntimeSdk; isolated var: $enerCubixVar"
Write-Host 'No FIN server has been started. Configure a new native admin identity and obtain an authorized test license before runtime acceptance.'
Write-Host 'Native launch: finStackHost -var <absolute-var-directory>; HTTP addr/port use native host settings.'

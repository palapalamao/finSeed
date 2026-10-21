param([string]$SdkPath)
. "$PSScriptRoot\sdk.ps1"
$seedRoot = Get-SeedRoot
if (-not $SdkPath) { $SdkPath = $env:FINSEED_SDK }
if (-not $SdkPath) { $SdkPath = 'C:\Program Files (x86)\FIN\FIN 5.3.0.2761' }
$seedSource = (Resolve-Path -LiteralPath $SdkPath).Path
$seedSdk = Get-SeedSdk -SdkPath $SdkPath
$seedRuntimeSdk = Get-SeedSdk -SdkPath $seedSdk -DestinationPath (Join-Path $seedRoot '.local\runtime-sdk')
$seedVar = Join-Path $seedRoot '.local\runtime-var'
$seedBrand = Join-Path $seedSource 'var\brand\brand.zip'
if (-not (Test-Path -LiteralPath $seedBrand)) { throw 'Source SDK has no static var\brand\brand.zip.' }
# Native FIN bootstrap reads branding and licenses relative to home before parsing -var.
# Copy branding only. Never copy lic, db, proj, auth, config, certs or keys.
foreach ($seedDir in @((Join-Path $seedSdk 'var\brand'), (Join-Path $seedSdk 'var\lic'), (Join-Path $seedRuntimeSdk 'var\brand'), (Join-Path $seedRuntimeSdk 'var\lic'), (Join-Path $seedVar 'brand'))) {
    New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
}
Copy-Item -LiteralPath $seedBrand -Destination (Join-Path $seedSdk 'var\brand\brand.zip') -Force
Copy-Item -LiteralPath $seedBrand -Destination (Join-Path $seedRuntimeSdk 'var\brand\brand.zip') -Force
Copy-Item -LiteralPath $seedBrand -Destination (Join-Path $seedVar 'brand\brand.zip') -Force
# Only licenses already authorized and copied to the local build SDK may be reused.
Get-ChildItem -LiteralPath (Join-Path $seedSdk 'var\lic') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $seedRuntimeSdk "var\lic\$($_.Name)") -Force
}
$seedLauncher = @'
$ErrorActionPreference = 'Stop'
$env:FAN_HOME = Join-Path $PSScriptRoot 'runtime-sdk'
$seedVar = Join-Path $PSScriptRoot 'runtime-var'
Push-Location $env:FAN_HOME
try { & '.\bin\fan.bat' finStackHost -var $seedVar }
finally { Pop-Location }
'@
[IO.File]::WriteAllText((Join-Path $seedRoot '.local\run-native.ps1'), $seedLauncher, [Text.UTF8Encoding]::new($false))
Write-Host "Static runtime prerequisites prepared. Isolated home: $seedRuntimeSdk; isolated var: $seedVar"
Write-Host 'No FIN server has been started. Configure a new native admin identity and obtain an authorized test license before runtime acceptance.'
Write-Host 'Native launch: finStackHost -var <absolute-var-directory>; HTTP addr/port use native host settings.'

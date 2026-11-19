param([string]$SdkPath)
. "$PSScriptRoot\sdk.ps1"
$finEnergyRoot = Get-FinEnergyRoot
if (-not $SdkPath) { $SdkPath = $env:FINENERGY_SDK }
if (-not $SdkPath) { $SdkPath = 'C:\Program Files (x86)\FIN\FIN 5.3.0.2761' }
$finEnergySource = (Resolve-Path -LiteralPath $SdkPath).Path
$finEnergySdk = Get-FinEnergySdk -SdkPath $SdkPath
$finEnergyRuntimeSdk = Get-FinEnergySdk -SdkPath $finEnergySdk -DestinationPath (Join-Path $finEnergyRoot '.local\runtime-sdk')
$finEnergyVar = Join-Path $finEnergyRoot '.local\runtime-var'
$finEnergyBrand = Join-Path $finEnergySource 'var\brand\brand.zip'
if (-not (Test-Path -LiteralPath $finEnergyBrand)) { throw 'Source SDK has no static var\brand\brand.zip.' }
# Native FIN bootstrap reads branding and licenses relative to home before parsing -var.
# Copy branding only. Never copy lic, db, proj, auth, config, certs or keys.
foreach ($finEnergyDir in @((Join-Path $finEnergySdk 'var\brand'), (Join-Path $finEnergySdk 'var\lic'), (Join-Path $finEnergyRuntimeSdk 'var\brand'), (Join-Path $finEnergyRuntimeSdk 'var\lic'), (Join-Path $finEnergyVar 'brand'))) {
    New-Item -ItemType Directory -Force -Path $finEnergyDir | Out-Null
}
Copy-Item -LiteralPath $finEnergyBrand -Destination (Join-Path $finEnergySdk 'var\brand\brand.zip') -Force
Copy-Item -LiteralPath $finEnergyBrand -Destination (Join-Path $finEnergyRuntimeSdk 'var\brand\brand.zip') -Force
Copy-Item -LiteralPath $finEnergyBrand -Destination (Join-Path $finEnergyVar 'brand\brand.zip') -Force
# Only licenses already authorized and copied to the local build SDK may be reused.
Get-ChildItem -LiteralPath (Join-Path $finEnergySdk 'var\lic') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $finEnergyRuntimeSdk "var\lic\$($_.Name)") -Force
}
$finEnergyLauncher = @'
$ErrorActionPreference = 'Stop'
$env:FAN_HOME = Join-Path $PSScriptRoot 'runtime-sdk'
$finEnergyVar = Join-Path $PSScriptRoot 'runtime-var'
Push-Location $env:FAN_HOME
try { & '.\bin\fan.bat' finStackHost -var $finEnergyVar }
finally { Pop-Location }
'@
[IO.File]::WriteAllText((Join-Path $finEnergyRoot '.local\run-native.ps1'), $finEnergyLauncher, [Text.UTF8Encoding]::new($false))
Write-Host "Static runtime prerequisites prepared. Isolated home: $finEnergyRuntimeSdk; isolated var: $finEnergyVar"
Write-Host 'No FIN server has been started. Configure a new native admin identity and obtain an authorized test license before runtime acceptance.'
Write-Host 'Native launch: finStackHost -var <absolute-var-directory>; HTTP addr/port use native host settings.'

param([string]$SdkPath, [switch]$SkipBuild)
. "$PSScriptRoot\sdk.ps1"
$finEnergyRoot = Get-FinEnergyRoot
if (-not $SkipBuild) { & "$PSScriptRoot\build.ps1" -SdkPath $SdkPath }
$finEnergySdk = Get-FinEnergySdk -SdkPath $SdkPath
$finEnergyPreviousHome = $env:FAN_HOME
try {
    $env:FAN_HOME = $finEnergySdk
    Push-Location $finEnergyRoot
    try {
        Invoke-FinEnergyCommand (Join-Path $finEnergySdk 'bin\fant.bat') @('finEnergy')
        Invoke-FinEnergyCommand 'npm.cmd' @('--prefix', 'finEnergy.pod/ts', 'test', '--', '--run')
        Invoke-FinEnergyCommand 'npm.cmd' @('--prefix', 'finEnergy.pod/ts', 'run', 'build')
    }
    finally { Pop-Location }
}
finally { $env:FAN_HOME = $finEnergyPreviousHome }

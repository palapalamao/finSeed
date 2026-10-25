param([string]$SdkPath, [switch]$SkipBuild)
. "$PSScriptRoot\sdk.ps1"
$enerCubixRoot = Get-EnerCubixRoot
if (-not $SkipBuild) { & "$PSScriptRoot\build.ps1" -SdkPath $SdkPath }
$enerCubixSdk = Get-EnerCubixSdk -SdkPath $SdkPath
$enerCubixPreviousHome = $env:FAN_HOME
try {
    $env:FAN_HOME = $enerCubixSdk
    Push-Location $enerCubixRoot
    try {
        Invoke-EnerCubixCommand (Join-Path $enerCubixSdk 'bin\fant.bat') @('enerCubix')
        Invoke-EnerCubixCommand 'npm.cmd' @('--prefix', 'enerCubix.pod/ts', 'test', '--', '--run')
        Invoke-EnerCubixCommand 'npm.cmd' @('--prefix', 'enerCubix.pod/ts', 'run', 'build')
    }
    finally { Pop-Location }
}
finally { $env:FAN_HOME = $enerCubixPreviousHome }

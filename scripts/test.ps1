param([string]$SdkPath, [switch]$SkipBuild)
. "$PSScriptRoot\sdk.ps1"
$seedRoot = Get-SeedRoot
if (-not $SkipBuild) { & "$PSScriptRoot\build.ps1" -SdkPath $SdkPath }
$seedSdk = Get-SeedSdk -SdkPath $SdkPath
$seedPreviousHome = $env:FAN_HOME
try {
    $env:FAN_HOME = $seedSdk
    Push-Location $seedRoot
    try {
        Invoke-SeedCommand (Join-Path $seedSdk 'bin\fant.bat') @('finSeed')
        Invoke-SeedCommand 'npm.cmd' @('--prefix', 'finSeed.pod/ts', 'test', '--', '--run')
        Invoke-SeedCommand 'npm.cmd' @('--prefix', 'finSeed.pod/ts', 'run', 'build')
    }
    finally { Pop-Location }
}
finally { $env:FAN_HOME = $seedPreviousHome }

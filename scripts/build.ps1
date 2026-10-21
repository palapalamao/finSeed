param([string]$SdkPath, [switch]$SkipUi)
. "$PSScriptRoot\sdk.ps1"
$seedRoot = Get-SeedRoot
$seedSdk = Get-SeedSdk -SdkPath $SdkPath
$seedPreviousHome = $env:FAN_HOME
$seedPreviousUi = $env:FINSEED_UI_BUILT
try {
    $env:FAN_HOME = $seedSdk
    Push-Location $seedRoot
    try {
        if (-not $SkipUi) {
            Invoke-SeedCommand 'npm.cmd' @('--prefix', 'finSeed.pod/ts', 'run', 'build')
        }
        if (-not (Test-Path -LiteralPath 'finSeed.pod\res\web\seed\index.html')) {
            throw 'UI output missing; run the UI build before packing the Pod.'
        }
        $env:FINSEED_UI_BUILT = 'true'
        Push-Location 'finSeed.pod'
        try { Invoke-SeedCommand (Join-Path $seedSdk 'bin\fan.bat') @('build.fan') -FailurePattern '(?m)^BUILD FAILED' }
        finally { Pop-Location }
        New-Item -ItemType Directory -Force -Path 'out' | Out-Null
        Copy-Item -LiteralPath (Join-Path $seedSdk 'lib\fan\finSeed.pod') -Destination 'out\finSeed.pod' -Force
        Write-Host "Built $seedRoot\out\finSeed.pod against isolated SDK $seedSdk"
    }
    finally { Pop-Location }
}
finally {
    $env:FAN_HOME = $seedPreviousHome
    $env:FINSEED_UI_BUILT = $seedPreviousUi
}

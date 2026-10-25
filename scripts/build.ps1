param([string]$SdkPath, [switch]$SkipUi)
. "$PSScriptRoot\sdk.ps1"
$enerCubixRoot = Get-EnerCubixRoot
$enerCubixSdk = Get-EnerCubixSdk -SdkPath $SdkPath
$enerCubixPreviousHome = $env:FAN_HOME
$enerCubixPreviousUi = $env:ENERCUBIX_UI_BUILT
try {
    $env:FAN_HOME = $enerCubixSdk
    Push-Location $enerCubixRoot
    try {
        if (-not $SkipUi) {
            Invoke-EnerCubixCommand 'npm.cmd' @('--prefix', 'enerCubix.pod/ts', 'run', 'build')
        }
        if (-not (Test-Path -LiteralPath 'enerCubix.pod\res\web\enerCubix\index.html')) {
            throw 'UI output missing; run the UI build before packing the Pod.'
        }
        $env:ENERCUBIX_UI_BUILT = 'true'
        Push-Location 'enerCubix.pod'
        try { Invoke-EnerCubixCommand (Join-Path $enerCubixSdk 'bin\fan.bat') @('build.fan') -FailurePattern '(?m)^BUILD FAILED' }
        finally { Pop-Location }
        New-Item -ItemType Directory -Force -Path 'out' | Out-Null
        Copy-Item -LiteralPath (Join-Path $enerCubixSdk 'lib\fan\enerCubix.pod') -Destination 'out\enerCubix.pod' -Force
        Write-Host "Built $enerCubixRoot\out\enerCubix.pod against isolated SDK $enerCubixSdk"
    }
    finally { Pop-Location }
}
finally {
    $env:FAN_HOME = $enerCubixPreviousHome
    $env:ENERCUBIX_UI_BUILT = $enerCubixPreviousUi
}

param([string]$SdkPath, [switch]$SkipUi)
. "$PSScriptRoot\sdk.ps1"
$finEnergyRoot = Get-FinEnergyRoot
$finEnergySdk = Get-FinEnergySdk -SdkPath $SdkPath
$finEnergyPreviousHome = $env:FAN_HOME
$finEnergyPreviousUi = $env:FINENERGY_UI_BUILT
try {
    $env:FAN_HOME = $finEnergySdk
    Push-Location $finEnergyRoot
    try {
        Invoke-FinEnergyCommand 'node' @('scripts/check-primary-energy-source.mjs')
        if (-not $SkipUi) {
            Invoke-FinEnergyCommand 'npm.cmd' @('--prefix', 'finEnergy.pod/ts', 'run', 'build')
        }
        if (-not (Test-Path -LiteralPath 'finEnergy.pod\res\web\finEnergy\index.html')) {
            throw 'UI output missing; run the UI build before packing the Pod.'
        }
        $finEnergyUiVersion=(Get-Content -LiteralPath 'finEnergy.pod\ts\package.json' -Raw | ConvertFrom-Json).version
        if (-not (Test-Path -LiteralPath "finEnergy.pod\res\web\finEnergy\index-$finEnergyUiVersion.html")) {
            throw 'Versioned UI entry missing; rebuild the matching frontend before packing the Pod.'
        }
        $env:FINENERGY_UI_BUILT = 'true'
        Push-Location 'finEnergy.pod'
        try { Invoke-FinEnergyCommand (Join-Path $finEnergySdk 'bin\fan.bat') @('build.fan') -FailurePattern '(?m)^BUILD FAILED' }
        finally { Pop-Location }
        New-Item -ItemType Directory -Force -Path 'out' | Out-Null
        Copy-Item -LiteralPath (Join-Path $finEnergySdk 'lib\fan\finEnergy.pod') -Destination 'out\finEnergy.pod' -Force
        Write-Host "Built $finEnergyRoot\out\finEnergy.pod against isolated SDK $finEnergySdk"
    }
    finally { Pop-Location }
}
finally {
    $env:FAN_HOME = $finEnergyPreviousHome
    $env:FINENERGY_UI_BUILT = $finEnergyPreviousUi
}

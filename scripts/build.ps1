param([string]$SdkPath, [switch]$SkipUi, [string]$LicenseKeyring)
. "$PSScriptRoot\sdk.ps1"
$finEnergyRoot = Get-FinEnergyRoot
$finEnergySdk = Get-FinEnergySdk -SdkPath $SdkPath
$finEnergyPreviousHome = $env:FAN_HOME
$finEnergyPreviousUi = $env:FINENERGY_UI_BUILT
$finEnergyKeyringPath = Join-Path $finEnergyRoot 'finEnergy.pod\res\license-keys.json'
$finEnergyPreparedKeyring = $false
try {
    if (Test-Path -LiteralPath $finEnergyKeyringPath) {
        throw 'A build keyring is already present in the Pod source. Use -LicenseKeyring to select a keyring for this build.'
    }
    if ($LicenseKeyring) {
        $finEnergyKeyringSource = (Resolve-Path -LiteralPath $LicenseKeyring -ErrorAction Stop).Path
        Invoke-FinEnergyCommand 'node' @((Join-Path $PSScriptRoot 'prepare-license-keyring.mjs'), $finEnergyKeyringSource, $finEnergyKeyringPath)
        $finEnergyPreparedKeyring = $true
    }
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
    if ($finEnergyPreparedKeyring) { Remove-Item -LiteralPath $finEnergyKeyringPath }
    $env:FAN_HOME = $finEnergyPreviousHome
    $env:FINENERGY_UI_BUILT = $finEnergyPreviousUi
}

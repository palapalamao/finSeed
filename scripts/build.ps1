param([string]$SdkPath, [switch]$SkipUi, [string]$LicenseKeyring)
. "$PSScriptRoot\sdk.ps1"
$enerCubixRoot = Get-EnerCubixRoot
$enerCubixSdk = Get-EnerCubixSdk -SdkPath $SdkPath
$enerCubixPreviousHome = $env:FAN_HOME
$enerCubixPreviousUi = $env:ENERCUBIX_UI_BUILT
$enerCubixKeyringPath = Join-Path $enerCubixRoot 'enerCubix.pod\res\license-keys.json'
$enerCubixPreparedKeyring = $false
try {
    if (Test-Path -LiteralPath $enerCubixKeyringPath) {
        throw 'A build keyring is already present in the Pod source. Use -LicenseKeyring to select a keyring for this build.'
    }
    if ($LicenseKeyring) {
        $enerCubixKeyringSource = (Resolve-Path -LiteralPath $LicenseKeyring -ErrorAction Stop).Path
        Invoke-EnerCubixCommand 'node' @((Join-Path $PSScriptRoot 'prepare-license-keyring.mjs'), $enerCubixKeyringSource, $enerCubixKeyringPath)
        $enerCubixPreparedKeyring = $true
    }
    $env:FAN_HOME = $enerCubixSdk
    Push-Location $enerCubixRoot
    try {
        Invoke-EnerCubixCommand 'node' @('scripts/check-primary-energy-source.mjs')
        if (-not $SkipUi) {
            Invoke-EnerCubixCommand 'npm.cmd' @('--prefix', 'enerCubix.pod/ts', 'run', 'build')
        }
        if (-not (Test-Path -LiteralPath 'enerCubix.pod\res\web\enerCubix\index.html')) {
            throw 'UI output missing; run the UI build before packing the Pod.'
        }
        $enerCubixUiVersion=(Get-Content -LiteralPath 'enerCubix.pod\ts\package.json' -Raw | ConvertFrom-Json).version
        if (-not (Test-Path -LiteralPath "enerCubix.pod\res\web\enerCubix\index-$enerCubixUiVersion.html")) {
            throw 'Versioned UI entry missing; rebuild the matching frontend before packing the Pod.'
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
    if ($enerCubixPreparedKeyring) { Remove-Item -LiteralPath $enerCubixKeyringPath }
    $env:FAN_HOME = $enerCubixPreviousHome
    $env:ENERCUBIX_UI_BUILT = $enerCubixPreviousUi
}

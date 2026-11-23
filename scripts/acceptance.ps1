param([string]$PodPath, [ValidateSet('China','HQ')][string]$Edition)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (!$Edition) { throw 'Choose -Edition China or -Edition HQ.' }
$finEnergyEdition = $Edition.ToLowerInvariant()
$finEnergyMode = if ($Edition -eq 'China') { 'selfManaged' } else { 'finNative' }
if (!$PodPath) { $PodPath = Join-Path $PSScriptRoot "..\out\$finEnergyEdition\finEnergy.pod" }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$finEnergyArtifact = (Resolve-Path -LiteralPath $PodPath).Path
$finEnergyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$finEnergyVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $finEnergyRoot 'finEnergy.pod\build.fan')), 'version\s*=\s*Version\("([^"]+)"\)').Groups[1].Value
if (-not $finEnergyVersion) { throw 'Build version is missing.' }
foreach ($finEnergyManifest in @('package.json', 'finEnergy.pod\ts\package.json', 'finEnergy.pod\ts\package-lock.json')) {
    # Windows PowerShell 5 cannot decode npm's empty packages[""] key.
    $finEnergyManifestVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $finEnergyRoot $finEnergyManifest)), '(?m)^  "version":\s*"([^"]+)"').Groups[1].Value
    if ($finEnergyManifestVersion -ne $finEnergyVersion) { throw "Version mismatch in $finEnergyManifest : expected $finEnergyVersion, got $finEnergyManifestVersion." }
}
$finEnergyZip = [IO.Compression.ZipFile]::OpenRead($finEnergyArtifact)
try {
    $finEnergyEntries = @($finEnergyZip.Entries | ForEach-Object FullName)
    $finEnergyRequired = @('meta.props', 'index.props', 'lib/menu.trio', 'locale/en.props', 'locale/zh.props', 'res/Manrope-OFL.txt', 'res/Manrope-SOURCE.txt', 'res/web/finEnergy/index.html', "res/web/finEnergy/index-$finEnergyVersion.html", 'res/web/finEnergy/build-info.json')
    foreach ($finEnergyEntry in $finEnergyRequired) {
        if ($finEnergyEntry -notin $finEnergyEntries) { throw "Pod missing required entry: $finEnergyEntry" }
    }
    $hasLocalKeys = 'res/license-keys.json' -in $finEnergyEntries
    $hasNativePolicy = 'fcode/FinEnergyNativeLicense.fcode' -in $finEnergyEntries
    $hasLocalPolicy = 'fcode/FinEnergyLicenseGrant.fcode' -in $finEnergyEntries
    if ($Edition -eq 'HQ' -and ($hasLocalKeys -or $hasLocalPolicy -or !$hasNativePolicy)) { throw 'HQ package contains unexpected authorization material.' }
    if ($Edition -eq 'China' -and (!$hasLocalKeys -or !$hasLocalPolicy -or $hasNativePolicy)) { throw 'China package contains unexpected authorization material.' }
    if (-not ($finEnergyEntries | Where-Object { $_ -match '^res/web/finEnergy/modules/Manrope.*\.ttf$' })) { throw 'Locally packaged Manrope font is missing.' }
    $finEnergyReader = [IO.StreamReader]::new($finEnergyZip.GetEntry('meta.props').Open())
    try { $finEnergyMeta = $finEnergyReader.ReadToEnd() } finally { $finEnergyReader.Dispose() }
    if ($finEnergyMeta -notmatch '(?m)^pod.name=finEnergy\s*$' -or $finEnergyMeta -notmatch ('(?m)^pod.version=' + [regex]::Escape($finEnergyVersion) + '\s*$')) { throw 'Pod name/version mismatch.' }
    if ($finEnergyMeta -cnotmatch "(?m)^finEnergy\.edition=$finEnergyEdition\s*$" -or
        $finEnergyMeta -cnotmatch "(?m)^finEnergy\.licenseMode=$finEnergyMode\s*$") { throw 'Wrong Pod edition or license mode.' }
    $finEnergyReader = [IO.StreamReader]::new($finEnergyZip.GetEntry('res/web/finEnergy/build-info.json').Open())
    try { $finEnergyUi = $finEnergyReader.ReadToEnd() | ConvertFrom-Json } finally { $finEnergyReader.Dispose() }
    if ($finEnergyUi.edition -cne $finEnergyEdition -or $finEnergyUi.licenseMode -cne $finEnergyMode -or
        $finEnergyUi.version -cne $finEnergyVersion) { throw 'UI and Pod build identities differ.' }
    if ($finEnergyUi.sourceCommit -and
        $finEnergyMeta -cnotmatch ('(?m)^finEnergy\.sourceCommit=' + [regex]::Escape($finEnergyUi.sourceCommit) + '\s*$')) {
        throw 'UI and Pod source commits differ.'
    }
    $finEnergyReader = [IO.StreamReader]::new($finEnergyZip.GetEntry('index.props').Open())
    try { $finEnergyIndex = $finEnergyReader.ReadToEnd() } finally { $finEnergyReader.Dispose() }
    foreach ($finEnergyRegistration in @('skyarc.ext=finEnergy::FinEnergyExt', 'skyarc.lib=finEnergy::FinEnergyLib', 'fin.lang=finEnergy')) {
        if (-not $finEnergyIndex.Contains($finEnergyRegistration)) { throw "Missing registration: $finEnergyRegistration" }
    }
    $finEnergyResult = [ordered]@{
        artifact = $finEnergyArtifact
        version = $finEnergyVersion
        edition = $finEnergyEdition
        licenseMode = $finEnergyMode
        sha256 = (Get-FileHash -LiteralPath $finEnergyArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
        checkedAt = [DateTime]::UtcNow.ToString('o')
        targetFin = '5.3.0.2761'
        archiveChecks = 'passed'
        requiredEntries = $finEnergyRequired
        resourceEntries = @($finEnergyEntries | Where-Object { $_ -match '^(lib/|locale/|res/)' })
        runtimeVerified = $false
        nativeFeature = if ($Edition -eq 'HQ') { 'finenergy' } else { $null }
        nativeFeatureConfirmedByHq = ($Edition -eq 'HQ')
        licensedRuntimeVerified = $false
    }
    $finEnergyJson = $finEnergyResult | ConvertTo-Json -Depth 6
    $finEnergyReport = Join-Path (Split-Path -Parent $finEnergyArtifact) 'acceptance.json'
    [IO.File]::WriteAllText($finEnergyReport, $finEnergyJson, [Text.UTF8Encoding]::new($false))
    Write-Output $finEnergyJson
}
finally { $finEnergyZip.Dispose() }

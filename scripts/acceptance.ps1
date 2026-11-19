param([string]$PodPath = (Join-Path $PSScriptRoot '..\out\finEnergy.pod'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
    $finEnergyRequired = @('meta.props', 'index.props', 'lib/menu.trio', 'locale/en.props', 'locale/zh.props', 'res/Manrope-OFL.txt', 'res/Manrope-SOURCE.txt', 'res/web/finEnergy/index.html', "res/web/finEnergy/index-$finEnergyVersion.html")
    foreach ($finEnergyEntry in $finEnergyRequired) {
        if ($finEnergyEntry -notin $finEnergyEntries) { throw "Pod missing required entry: $finEnergyEntry" }
    }
    if ('res/license-keys.json' -in $finEnergyEntries) { throw 'Native FIN candidate must not include a legacy RSA keyring.' }
    if (-not ($finEnergyEntries | Where-Object { $_ -match '^res/web/finEnergy/modules/Manrope.*\.ttf$' })) { throw 'Locally packaged Manrope font is missing.' }
    $finEnergyReader = [IO.StreamReader]::new($finEnergyZip.GetEntry('meta.props').Open())
    try { $finEnergyMeta = $finEnergyReader.ReadToEnd() } finally { $finEnergyReader.Dispose() }
    if ($finEnergyMeta -notmatch '(?m)^pod.name=finEnergy\s*$' -or $finEnergyMeta -notmatch ('(?m)^pod.version=' + [regex]::Escape($finEnergyVersion) + '\s*$')) { throw 'Pod name/version mismatch.' }
    $finEnergyReader = [IO.StreamReader]::new($finEnergyZip.GetEntry('index.props').Open())
    try { $finEnergyIndex = $finEnergyReader.ReadToEnd() } finally { $finEnergyReader.Dispose() }
    foreach ($finEnergyRegistration in @('skyarc.ext=finEnergy::FinEnergyExt', 'skyarc.lib=finEnergy::FinEnergyLib', 'fin.lang=finEnergy')) {
        if (-not $finEnergyIndex.Contains($finEnergyRegistration)) { throw "Missing registration: $finEnergyRegistration" }
    }
    $finEnergyResult = [ordered]@{
        artifact = $finEnergyArtifact
        version = $finEnergyVersion
        sha256 = (Get-FileHash -LiteralPath $finEnergyArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
        checkedAt = [DateTime]::UtcNow.ToString('o')
        targetFin = '5.3.0.2761'
        archiveChecks = 'passed'
        requiredEntries = $finEnergyRequired
        resourceEntries = @($finEnergyEntries | Where-Object { $_ -match '^(lib/|locale/|res/)' })
        runtimeVerified = $false
        nativeFeature = 'fin energy'
        nativeFeatureConfirmedByHq = $false
        licensedRuntimeVerified = $false
    }
    $finEnergyJson = $finEnergyResult | ConvertTo-Json -Depth 6
    $finEnergyReport = Join-Path (Split-Path -Parent $finEnergyArtifact) 'acceptance.json'
    [IO.File]::WriteAllText($finEnergyReport, $finEnergyJson, [Text.UTF8Encoding]::new($false))
    Write-Output $finEnergyJson
}
finally { $finEnergyZip.Dispose() }

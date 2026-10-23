param([string]$PodPath = (Join-Path $PSScriptRoot '..\out\enerCubix.pod'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$seedArtifact = (Resolve-Path -LiteralPath $PodPath).Path
$seedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$seedVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $seedRoot 'finSeed.pod\build.fan')), 'version\s*=\s*Version\("([^"]+)"\)').Groups[1].Value
if (-not $seedVersion) { throw 'Build version is missing.' }
foreach ($seedManifest in @('package.json', 'finSeed.pod\ts\package.json', 'finSeed.pod\ts\package-lock.json')) {
    # Windows PowerShell 5 cannot decode npm's empty packages[""] key.
    $seedManifestVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $seedRoot $seedManifest)), '(?m)^  "version":\s*"([^"]+)"').Groups[1].Value
    if ($seedManifestVersion -ne $seedVersion) { throw "Version mismatch in $seedManifest : expected $seedVersion, got $seedManifestVersion." }
}
$seedZip = [IO.Compression.ZipFile]::OpenRead($seedArtifact)
try {
    $seedEntries = @($seedZip.Entries | ForEach-Object FullName)
    $seedRequired = @('meta.props', 'index.props', 'lib/menu.trio', 'locale/en.props', 'locale/zh.props', 'res/web/seed/index.html')
    foreach ($seedEntry in $seedRequired) {
        if ($seedEntry -notin $seedEntries) { throw "Pod missing required entry: $seedEntry" }
    }
    $seedReader = [IO.StreamReader]::new($seedZip.GetEntry('meta.props').Open())
    try { $seedMeta = $seedReader.ReadToEnd() } finally { $seedReader.Dispose() }
    if ($seedMeta -notmatch '(?m)^pod.name=enerCubix\s*$' -or $seedMeta -notmatch ('(?m)^pod.version=' + [regex]::Escape($seedVersion) + '\s*$')) { throw 'Pod name/version mismatch.' }
    $seedReader = [IO.StreamReader]::new($seedZip.GetEntry('index.props').Open())
    try { $seedIndex = $seedReader.ReadToEnd() } finally { $seedReader.Dispose() }
    foreach ($seedRegistration in @('skyarc.ext=enerCubix::SeedExt', 'skyarc.lib=enerCubix::SeedLib', 'fin.lang=enerCubix')) {
        if (-not $seedIndex.Contains($seedRegistration)) { throw "Missing registration: $seedRegistration" }
    }
    $seedResult = [ordered]@{
        artifact = $seedArtifact
        version = $seedVersion
        sha256 = (Get-FileHash -LiteralPath $seedArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
        checkedAt = [DateTime]::UtcNow.ToString('o')
        targetFin = '5.3.0.2761'
        archiveChecks = 'passed'
        requiredEntries = $seedRequired
        resourceEntries = @($seedEntries | Where-Object { $_ -match '^(lib/|locale/|res/)' })
        runtimeVerified = $false
    }
    $seedJson = $seedResult | ConvertTo-Json -Depth 6
    $seedReport = Join-Path (Split-Path -Parent $seedArtifact) 'acceptance.json'
    [IO.File]::WriteAllText($seedReport, $seedJson, [Text.UTF8Encoding]::new($false))
    Write-Output $seedJson
}
finally { $seedZip.Dispose() }

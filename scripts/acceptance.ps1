param([string]$PodPath = (Join-Path $PSScriptRoot '..\out\enerCubix.pod'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$enerCubixArtifact = (Resolve-Path -LiteralPath $PodPath).Path
$enerCubixRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$enerCubixVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $enerCubixRoot 'enerCubix.pod\build.fan')), 'version\s*=\s*Version\("([^"]+)"\)').Groups[1].Value
if (-not $enerCubixVersion) { throw 'Build version is missing.' }
foreach ($enerCubixManifest in @('package.json', 'enerCubix.pod\ts\package.json', 'enerCubix.pod\ts\package-lock.json')) {
    # Windows PowerShell 5 cannot decode npm's empty packages[""] key.
    $enerCubixManifestVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $enerCubixRoot $enerCubixManifest)), '(?m)^  "version":\s*"([^"]+)"').Groups[1].Value
    if ($enerCubixManifestVersion -ne $enerCubixVersion) { throw "Version mismatch in $enerCubixManifest : expected $enerCubixVersion, got $enerCubixManifestVersion." }
}
$enerCubixZip = [IO.Compression.ZipFile]::OpenRead($enerCubixArtifact)
try {
    $enerCubixEntries = @($enerCubixZip.Entries | ForEach-Object FullName)
    $enerCubixRequired = @('meta.props', 'index.props', 'lib/menu.trio', 'locale/en.props', 'locale/zh.props', 'res/web/enerCubix/index.html')
    foreach ($enerCubixEntry in $enerCubixRequired) {
        if ($enerCubixEntry -notin $enerCubixEntries) { throw "Pod missing required entry: $enerCubixEntry" }
    }
    $enerCubixReader = [IO.StreamReader]::new($enerCubixZip.GetEntry('meta.props').Open())
    try { $enerCubixMeta = $enerCubixReader.ReadToEnd() } finally { $enerCubixReader.Dispose() }
    if ($enerCubixMeta -notmatch '(?m)^pod.name=enerCubix\s*$' -or $enerCubixMeta -notmatch ('(?m)^pod.version=' + [regex]::Escape($enerCubixVersion) + '\s*$')) { throw 'Pod name/version mismatch.' }
    $enerCubixReader = [IO.StreamReader]::new($enerCubixZip.GetEntry('index.props').Open())
    try { $enerCubixIndex = $enerCubixReader.ReadToEnd() } finally { $enerCubixReader.Dispose() }
    foreach ($enerCubixRegistration in @('skyarc.ext=enerCubix::EnerCubixExt', 'skyarc.lib=enerCubix::EnerCubixLib', 'fin.lang=enerCubix')) {
        if (-not $enerCubixIndex.Contains($enerCubixRegistration)) { throw "Missing registration: $enerCubixRegistration" }
    }
    $enerCubixResult = [ordered]@{
        artifact = $enerCubixArtifact
        version = $enerCubixVersion
        sha256 = (Get-FileHash -LiteralPath $enerCubixArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
        checkedAt = [DateTime]::UtcNow.ToString('o')
        targetFin = '5.3.0.2761'
        archiveChecks = 'passed'
        requiredEntries = $enerCubixRequired
        resourceEntries = @($enerCubixEntries | Where-Object { $_ -match '^(lib/|locale/|res/)' })
        runtimeVerified = $false
    }
    $enerCubixJson = $enerCubixResult | ConvertTo-Json -Depth 6
    $enerCubixReport = Join-Path (Split-Path -Parent $enerCubixArtifact) 'acceptance.json'
    [IO.File]::WriteAllText($enerCubixReport, $enerCubixJson, [Text.UTF8Encoding]::new($false))
    Write-Output $enerCubixJson
}
finally { $enerCubixZip.Dispose() }

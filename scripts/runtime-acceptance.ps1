param([string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$seedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$seedRequests = Join-Path $seedRoot '.local\acceptance-requests'
$seedReports = Join-Path $seedRoot 'out\native'
New-Item -ItemType Directory -Force -Path $seedRequests, $seedReports | Out-Null
$seedChecks = [ordered]@{}

function Invoke-SeedAcceptanceStep([string]$Name, [string]$Connection, [string]$Expression) {
    $seedRequest = [ordered]@{ operation = 'axon'; connection_id = $Connection; expression = "try $Expression catch (err) {caught:err.toStr}"; max_rows = 10; max_bytes = 25000; timeout_seconds = 60 }
    $seedRequestPath = Join-Path $seedRequests "$Name.json"
    $seedReportPath = Join-Path $seedReports "$Name.json"
    [IO.File]::WriteAllText($seedRequestPath, ($seedRequest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    & "$PSScriptRoot\audited-fin.ps1" -RequestFile $seedRequestPath -OutputFile $seedReportPath -ExpertWorkspace $ExpertWorkspace
    $seedResponse = Get-Content -Raw -LiteralPath $seedReportPath | ConvertFrom-Json
    $seedRow = $seedResponse.data.data.data.rows[0]
    if ('caught' -in $seedRow.PSObject.Properties.Name) { throw "$Name failed: $($seedRow.caught)" }
    if ('result' -notin $seedRow.PSObject.Properties.Name) { throw "$Name returned no acceptance result." }
    $seedResult = $seedRow.result | ConvertFrom-Json
    if ($seedResult.status -ne 'passed') { throw "$Name did not pass." }
    $seedChecks[$Name] = [ordered]@{ auditId = $seedResponse.data.audit_id; result = $seedResult }
}

# Each invocation authenticates through the official FIN Expert registry and audit facade.
# The functions themselves refuse any project/host outside this independent fixture.
Invoke-SeedAcceptanceStep 'calculation-persistence-history' 'finseed-acceptance-local' 'seedAcceptance()'
Invoke-SeedAcceptanceStep 'three-tree-persistence-migration-rollback' 'finseed-acceptance-local' 'seedThreeTreeAcceptance()'
Invoke-SeedAcceptanceStep 'native-space-refresh-and-isolation' 'finseed-acceptance-local' 'seedNativeSpaceAcceptance()'
Invoke-SeedAcceptanceStep 'engineering-atomic-operations' 'finseed-acceptance-local' 'seedEngineeringAcceptance()'
Invoke-SeedAcceptanceStep 'real-http-business-routes' 'finseed-acceptance-local' 'seedTransportAcceptance()'
Invoke-SeedAcceptanceStep 'native-readonly-permissions' 'finseed-acceptance-reader' 'seedPermissionAcceptance()'
$seedRuntimePod = Join-Path $seedRoot '.local\runtime-sdk\lib\fan\enerCubix.pod'
$seedSummary = [ordered]@{ checkedAt = [DateTime]::UtcNow.ToString('o'); targetFin = '5.3.0.2761'; project = 'finseed_acceptance'; podSha256 = (Get-FileHash -LiteralPath $seedRuntimePod -Algorithm SHA256).Hash.ToLowerInvariant(); status = 'passed'; checks = $seedChecks; browserScope = 'Native HTTP and audited FIN identity are checked here. Separate browser suites distinguish controlled API fixtures from real FIN business responses through the audited loopback bridge; they do not certify native browser-cookie login.' }
[IO.File]::WriteAllText((Join-Path $seedRoot 'out\runtime-acceptance.json'), ($seedSummary | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
Write-Output 'Native FIN calculation, persistence, real HTTP routes and readonly permissions passed. See out/runtime-acceptance.json.'

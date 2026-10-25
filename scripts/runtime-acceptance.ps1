param([string]$ExpertWorkspace = 'D:\FINExpert-Export\fin-expert2.1\FINExpert\finprofile')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$enerCubixRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$enerCubixRequests = Join-Path $enerCubixRoot '.local\acceptance-requests'
$enerCubixReports = Join-Path $enerCubixRoot 'out\native'
New-Item -ItemType Directory -Force -Path $enerCubixRequests, $enerCubixReports | Out-Null
$enerCubixChecks = [ordered]@{}

function Invoke-EnerCubixAcceptanceStep([string]$Name, [string]$Connection, [string]$Expression) {
    $enerCubixRequest = [ordered]@{ operation = 'axon'; connection_id = $Connection; expression = "try $Expression catch (err) {caught:err.toStr}"; max_rows = 10; max_bytes = 25000; timeout_seconds = 60 }
    $enerCubixRequestPath = Join-Path $enerCubixRequests "$Name.json"
    $enerCubixReportPath = Join-Path $enerCubixReports "$Name.json"
    [IO.File]::WriteAllText($enerCubixRequestPath, ($enerCubixRequest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    & "$PSScriptRoot\audited-fin.ps1" -RequestFile $enerCubixRequestPath -OutputFile $enerCubixReportPath -ExpertWorkspace $ExpertWorkspace
    $enerCubixResponse = Get-Content -Raw -LiteralPath $enerCubixReportPath | ConvertFrom-Json
    $enerCubixRow = $enerCubixResponse.data.data.data.rows[0]
    if ('caught' -in $enerCubixRow.PSObject.Properties.Name) { throw "$Name failed: $($enerCubixRow.caught)" }
    if ('result' -notin $enerCubixRow.PSObject.Properties.Name) { throw "$Name returned no acceptance result." }
    $enerCubixResult = $enerCubixRow.result | ConvertFrom-Json
    if ($enerCubixResult.status -ne 'passed') { throw "$Name did not pass." }
    $enerCubixChecks[$Name] = [ordered]@{ auditId = $enerCubixResponse.data.audit_id; result = $enerCubixResult }
}

# Each invocation authenticates through the official FIN Expert registry and audit facade.
# The functions themselves refuse any project/host outside this independent fixture.
Invoke-EnerCubixAcceptanceStep 'calculation-persistence-history' 'enerCubix-acceptance-local' 'enerCubixAcceptance()'
Invoke-EnerCubixAcceptanceStep 'three-tree-persistence-migration-rollback' 'enerCubix-acceptance-local' 'enerCubixThreeTreeAcceptance()'
Invoke-EnerCubixAcceptanceStep 'native-space-refresh-and-isolation' 'enerCubix-acceptance-local' 'enerCubixNativeSpaceAcceptance()'
Invoke-EnerCubixAcceptanceStep 'engineering-atomic-operations' 'enerCubix-acceptance-local' 'enerCubixEngineeringAcceptance()'
Invoke-EnerCubixAcceptanceStep 'real-http-business-routes' 'enerCubix-acceptance-local' 'enerCubixTransportAcceptance()'
Invoke-EnerCubixAcceptanceStep 'native-readonly-permissions' 'enerCubix-acceptance-reader' 'enerCubixPermissionAcceptance()'
$enerCubixRuntimePod = Join-Path $enerCubixRoot '.local\runtime-sdk\lib\fan\enerCubix.pod'
$enerCubixSummary = [ordered]@{ checkedAt = [DateTime]::UtcNow.ToString('o'); targetFin = '5.3.0.2761'; project = 'enerCubix_acceptance'; podSha256 = (Get-FileHash -LiteralPath $enerCubixRuntimePod -Algorithm SHA256).Hash.ToLowerInvariant(); status = 'passed'; checks = $enerCubixChecks; browserScope = 'Native HTTP and audited FIN identity are checked here. Separate browser suites distinguish controlled API fixtures from real FIN business responses through the audited loopback bridge; they do not certify native browser-cookie login.' }
[IO.File]::WriteAllText((Join-Path $enerCubixRoot 'out\runtime-acceptance.json'), ($enerCubixSummary | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
Write-Output 'Native FIN calculation, persistence, real HTTP routes and readonly permissions passed. See out/runtime-acceptance.json.'

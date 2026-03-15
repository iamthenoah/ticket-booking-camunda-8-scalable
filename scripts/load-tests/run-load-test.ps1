[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("low-load", "medium-load", "high-load", "medium-soak", "ramp-load", "burst-load", "edge-load", "peak-load")]
  [string]$Scenario,
  [string]$MonitoringNamespace = "monitoring",
  [int]$GrafanaLocalPort = 3000,
  [int]$PushgatewayLocalPort = 9091,
  [int]$PrometheusScrapeWaitSeconds = 20
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path
}

function Get-GrafanaCredentials {
  param(
    [string]$Namespace,
    [string]$MonitoringRelease
  )

  $secretName = kubectl get secret -n $Namespace `
    -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$MonitoringRelease" `
    -o jsonpath="{.items[0].metadata.name}"

  if (-not $secretName) {
    throw "Could not find the Grafana secret in namespace '$Namespace'."
  }

  $adminUserB64 = kubectl get secret $secretName -n $Namespace -o jsonpath="{.data.admin-user}"
  $adminPasswordB64 = kubectl get secret $secretName -n $Namespace -o jsonpath="{.data.admin-password}"

  return @{
    User = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($adminUserB64))
    Password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($adminPasswordB64))
  }
}

function New-BasicAuthHeader {
  param(
    [string]$User,
    [string]$Password
  )

  $bytes = [Text.Encoding]::ASCII.GetBytes("$User`:$Password")
  return "Basic " + [Convert]::ToBase64String($bytes)
}

function Publish-GrafanaAnnotation {
  param(
    [string]$GrafanaUrl,
    [hashtable]$Credentials,
    [string]$RunId,
    [string]$ScenarioName,
    [string]$Phase,
    [string]$Status
  )

  $headers = @{
    Authorization = New-BasicAuthHeader -User $Credentials.User -Password $Credentials.Password
  }

  $body = @{
    time = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    text = "Load test ${Phase}: $ScenarioName ($RunId) [$Status]"
    tags = @(
      "load-test",
      "run_id:$RunId",
      "scenario:$ScenarioName",
      "phase:$Phase",
      "status:$Status"
    )
  } | ConvertTo-Json

  Invoke-RestMethod `
    -Method Post `
    -Uri "$GrafanaUrl/api/annotations" `
    -Headers $headers `
    -ContentType "application/json" `
    -Body $body | Out-Null
}

function Invoke-PushgatewayCleanup {
  param([string]$PushgatewayUrl)

  Invoke-WebRequest `
    -UseBasicParsing `
    -Method Put `
    -Uri "$PushgatewayUrl/api/v1/admin/wipe" | Out-Null
}

function Get-ScenarioExpectations {
  param([string]$ScenarioPath)

  $durations = @()
  $arrivalRates = @()

  foreach ($line in Get-Content -Path $ScenarioPath) {
    if ($line -match '^\s*-\s*duration:\s*(\d+)\s*$' -or $line -match '^\s*duration:\s*(\d+)\s*$') {
      $durations += [double]$Matches[1]
      continue
    }

    if ($line -match '^\s*arrivalRate:\s*(\d+(?:\.\d+)?)\s*$') {
      $arrivalRates += [double]$Matches[1]
    }
  }

  if ($durations.Count -eq 0 -or $arrivalRates.Count -eq 0 -or $durations.Count -ne $arrivalRates.Count) {
    throw "Could not determine expected load from scenario file '$ScenarioPath'."
  }

  $expectedDurationSeconds = 0.0
  $expectedRequests = 0.0

  for ($index = 0; $index -lt $durations.Count; $index++) {
    $expectedDurationSeconds += $durations[$index]
    $expectedRequests += ($durations[$index] * $arrivalRates[$index])
  }

  $expectedRequestRate = if ($expectedDurationSeconds -gt 0) {
    $expectedRequests / $expectedDurationSeconds
  }
  else {
    0.0
  }

  return @{
    DurationSeconds = [int][Math]::Round($expectedDurationSeconds)
    ExpectedRequests = [int][Math]::Round($expectedRequests)
    ExpectedRequestRate = [Math]::Round($expectedRequestRate, 4)
  }
}

function Publish-ExpectedMetrics {
  param(
    [string]$PushgatewayUrl,
    [string]$RunId,
    [string]$ScenarioName,
    [string]$GitSha,
    [int]$ExpectedRequests,
    [double]$ExpectedRequestRate,
    [int]$ExpectedDurationSeconds
  )

  $labels = 'run_id="{0}",scenario="{1}",env="aws-eks",git_sha="{2}"' -f $RunId, $ScenarioName, $GitSha
  $requestRate = $ExpectedRequestRate.ToString([Globalization.CultureInfo]::InvariantCulture)
  $body = @(
    "# TYPE ticket_booking_loadtest_expected_requests gauge"
    "ticket_booking_loadtest_expected_requests{$labels} $ExpectedRequests"
    "# TYPE ticket_booking_loadtest_expected_request_rate gauge"
    "ticket_booking_loadtest_expected_request_rate{$labels} $requestRate"
    "# TYPE ticket_booking_loadtest_expected_duration_seconds gauge"
    "ticket_booking_loadtest_expected_duration_seconds{$labels} $ExpectedDurationSeconds"
    ""
  ) -join "`n"

  Invoke-WebRequest `
    -UseBasicParsing `
    -Method Put `
    -Uri "$PushgatewayUrl/metrics/job/ticket-booking-loadtest-plan/instance/$RunId" `
    -ContentType "text/plain; version=0.0.4; charset=utf-8" `
    -Body $body | Out-Null
}

function Get-GitSha {
  $gitSha = git rev-parse --short HEAD 2>$null
  if ($LASTEXITCODE -eq 0 -and $gitSha) {
    return $gitSha.Trim()
  }

  return "unknown"
}

$repoRoot = Get-RepoRoot
$resultsDirectory = Join-Path $repoRoot "load-tests\results"
if (-not (Test-Path $resultsDirectory)) {
  New-Item -ItemType Directory -Path $resultsDirectory | Out-Null
}

$scenarioFiles = @{
  "low-load" = "load-tests\scenario1-low-load.yml"
  "medium-load" = "load-tests\scenario2-medium-load.yml"
  "high-load" = "load-tests\scenario4-high-load.yml"
  "medium-soak" = "load-tests\scenario5-medium-soak.yml"
  "ramp-load" = "load-tests\scenario6-ramp-load.yml"
  "burst-load" = "load-tests\scenario7-burst-load.yml"
  "edge-load" = "load-tests\scenario8-edge-load.yml"
  "peak-load" = "load-tests\scenario3-peah-load.yml"
}

$scenarioFile = Join-Path $repoRoot $scenarioFiles[$Scenario]
$runId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $Scenario
$gitSha = Get-GitSha
$grafanaUrl = "http://127.0.0.1:$GrafanaLocalPort"
$pushgatewayUrl = "http://127.0.0.1:$PushgatewayLocalPort"
$scenarioExpectations = Get-ScenarioExpectations -ScenarioPath $scenarioFile

$portForwardScript = Join-Path $repoRoot "scripts\monitoring\port-forward-monitoring.ps1"
& $portForwardScript `
  -Namespace $MonitoringNamespace `
  -GrafanaLocalPort $GrafanaLocalPort `
  -PushgatewayLocalPort $PushgatewayLocalPort

$grafanaCredentials = $null
try {
  $grafanaCredentials = Get-GrafanaCredentials -Namespace $MonitoringNamespace -MonitoringRelease "monitoring-stack"
}
catch {
  Write-Warning "Could not fetch Grafana credentials. Load test metrics will still be published, but Grafana annotations will be skipped: $($_.Exception.Message)"
}

try {
  if ($grafanaCredentials) {
    Publish-GrafanaAnnotation `
      -GrafanaUrl $grafanaUrl `
      -Credentials $grafanaCredentials `
      -RunId $runId `
      -ScenarioName $Scenario `
      -Phase "start" `
      -Status "running"
  }
}
catch {
  Write-Warning "Could not create the start annotation in Grafana: $($_.Exception.Message)"
}

$env:PUSHGATEWAY_URL = $pushgatewayUrl
$env:RUN_ID = $runId
$env:GIT_SHA = $gitSha

$resultPath = Join-Path $resultsDirectory "$runId.json"
$testSucceeded = $false

try {
  Publish-ExpectedMetrics `
    -PushgatewayUrl $pushgatewayUrl `
    -RunId $runId `
    -ScenarioName $Scenario `
    -GitSha $gitSha `
    -ExpectedRequests $scenarioExpectations.ExpectedRequests `
    -ExpectedRequestRate $scenarioExpectations.ExpectedRequestRate `
    -ExpectedDurationSeconds $scenarioExpectations.DurationSeconds

  & npx artillery run $scenarioFile --output $resultPath

  if ($LASTEXITCODE -ne 0) {
    throw "Artillery exited with code $LASTEXITCODE."
  }

  $testSucceeded = $true
}
finally {
  Start-Sleep -Seconds $PrometheusScrapeWaitSeconds

  try {
    Invoke-PushgatewayCleanup -PushgatewayUrl $pushgatewayUrl
  }
  catch {
    Write-Warning "Could not wipe the Pushgateway cache: $($_.Exception.Message)"
  }

  try {
    if ($grafanaCredentials) {
      Publish-GrafanaAnnotation `
        -GrafanaUrl $grafanaUrl `
        -Credentials $grafanaCredentials `
        -RunId $runId `
        -ScenarioName $Scenario `
        -Phase "finish" `
        -Status ($(if ($testSucceeded) { "success" } else { "failed" }))
    }
  }
  catch {
    Write-Warning "Could not create the finish annotation in Grafana: $($_.Exception.Message)"
  }
}

Write-Host ""
Write-Host "Load test completed."
Write-Host "Scenario: $Scenario"
Write-Host "Run ID: $runId"
Write-Host "Expected requests: $($scenarioExpectations.ExpectedRequests)"
Write-Host "Artillery result file: $resultPath"
Write-Host "Grafana URL: $grafanaUrl"

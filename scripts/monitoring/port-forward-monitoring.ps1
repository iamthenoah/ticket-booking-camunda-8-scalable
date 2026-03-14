[CmdletBinding()]
param(
  [string]$Namespace = "monitoring",
  [string]$MonitoringRelease = "monitoring-stack",
  [string]$PushgatewayRelease = "pushgateway",
  [int]$GrafanaLocalPort = 3000,
  [int]$PushgatewayLocalPort = 9091
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path
}

function New-RuntimeDirectory {
  $runtimePath = Join-Path (Get-RepoRoot) ".k8s\monitoring\.runtime"
  if (-not (Test-Path $runtimePath)) {
    New-Item -ItemType Directory -Path $runtimePath | Out-Null
  }

  return $runtimePath
}

function Get-PodName {
  param(
    [string]$TargetNamespace,
    [string]$LabelSelector
  )

  return kubectl get pod -n $TargetNamespace -l $LabelSelector -o jsonpath="{.items[0].metadata.name}"
}

function Get-ServiceName {
  param(
    [string]$TargetNamespace,
    [string]$LabelSelector
  )

  return kubectl get service -n $TargetNamespace -l $LabelSelector -o jsonpath="{.items[0].metadata.name}"
}

function Test-HttpEndpoint {
  param([string]$Url)

  try {
    $null = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 3
    return $true
  }
  catch {
    return $false
  }
}

$grafanaHealthUrl = "http://127.0.0.1:$GrafanaLocalPort/api/health"
$pushgatewayHealthUrl = "http://127.0.0.1:$PushgatewayLocalPort/metrics"

if ((Test-HttpEndpoint -Url $grafanaHealthUrl) -and (Test-HttpEndpoint -Url $pushgatewayHealthUrl)) {
  Write-Host "Port $GrafanaLocalPort is already serving $grafanaHealthUrl."
  Write-Host "Port $PushgatewayLocalPort is already serving $pushgatewayHealthUrl."
  Write-Host ""
  Write-Host "Grafana URL: http://127.0.0.1:$GrafanaLocalPort"
  Write-Host "Pushgateway URL: http://127.0.0.1:$PushgatewayLocalPort"
  return
}

function Start-PortForward {
  param(
    [string]$RuntimePath,
    [string]$TargetNamespace,
    [string]$ServiceName,
    [int]$LocalPort,
    [int]$RemotePort,
    [string]$HealthUrl,
    [string]$StateFileName
  )

  if (Test-HttpEndpoint -Url $HealthUrl) {
    Write-Host "Port $LocalPort is already serving $HealthUrl."
    return
  }

  $stdoutPath = Join-Path $RuntimePath "$StateFileName.stdout.log"
  $stderrPath = Join-Path $RuntimePath "$StateFileName.stderr.log"
  $statePath = Join-Path $RuntimePath "$StateFileName.json"

  $process = Start-Process `
    -FilePath "kubectl" `
    -ArgumentList @("-n", $TargetNamespace, "port-forward", "service/$ServiceName", "$LocalPort`:$RemotePort", "--address", "127.0.0.1") `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

  $state = @{
    pid = $process.Id
    service = $ServiceName
    localPort = $LocalPort
    remotePort = $RemotePort
  }

  $state | ConvertTo-Json | Set-Content -Path $statePath -Encoding ascii

  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline) {
    if (Test-HttpEndpoint -Url $HealthUrl) {
      Write-Host "Port-forward ready: $ServiceName on http://127.0.0.1:$LocalPort"
      return
    }

    Start-Sleep -Seconds 1
  }

  throw "Timed out waiting for the port-forward to $ServiceName on local port $LocalPort."
}

function Restore-GrafanaStateIfNeeded {
  param(
    [string]$RuntimePath,
    [string]$TargetNamespace,
    [string]$Release,
    [int]$LocalPort,
    [string]$GrafanaPodName
  )

  $backupRoot = Join-Path (Get-RepoRoot) ".k8s\monitoring\grafana-state"
  $dashboardIndexPath = Join-Path $backupRoot "dashboard-index.json"
  if (-not (Test-Path $dashboardIndexPath)) {
    return
  }

  $restoreStatePath = Join-Path $RuntimePath "grafana-restore-state.json"
  if (Test-Path $restoreStatePath) {
    $restoreState = Get-Content -Raw -Path $restoreStatePath | ConvertFrom-Json
    if ($restoreState.grafanaPodName -eq $GrafanaPodName) {
      return
    }
  }

  $importScript = Join-Path (Get-RepoRoot) "scripts\monitoring\import-grafana-state.ps1"

  try {
    & $importScript `
      -MonitoringNamespace $TargetNamespace `
      -MonitoringRelease $Release `
      -GrafanaLocalPort $LocalPort `
      -InputDirectory $backupRoot `
      -SkipPortForward | Out-Null

    @{
      grafanaPodName = $GrafanaPodName
      restoredAt = (Get-Date).ToString("o")
    } | ConvertTo-Json | Set-Content -Path $restoreStatePath -Encoding ascii

    Write-Host "Grafana state restored from local backup for pod '$GrafanaPodName'."
  }
  catch {
    Write-Warning "Could not restore Grafana state from local backup: $($_.Exception.Message)"
  }
}

$runtimeDirectory = New-RuntimeDirectory

$grafanaService = Get-ServiceName `
  -TargetNamespace $Namespace `
  -LabelSelector "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$MonitoringRelease"

$pushgatewayService = Get-ServiceName `
  -TargetNamespace $Namespace `
  -LabelSelector "app.kubernetes.io/name=prometheus-pushgateway,app.kubernetes.io/instance=$PushgatewayRelease"

if (-not $grafanaService) {
  throw "Could not find the Grafana service in namespace '$Namespace'."
}

if (-not $pushgatewayService) {
  throw "Could not find the Pushgateway service in namespace '$Namespace'."
}

$grafanaPodName = Get-PodName `
  -TargetNamespace $Namespace `
  -LabelSelector "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$MonitoringRelease"

Start-PortForward `
  -RuntimePath $runtimeDirectory `
  -TargetNamespace $Namespace `
  -ServiceName $grafanaService `
  -LocalPort $GrafanaLocalPort `
  -RemotePort 80 `
  -HealthUrl $grafanaHealthUrl `
  -StateFileName "grafana-port-forward"

Start-PortForward `
  -RuntimePath $runtimeDirectory `
  -TargetNamespace $Namespace `
  -ServiceName $pushgatewayService `
  -LocalPort $PushgatewayLocalPort `
  -RemotePort 9091 `
  -HealthUrl $pushgatewayHealthUrl `
  -StateFileName "pushgateway-port-forward"

if ($grafanaPodName) {
  Restore-GrafanaStateIfNeeded `
    -RuntimePath $runtimeDirectory `
    -TargetNamespace $Namespace `
    -Release $MonitoringRelease `
    -LocalPort $GrafanaLocalPort `
    -GrafanaPodName $grafanaPodName
}

Write-Host ""
Write-Host "Grafana URL: http://127.0.0.1:$GrafanaLocalPort"
Write-Host "Pushgateway URL: http://127.0.0.1:$PushgatewayLocalPort"

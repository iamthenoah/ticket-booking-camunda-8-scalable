[CmdletBinding()]
param(
  [string]$MonitoringNamespace = "monitoring",
  [string]$MonitoringRelease = "monitoring-stack",
  [int]$GrafanaLocalPort = 3000,
  [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path
}

function Get-GrafanaCredentials {
  param(
    [string]$Namespace,
    [string]$Release
  )

  $secretName = kubectl get secret -n $Namespace `
    -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$Release" `
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

function ConvertTo-Slug {
  param([string]$Value)

  $lowercase = $Value.ToLowerInvariant()
  $sanitized = [Regex]::Replace($lowercase, "[^a-z0-9._-]+", "-")
  $trimmed = $sanitized.Trim("-")

  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    return "unnamed"
  }

  return $trimmed
}

function Invoke-GrafanaApi {
  param(
    [string]$Method,
    [string]$Path,
    [hashtable]$Headers
  )

  return Invoke-RestMethod `
    -Method $Method `
    -Uri ("http://127.0.0.1:{0}{1}" -f $GrafanaLocalPort, $Path) `
    -Headers $Headers `
    -ContentType "application/json"
}

function ConvertTo-FlatArray {
  param([object]$Value)

  if ($null -eq $Value) {
    return @()
  }

  if ($Value -is [System.Array]) {
    return @($Value)
  }

  $propertyNames = @($Value.PSObject.Properties.Name)
  if ($propertyNames -contains "value" -and $Value.value -is [System.Array]) {
    return @($Value.value)
  }

  return @($Value)
}

function New-CleanDirectory {
  param([string]$Path)

  if (Test-Path $Path) {
    Remove-Item -Path $Path -Recurse -Force
  }

  New-Item -ItemType Directory -Path $Path | Out-Null
}

$repoRoot = Get-RepoRoot
if (-not $OutputDirectory) {
  $OutputDirectory = Join-Path $repoRoot ".k8s\monitoring\grafana-state"
}

$portForwardScript = Join-Path $repoRoot "scripts\monitoring\port-forward-monitoring.ps1"
& $portForwardScript `
  -Namespace $MonitoringNamespace `
  -MonitoringRelease $MonitoringRelease `
  -GrafanaLocalPort $GrafanaLocalPort | Out-Null

$grafanaCredentials = Get-GrafanaCredentials -Namespace $MonitoringNamespace -Release $MonitoringRelease
$headers = @{
  Authorization = New-BasicAuthHeader -User $grafanaCredentials.User -Password $grafanaCredentials.Password
}

$folders = ConvertTo-FlatArray -Value (Invoke-GrafanaApi -Method Get -Path "/api/folders" -Headers $headers)
$dashboards = ConvertTo-FlatArray -Value (Invoke-GrafanaApi -Method Get -Path "/api/search?type=dash-db&limit=5000" -Headers $headers)
$datasources = ConvertTo-FlatArray -Value (Invoke-GrafanaApi -Method Get -Path "/api/datasources" -Headers $headers)

New-CleanDirectory -Path $OutputDirectory
$dashboardsDirectory = Join-Path $OutputDirectory "dashboards"
New-CleanDirectory -Path $dashboardsDirectory

$folders | ConvertTo-Json -Depth 100 | Set-Content -Path (Join-Path $OutputDirectory "folders.json")
$dashboards | ConvertTo-Json -Depth 100 | Set-Content -Path (Join-Path $OutputDirectory "dashboard-index.json")
$datasources | ConvertTo-Json -Depth 100 | Set-Content -Path (Join-Path $OutputDirectory "datasources.json")

foreach ($dashboard in $dashboards) {
  if (-not $dashboard.uid -or $dashboard.type -ne "dash-db") {
    continue
  }

  try {
    $definition = Invoke-GrafanaApi -Method Get -Path "/api/dashboards/uid/$($dashboard.uid)" -Headers $headers
  }
  catch {
    Write-Warning "Could not export dashboard '$($dashboard.title)' ($($dashboard.uid)): $($_.Exception.Message)"
    continue
  }

  $folderTitle = if ([string]::IsNullOrWhiteSpace($dashboard.folderTitle)) { "General" } else { $dashboard.folderTitle }
  $folderDirectory = Join-Path $dashboardsDirectory (ConvertTo-Slug -Value $folderTitle)

  if (-not (Test-Path $folderDirectory)) {
    New-Item -ItemType Directory -Path $folderDirectory | Out-Null
  }

  $dashboardSlug = ConvertTo-Slug -Value $dashboard.title
  $outputPath = Join-Path $folderDirectory ("{0}.{1}.json" -f $dashboardSlug, $dashboard.uid)
  $definition | ConvertTo-Json -Depth 100 | Set-Content -Path $outputPath
}

Write-Host "Grafana state exported."
Write-Host "Output directory: $OutputDirectory"
Write-Host "Folders exported: $($folders.Count)"
Write-Host "Dashboards exported: $($dashboards.Count)"

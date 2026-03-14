[CmdletBinding()]
param(
  [string]$MonitoringNamespace = "monitoring",
  [string]$MonitoringRelease = "monitoring-stack",
  [int]$GrafanaLocalPort = 3000,
  [string]$InputDirectory,
  [switch]$SkipPortForward
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

function Invoke-GrafanaApi {
  param(
    [string]$Method,
    [string]$Path,
    [hashtable]$Headers,
    [string]$Body
  )

  $request = @{
    Method = $Method
    Uri = ("http://127.0.0.1:{0}{1}" -f $GrafanaLocalPort, $Path)
    Headers = $Headers
    ContentType = "application/json"
  }

  if ($Body) {
    $request.Body = $Body
  }

  return Invoke-RestMethod @request
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

function Get-JsonArray {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return @()
  }

  $content = Get-Content -Raw -Path $Path | ConvertFrom-Json
  return ConvertTo-FlatArray -Value $content
}

$repoRoot = Get-RepoRoot
if (-not $InputDirectory) {
  $InputDirectory = Join-Path $repoRoot ".k8s\monitoring\grafana-state"
}

$foldersPath = Join-Path $InputDirectory "folders.json"
$dashboardsDirectory = Join-Path $InputDirectory "dashboards"

if (-not (Test-Path $foldersPath) -or -not (Test-Path $dashboardsDirectory)) {
  Write-Host "No Grafana state backup found at '$InputDirectory'."
  return
}

if (-not $SkipPortForward) {
  $portForwardScript = Join-Path $repoRoot "scripts\monitoring\port-forward-monitoring.ps1"
  & $portForwardScript `
    -Namespace $MonitoringNamespace `
    -MonitoringRelease $MonitoringRelease `
    -GrafanaLocalPort $GrafanaLocalPort | Out-Null
}

$grafanaCredentials = Get-GrafanaCredentials -Namespace $MonitoringNamespace -Release $MonitoringRelease
$headers = @{
  Authorization = New-BasicAuthHeader -User $grafanaCredentials.User -Password $grafanaCredentials.Password
}

$existingFolders = ConvertTo-FlatArray -Value (Invoke-GrafanaApi -Method Get -Path "/api/folders" -Headers $headers)
$existingFolderUids = @{}
foreach ($folder in $existingFolders) {
  if ($folder.uid) {
    $existingFolderUids[$folder.uid] = $true
  }
}

$createdFolders = 0
$folders = Get-JsonArray -Path $foldersPath
foreach ($folder in $folders) {
  if (-not $folder.uid -or [string]::IsNullOrWhiteSpace($folder.title) -or $folder.title -eq "General") {
    continue
  }

  if ($existingFolderUids.ContainsKey($folder.uid)) {
    continue
  }

  $body = @{
    uid = $folder.uid
    title = $folder.title
  } | ConvertTo-Json

  try {
    Invoke-GrafanaApi -Method Post -Path "/api/folders" -Headers $headers -Body $body | Out-Null
    $existingFolderUids[$folder.uid] = $true
    $createdFolders++
  }
  catch {
    Write-Warning "Could not create folder '$($folder.title)': $($_.Exception.Message)"
  }
}

$restoredDashboards = 0
$skippedDashboards = 0
$dashboardFiles = Get-ChildItem -Path $dashboardsDirectory -Recurse -Filter "*.json"
foreach ($file in $dashboardFiles) {
  $definition = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
  if (-not $definition.dashboard -or -not $definition.dashboard.uid) {
    $skippedDashboards++
    continue
  }

  $dashboardClone = $definition.dashboard | ConvertTo-Json -Depth 100 | ConvertFrom-Json
  if ($dashboardClone.PSObject.Properties.Name -contains "id") {
    $dashboardClone.id = $null
  }
  if ($dashboardClone.PSObject.Properties.Name -contains "version") {
    $dashboardClone.version = 0
  }

  $body = @{
    dashboard = $dashboardClone
    overwrite = $true
    message = "Restored from local backup"
  }

  if ($definition.meta -and $definition.meta.folderUid) {
    $body.folderUid = $definition.meta.folderUid
  }

  try {
    Invoke-GrafanaApi -Method Post -Path "/api/dashboards/db" -Headers $headers -Body ($body | ConvertTo-Json -Depth 100) | Out-Null
    $restoredDashboards++
  }
  catch {
    $skippedDashboards++
    Write-Warning "Could not restore dashboard '$($definition.dashboard.title)': $($_.Exception.Message)"
  }
}

Write-Host "Grafana state import completed."
Write-Host "Input directory: $InputDirectory"
Write-Host "Folders created: $createdFolders"
Write-Host "Dashboards restored: $restoredDashboards"
Write-Host "Dashboards skipped: $skippedDashboards"

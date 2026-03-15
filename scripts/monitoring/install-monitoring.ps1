[CmdletBinding()]
param(
  [string]$Namespace = "monitoring",
  [string]$MonitoringRelease = "monitoring-stack",
  [string]$PushgatewayRelease = "pushgateway",
  [string]$KubePrometheusStackChartVersion = "81.4.2",
  [string]$PushgatewayChartVersion = "3.6.0",
  [string]$StorageClassName,
  [switch]$DisablePersistence
)

$ErrorActionPreference = "Stop"

function Assert-Command {
  param([string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' is not available. Install it locally before running this script."
  }
}

function Assert-LastExitCode {
  param([string]$Operation)

  if ($LASTEXITCODE -ne 0) {
    throw "$Operation failed with exit code $LASTEXITCODE."
  }
}

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path
}

function Get-StorageClasses {
  $storageClasses = kubectl get storageclass -o json | ConvertFrom-Json
  return @($storageClasses.items)
}

function Get-DefaultStorageClass {
  param([object[]]$StorageClasses)

  foreach ($storageClass in $StorageClasses) {
    $annotations = $storageClass.metadata.annotations
    if ($annotations."storageclass.kubernetes.io/is-default-class" -eq "true" -or
        $annotations."storageclass.beta.kubernetes.io/is-default-class" -eq "true") {
      return $storageClass
    }
  }

  return $null
}

function Resolve-StorageClassName {
  param([string]$RequestedStorageClassName)

  $storageClasses = @(Get-StorageClasses)

  if (-not $storageClasses -or $storageClasses.Count -eq 0) {
    throw "No StorageClass objects were found in the cluster. Install or configure a StorageClass before installing the monitoring stack."
  }

  if ($RequestedStorageClassName) {
    $matchingStorageClass = $storageClasses | Where-Object { $_.metadata.name -eq $RequestedStorageClassName } | Select-Object -First 1
    if (-not $matchingStorageClass) {
      $availableStorageClasses = $storageClasses | ForEach-Object { $_.metadata.name }
      throw "StorageClass '$RequestedStorageClassName' was not found. Available StorageClasses: $($availableStorageClasses -join ', ')"
    }

    return $matchingStorageClass.metadata.name
  }

  $defaultStorageClass = Get-DefaultStorageClass -StorageClasses $storageClasses
  if ($defaultStorageClass) {
    return $defaultStorageClass.metadata.name
  }

  if ($storageClasses.Count -eq 1) {
    $singleStorageClassName = $storageClasses[0].metadata.name
    Write-Host "No default StorageClass is set. Using the only available StorageClass '$singleStorageClassName' for Grafana and Prometheus PVCs."
    return $singleStorageClassName
  }

  $availableStorageClasses = $storageClasses | ForEach-Object { $_.metadata.name }
  throw "No default StorageClass was found. Re-run this script with -StorageClassName <name>. Available StorageClasses: $($availableStorageClasses -join ', ')"
}

function New-TemporaryValuesFile {
  param(
    [string]$ResolvedStorageClassName,
    [bool]$UsePersistence,
    [string]$RuntimeDirectory
  )

  if (-not (Test-Path $RuntimeDirectory)) {
    New-Item -ItemType Directory -Path $RuntimeDirectory | Out-Null
  }

  $tempValuesPath = Join-Path $RuntimeDirectory "kube-prometheus-stack.generated.values.yml"
  if ($UsePersistence) {
    $storageClassOverlay = @"
grafana:
  persistence:
    enabled: true
    type: pvc
    accessModes:
      - ReadWriteOnce
    size: 10Gi
    storageClassName: $ResolvedStorageClassName

prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi
          storageClassName: $ResolvedStorageClassName
"@
  }
  else {
    $storageClassOverlay = @"
grafana:
  persistence:
    enabled: false

prometheus:
  prometheusSpec:
    storageSpec:
      emptyDir: {}
"@
  }

  Set-Content -Path $tempValuesPath -Value ($storageClassOverlay.TrimEnd() + "`r`n")
  return $tempValuesPath
}

function Wait-ForNamespaceReadiness {
  param(
    [string]$TargetNamespace,
    [int]$TimeoutSeconds = 900
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

  while ((Get-Date) -lt $deadline) {
    $podList = kubectl get pods -n $TargetNamespace -o json | ConvertFrom-Json

    if (-not $podList.items -or $podList.items.Count -eq 0) {
      Start-Sleep -Seconds 5
      continue
    }

    $notReady = @()

    foreach ($pod in $podList.items) {
      if ($pod.status.phase -eq "Succeeded") {
        continue
      }

      $containerStatuses = @($pod.status.containerStatuses)
      $allReady = $true

      foreach ($containerStatus in $containerStatuses) {
        if (-not $containerStatus.ready) {
          $allReady = $false
          break
        }
      }

      if (-not $allReady) {
        $notReady += $pod.metadata.name
      }
    }

    if ($notReady.Count -eq 0) {
      return
    }

    Write-Host "Waiting for monitoring pods to become ready: $($notReady -join ', ')"
    Start-Sleep -Seconds 10
  }

  throw "Timed out waiting for monitoring pods in namespace '$TargetNamespace' to become ready."
}

Assert-Command -Name "helm"
Assert-Command -Name "kubectl"

$repoRoot = Get-RepoRoot
$monitoringRoot = Join-Path $repoRoot ".k8s\monitoring"
$runtimeRoot = Join-Path $monitoringRoot ".runtime"
$kubePrometheusValuesPath = Join-Path $monitoringRoot "helm-values\kube-prometheus-stack-values.yml"
$pushgatewayValuesPath = Join-Path $monitoringRoot "helm-values\prometheus-pushgateway-values.yml"
$usePersistence = -not $DisablePersistence
$resolvedStorageClassName = $null

if ($usePersistence) {
  $resolvedStorageClassName = Resolve-StorageClassName -RequestedStorageClassName $StorageClassName
}

$generatedKubePrometheusValuesPath = New-TemporaryValuesFile `
  -ResolvedStorageClassName $resolvedStorageClassName `
  -UsePersistence $usePersistence `
  -RuntimeDirectory $runtimeRoot

Write-Host "Adding the prometheus-community Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts | Out-Null
Assert-LastExitCode -Operation "Adding the prometheus-community Helm repository"
helm repo update | Out-Null
Assert-LastExitCode -Operation "Updating the prometheus-community Helm repository"

Write-Host "Installing kube-prometheus-stack into namespace '$Namespace'..."
helm upgrade --install $MonitoringRelease prometheus-community/kube-prometheus-stack `
  --namespace $Namespace `
  --create-namespace `
  --force-conflicts `
  --version $KubePrometheusStackChartVersion `
  --values $kubePrometheusValuesPath `
  --values $generatedKubePrometheusValuesPath
Assert-LastExitCode -Operation "Installing kube-prometheus-stack"

Write-Host "Installing Pushgateway into namespace '$Namespace'..."
helm upgrade --install $PushgatewayRelease prometheus-community/prometheus-pushgateway `
  --namespace $Namespace `
  --create-namespace `
  --force-conflicts `
  --version $PushgatewayChartVersion `
  --values $pushgatewayValuesPath
Assert-LastExitCode -Operation "Installing Pushgateway"

Write-Host "Applying dashboard ConfigMaps and the Pushgateway ServiceMonitor..."
kubectl apply -k $monitoringRoot | Out-Null
Assert-LastExitCode -Operation "Applying dashboard ConfigMaps and the Pushgateway ServiceMonitor"

Wait-ForNamespaceReadiness -TargetNamespace $Namespace

$grafanaSecretName = kubectl get secret -n $Namespace `
  -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$MonitoringRelease" `
  -o jsonpath="{.items[0].metadata.name}"

if (-not $grafanaSecretName) {
  throw "Could not find the Grafana secret in namespace '$Namespace'."
}

$adminUserB64 = kubectl get secret $grafanaSecretName -n $Namespace -o jsonpath="{.data.admin-user}"
$adminPasswordB64 = kubectl get secret $grafanaSecretName -n $Namespace -o jsonpath="{.data.admin-password}"

$adminUser = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($adminUserB64))
$adminPassword = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($adminPasswordB64))

Write-Host ""
Write-Host "Monitoring stack installation completed."
Write-Host "Namespace: $Namespace"
if ($usePersistence) {
  Write-Host "StorageClass for Prometheus and Grafana PVCs: $resolvedStorageClassName"
}
else {
  Write-Host "Persistence mode: disabled (Grafana and Prometheus are using ephemeral storage)"
}
Write-Host "Grafana admin user: $adminUser"
Write-Host "Grafana admin password: $adminPassword"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. npm run monitoring:port-forward"
Write-Host "  2. Open http://127.0.0.1:3000"
Write-Host "  3. Run one of:"
Write-Host "       npm run load:test:low"
Write-Host "       npm run load:test:medium"
Write-Host "       npm run load:test:peak"

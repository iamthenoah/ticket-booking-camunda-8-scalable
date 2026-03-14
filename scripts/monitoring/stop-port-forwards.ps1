[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$runtimeDirectory = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path ".k8s\monitoring\.runtime"

function Remove-FileIfPossible {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return
  }

  $attempts = 0
  while ($attempts -lt 5) {
    try {
      Remove-Item $Path -Force -ErrorAction Stop
      return
    }
    catch {
      $attempts++
      Start-Sleep -Milliseconds 500
    }
  }

  Write-Warning "Could not remove '$Path'. It may still be locked by the OS. You can delete it manually later."
}

if (-not (Test-Path $runtimeDirectory)) {
  Write-Host "No monitoring port-forward runtime directory found."
  return
}

Get-ChildItem -Path $runtimeDirectory -Filter "*.json" | ForEach-Object {
  $state = Get-Content $_.FullName | ConvertFrom-Json

  if ($state.pid) {
    $process = Get-Process -Id $state.pid -ErrorAction SilentlyContinue
    if ($process) {
      Stop-Process -Id $state.pid -Force
      $process.WaitForExit()
      Write-Host "Stopped port-forward process $($state.pid) for $($state.service)."
    }
  }

  Remove-FileIfPossible -Path $_.FullName
}

Get-ChildItem -Path $runtimeDirectory -Filter "*.log" -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-FileIfPossible -Path $_.FullName
}

Write-Host "Monitoring port-forwards stopped."

#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Diagnostics,
    [switch]$SkipLiveProbes,
    [string]$Language = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$guiScript = Join-Path $repoRoot "scripts\start_gui.ps1"
if (-not (Test-Path -LiteralPath $guiScript)) {
    throw "WinQStep GUI script was not found: $guiScript"
}

$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $guiScript
)
if ($Diagnostics) {
    $arguments += "-Diagnostics"
}
if ($SkipLiveProbes) {
    $arguments += "-SkipLiveProbes"
}
if (-not [string]::IsNullOrWhiteSpace($Language)) {
    $arguments += @("-Language", $Language)
}

& powershell @arguments
exit $LASTEXITCODE

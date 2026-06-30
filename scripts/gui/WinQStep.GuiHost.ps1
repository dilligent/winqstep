function Set-WinQStepUtf8Encoding {
    if (-not (Get-Variable -Scope Script -Name Utf8NoBomEncoding -ErrorAction SilentlyContinue)) {
        $Script:Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
    }
    [Console]::InputEncoding = $Script:Utf8NoBomEncoding
    [Console]::OutputEncoding = $Script:Utf8NoBomEncoding
    $global:OutputEncoding = $Script:Utf8NoBomEncoding
    $env:PYTHONIOENCODING = "utf-8"
    $env:PYTHONUTF8 = "1"
}

Set-WinQStepUtf8Encoding

function Resolve-WinQStepPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return [System.IO.Path]::GetFullPath((Join-Path $Script:RepoRoot $RelativePath))
}

function Read-WinQStepConfigLanguage {
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    try {
        if (-not [System.IO.File]::Exists($ConfigPath)) {
            return ""
        }
        $payload = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $property = $payload.PSObject.Properties["ui_language"]
        if ($null -eq $property) {
            return ""
        }
        return [string]$property.Value
    }
    catch {
        return ""
    }
}

function Resolve-WinQStepLanguage {
    param([string]$Language)

    $candidate = $Language
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    }
    $candidate = $candidate.Trim()
    if ($candidate -match "^zh") {
        return "zh-CN"
    }
    return "en-US"
}

function Read-WinQStepLocalizationFile {
    param([Parameter(Mandatory = $true)][string]$Language)

    $path = Resolve-WinQStepPath "resources\i18n\$Language.json"
    if (-not [System.IO.File]::Exists($path)) {
        throw "Localization resource was not found: $path"
    }
    $payload = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $strings = @{}
    foreach ($property in $payload.PSObject.Properties) {
        $strings[$property.Name] = [string]$property.Value
    }
    return $strings
}

function Initialize-WinQStepLocalization {
    param([string]$Language)

    $resolvedLanguage = Resolve-WinQStepLanguage $Language
    $strings = Read-WinQStepLocalizationFile "en-US"
    if ($resolvedLanguage -ne "en-US") {
        $localized = Read-WinQStepLocalizationFile $resolvedLanguage
        foreach ($key in $localized.Keys) {
            $strings[$key] = $localized[$key]
        }
    }

    $Script:WinQStepLocalization = [ordered]@{
        language = $resolvedLanguage
        requested_language = $Language
        strings = $strings
    }
    return $Script:WinQStepLocalization
}

function Get-WinQStepLanguage {
    if ($null -eq (Get-Variable -Scope Script -Name WinQStepLocalization -ErrorAction SilentlyContinue)) {
        return ""
    }
    return [string]$Script:WinQStepLocalization.language
}

function Get-WinQStepText {
    param([Parameter(Mandatory = $true)][string]$Key)

    if ($null -eq (Get-Variable -Scope Script -Name WinQStepLocalization -ErrorAction SilentlyContinue)) {
        return $Key
    }
    $strings = $Script:WinQStepLocalization.strings
    if ($strings.ContainsKey($Key)) {
        return [string]$strings[$Key]
    }
    return $Key
}

function Format-WinQStepText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )

    return [string]::Format(
        [System.Globalization.CultureInfo]::InvariantCulture,
        (Get-WinQStepText $Key),
        $Arguments
    )
}

function Set-WinQStepContent {
    param($Control, [Parameter(Mandatory = $true)][string]$Key)
    if ($null -ne $Control) {
        $Control.Content = Get-WinQStepText $Key
    }
}

function Set-WinQStepHeader {
    param($Control, [Parameter(Mandatory = $true)][string]$Key)
    if ($null -ne $Control) {
        $Control.Header = Get-WinQStepText $Key
    }
}

function Set-WinQStepText {
    param($Control, [Parameter(Mandatory = $true)][string]$Key)
    if ($null -ne $Control) {
        $Control.Text = Get-WinQStepText $Key
    }
}

function Add-WinQStepWpfAssemblies {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
}

function Test-WinQStepGuiPrerequisites {
    Add-WinQStepWpfAssemblies
    $python = Get-Command $Script:PythonCommand -ErrorAction SilentlyContinue
    if ($null -eq $python) {
        throw "python was not found on PATH."
    }

    $requiredFiles = @(
        "WinQStep.cmd",
        "WinQStep.ps1",
        "launcher\WinQStep.Launcher.cs",
        "scripts\build_launcher.py",
        "scripts\check_startup.py",
        "scripts\build_release.py",
        "scripts\smoke_release_install.py",
        "scripts\run_checks.py",
        "scripts\release_candidate_walkthrough.py",
        "scripts\start_gui.ps1",
        "scripts\gui\WinQStep.GuiHost.ps1",
        "scripts\gui\WinQStep.GuiControls.ps1",
        "scripts\gui\WinQStep.xaml",
        "resources\i18n\en-US.json",
        "resources\i18n\zh-CN.json",
        "scripts\detect_environment.py",
        "scripts\import_structure.py",
        "scripts\run_workflow.py",
        "scripts\run_existing_input.py",
        "scripts\run_existing_input_batch.py",
        "scripts\manage_existing_input_batch.py",
        "scripts\list_job_history.py",
        "scripts\manage_config.py",
        "scripts\manage_template.py",
        "scripts\inspect_cp2k_data.py",
        "scripts\validate_job_inputs.py",
        "scripts\mark_job_cancelled.py",
        "examples\winqstep.config.example.json",
        "examples\templates\energy_pbe.example.json",
        "tests\fixtures\structures\water.xyz",
        "tests\fixtures\quickstep_energy.inp"
    )
    $missing = @(
        foreach ($relativePath in $requiredFiles) {
            $path = Resolve-WinQStepPath $relativePath
            if (-not (Test-Path -LiteralPath $path)) {
                $relativePath
            }
        }
    )
    if ($missing.Count -gt 0) {
        throw "Missing required file(s): $($missing -join ', ')"
    }

    return [ordered]@{
        wpf_available = $true
        python = $python.Source
        repo_root = $Script:RepoRoot
        checked_files = $requiredFiles
    }
}

function Invoke-WinQStepPython {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $python = Get-Command $Script:PythonCommand -ErrorAction Stop
    $argumentLine = (($Arguments | ForEach-Object { ConvertTo-WinQStepCommandLineArgument $_ }) -join " ")
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $python.Source
    $startInfo.Arguments = $argumentLine
    $startInfo.WorkingDirectory = $Script:RepoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $Script:Utf8NoBomEncoding
    $startInfo.StandardErrorEncoding = $Script:Utf8NoBomEncoding

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $exitCode = [int]$process.ExitCode
    }
    finally {
        $process.Dispose()
    }

    $stdoutText = $stdout.TrimEnd()
    $stderrText = $stderr.TrimEnd()
    $combined = (($stdoutText, $stderrText) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = $stdoutText
        Error = $stderrText
        CombinedOutput = $combined
    }
}

function Invoke-WinQStepStartupDiagnostics {
    param([bool]$SkipLive)

    $arguments = @(
        "scripts\check_startup.py",
        "--config", "examples\winqstep.config.example.json",
        "--compact"
    )
    if ($SkipLive) {
        $arguments += "--skip-live-probes"
    }
    return Invoke-WinQStepPython $arguments
}

function ConvertTo-WinQStepCommandLineArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }
    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $backslash = [char]92
    $quote = [char]34
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append($quote)
    $backslashCount = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq $backslash) {
            $backslashCount += 1
            continue
        }
        if ($character -eq $quote) {
            if ($backslashCount -gt 0) {
                [void]$builder.Append(([string]$backslash) * ($backslashCount * 2))
            }
            [void]$builder.Append([string]$backslash)
            [void]$builder.Append($quote)
            $backslashCount = 0
            continue
        }
        if ($backslashCount -gt 0) {
            [void]$builder.Append(([string]$backslash) * $backslashCount)
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashCount -gt 0) {
        [void]$builder.Append(([string]$backslash) * ($backslashCount * 2))
    }
    [void]$builder.Append($quote)
    return $builder.ToString()
}

function Start-WinQStepPythonProcess {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$StdoutPath,
        [Parameter(Mandatory = $true)][string]$StderrPath
    )

    $python = Get-Command $Script:PythonCommand -ErrorAction Stop
    $argumentLine = (($Arguments | ForEach-Object { ConvertTo-WinQStepCommandLineArgument $_ }) -join " ")
    $stdoutParent = Split-Path -Parent $StdoutPath
    $stderrParent = Split-Path -Parent $StderrPath
    if (-not [string]::IsNullOrWhiteSpace($stdoutParent)) {
        [System.IO.Directory]::CreateDirectory($stdoutParent) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($stderrParent)) {
        [System.IO.Directory]::CreateDirectory($stderrParent) | Out-Null
    }
    [System.IO.File]::WriteAllText($StdoutPath, "", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($StderrPath, "", $Script:Utf8NoBomEncoding)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $python.Source
    $startInfo.Arguments = $argumentLine
    $startInfo.WorkingDirectory = $Script:RepoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $Script:Utf8NoBomEncoding
    $startInfo.StandardErrorEncoding = $Script:Utf8NoBomEncoding

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    [void]$process.Start()
    return $process
}

function Save-WinQStepProcessOutput {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][string]$StdoutPath,
        [Parameter(Mandatory = $true)][string]$StderrPath
    )

    $stdout = ""
    $stderr = ""
    try {
        $stdout = $Process.StandardOutput.ReadToEnd()
    }
    catch {
        $stdout = ""
    }
    try {
        $stderr = $Process.StandardError.ReadToEnd()
    }
    catch {
        $stderr = ""
    }
    try {
        $Process.WaitForExit()
    }
    catch {
    }
    [System.IO.File]::WriteAllText($StdoutPath, $stdout, $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($StderrPath, $stderr, $Script:Utf8NoBomEncoding)
    return [pscustomobject]@{
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Stop-WinQStepProcessTree {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)

    if ($Process.HasExited) {
        return
    }

    $children = @()
    try {
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($Process.Id)")
    }
    catch {
        $children = @()
    }
    foreach ($child in $children) {
        try {
            $childProcess = [System.Diagnostics.Process]::GetProcessById([int]$child.ProcessId)
            Stop-WinQStepProcessTree $childProcess
        }
        catch {
            continue
        }
    }
    try {
        if (-not $Process.HasExited) {
            $Process.Kill()
        }
    }
    catch {
    }
}

function Read-WinQStepFileText {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.File]::Exists($Path)) {
        return ""
    }
    try {
        return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    }
    catch {
        return ""
    }
}

function Get-WinQStepFileTail {
    param([string]$Path, [int]$LineCount = 80)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.File]::Exists($Path)) {
        return ""
    }
    try {
        return ((Get-Content -LiteralPath $Path -Encoding UTF8 -Tail $LineCount -ErrorAction Stop) | Out-String).TrimEnd()
    }
    catch {
        return ""
    }
}

function Get-JsonResult {
    param([Parameter(Mandatory = $true)]$Result)
    if ($Result.ExitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Result.Output)) {
            throw $Result.Output
        }
        throw $Result.Error
    }
    try {
        return ($Result.Output | ConvertFrom-Json)
    }
    catch {
        if ($Result.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
            throw $Result.Error
        }
        $raw = [string]$Result.Output
        if (-not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
            $raw = (($raw, [string]$Result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
        }
        throw "Command did not return JSON. Raw output:`n$raw"
    }
}

function Format-Cp2kSummary {
    param([Parameter(Mandatory = $true)]$Metadata)
    if ($null -eq $Metadata.cp2k_output) {
        return ""
    }
    $summary = $Metadata.cp2k_output
    $warningCount = if ($null -eq $summary.warning_count) { "n/a" } else { [string]$summary.warning_count }
    $parts = @("CP2K summary: status=$($summary.status)", "warnings=$warningCount", "program_ended=$($summary.program_ended)")
    if ($null -ne $summary.PSObject.Properties["total_energy_hartree"] -and $null -ne $summary.total_energy_hartree) {
        $parts += "energy_hartree=$($summary.total_energy_hartree)"
    }
    if (
        $null -ne $summary.PSObject.Properties["forces"] -and
        $null -ne $summary.forces -and
        $null -ne $summary.forces.PSObject.Properties["total_atomic_force"] -and
        $null -ne $summary.forces.total_atomic_force
    ) {
        $unit = if ($null -ne $summary.forces.PSObject.Properties["unit"]) { [string]$summary.forces.unit } else { "" }
        $suffix = if ([string]::IsNullOrWhiteSpace($unit)) { "" } else { " $unit" }
        $parts += "total_atomic_force=$($summary.forces.total_atomic_force)$suffix"
    }
    return ($parts -join ", ")
}


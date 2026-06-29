#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [switch]$LifecycleSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:RepoRoot = Split-Path -Parent $PSScriptRoot
$Script:PythonCommand = "python"
$Script:Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)

function Set-WinQStepUtf8Encoding {
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
        "scripts\detect_environment.py",
        "scripts\import_structure.py",
        "scripts\run_workflow.py",
        "scripts\run_existing_input.py",
        "scripts\list_job_history.py",
        "scripts\manage_config.py",
        "scripts\manage_template.py",
        "scripts\inspect_cp2k_data.py",
        "scripts\mark_job_cancelled.py",
        "examples\winqstep.config.json",
        "examples\templates\energy_pbe.json",
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

    Push-Location $Script:RepoRoot
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $Script:PythonCommand @Arguments 2>&1
        $exitCode = if ($null -eq $global:LASTEXITCODE) { 0 } else { $global:LASTEXITCODE }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = (($output | Out-String).TrimEnd())
    }
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
        return ((Get-Content -LiteralPath $Path -Tail $LineCount -ErrorAction Stop) | Out-String).TrimEnd()
    }
    catch {
        return ""
    }
}

function Get-JsonResult {
    param([Parameter(Mandatory = $true)]$Result)
    if ($Result.ExitCode -ne 0) {
        throw $Result.Output
    }
    try {
        return ($Result.Output | ConvertFrom-Json)
    }
    catch {
        throw "Command did not return JSON. Raw output:`n$($Result.Output)"
    }
}

function Format-Cp2kSummary {
    param([Parameter(Mandatory = $true)]$Metadata)
    if ($null -eq $Metadata.cp2k_output) {
        return ""
    }
    $summary = $Metadata.cp2k_output
    $warningCount = if ($null -eq $summary.warning_count) { "n/a" } else { [string]$summary.warning_count }
    return "CP2K summary: status=$($summary.status), warnings=$warningCount, program_ended=$($summary.program_ended)"
}

function New-WinQStepWindow {
    Add-WinQStepWpfAssemblies

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinQStep" Height="760" Width="1120" MinHeight="620" MinWidth="900"
        Background="#F5F7FA" FontFamily="Segoe UI, Microsoft YaHei UI, Microsoft YaHei" WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style TargetType="TextBox">
      <Setter Property="Margin" Value="6,4"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Margin" Value="6,4"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="MinWidth" Value="90"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" Text="WinQStep" FontSize="22" FontWeight="SemiBold" Margin="0,4,16,4"/>
      <WrapPanel x:Name="ActionButtonPanel" Grid.Column="1" HorizontalAlignment="Right">
        <Button x:Name="LoadConfigButton" Content="Load Config"/>
        <Button x:Name="SaveConfigButton" Content="Save Config"/>
        <Button x:Name="LoadTemplateButton" Content="Load Template"/>
        <Button x:Name="SaveTemplateButton" Content="Save Template"/>
        <Button x:Name="InspectDataButton" Content="Inspect Data"/>
        <Button x:Name="DetectButton" Content="Detect"/>
        <Button x:Name="ImportButton" Content="Import"/>
        <Button x:Name="PreviewButton" Content="Preview"/>
        <Button x:Name="RunButton" Content="Run"/>
        <Button x:Name="CancelJobButton" Content="Stop"/>
        <Button x:Name="HistoryButton" Content="History"/>
        <Button x:Name="ClearButton" Content="Clear"/>
      </WrapPanel>
    </Grid>

    <GroupBox Grid.Row="1" Header="Job Inputs" Padding="10" Margin="0,10,0,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="110"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Mode"/>
        <StackPanel Grid.Row="0" Grid.Column="1" Orientation="Horizontal" Margin="6,4">
          <RadioButton x:Name="WorkflowModeRadio" Content="Workflow" GroupName="JobMode" IsChecked="True" Margin="0,0,18,0"/>
          <RadioButton x:Name="ExistingInputModeRadio" Content="Existing input" GroupName="JobMode"/>
        </StackPanel>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="Config"/>
        <TextBox x:Name="ConfigPathBox" Grid.Row="1" Grid.Column="1"/>
        <Button x:Name="BrowseConfigButton" Grid.Row="1" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="Template"/>
        <TextBox x:Name="TemplatePathBox" Grid.Row="2" Grid.Column="1"/>
        <Button x:Name="BrowseTemplateButton" Grid.Row="2" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="3" Grid.Column="0" Text="Structure"/>
        <TextBox x:Name="StructurePathBox" Grid.Row="3" Grid.Column="1"/>
        <Button x:Name="BrowseStructureButton" Grid.Row="3" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="4" Grid.Column="0" Text="Existing Input"/>
        <TextBox x:Name="ExistingInputPathBox" Grid.Row="4" Grid.Column="1"/>
        <Button x:Name="BrowseExistingInputButton" Grid.Row="4" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="5" Grid.Column="0" Text="Job Folder"/>
        <TextBox x:Name="JobDirBox" Grid.Row="5" Grid.Column="1"/>
        <Button x:Name="BrowseJobDirButton" Grid.Row="5" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="6" Grid.Column="0" Text="Project"/>
        <TextBox x:Name="ProjectNameBox" Grid.Row="6" Grid.Column="1"/>
      </Grid>
    </GroupBox>

    <TabControl Grid.Row="2">
      <TabItem Header="Config">
        <Grid Margin="8">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="160"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <TextBlock Grid.Row="0" Grid.Column="0" Text="Distro"/>
          <TextBox x:Name="DistroBox" Grid.Row="0" Grid.Column="1"/>

          <TextBlock Grid.Row="1" Grid.Column="0" Text="CP2K Command"/>
          <TextBox x:Name="Cp2kCommandBox" Grid.Row="1" Grid.Column="1"/>

          <TextBlock Grid.Row="2" Grid.Column="0" Text="CP2K Data Dir"/>
          <TextBox x:Name="Cp2kDataDirBox" Grid.Row="2" Grid.Column="1"/>

          <TextBlock Grid.Row="3" Grid.Column="0" Text="MPI Command"/>
          <TextBox x:Name="MpirunCommandBox" Grid.Row="3" Grid.Column="1"/>

          <TextBlock Grid.Row="4" Grid.Column="0" Text="Workspace"/>
          <TextBox x:Name="DefaultWorkspaceBox" Grid.Row="4" Grid.Column="1"/>

          <TextBlock Grid.Row="5" Grid.Column="0" Text="WSL Prelude"/>
          <TextBox x:Name="WslPreludeBox" Grid.Row="5" Grid.Column="1" Height="64"
                   AcceptsReturn="True" TextWrapping="NoWrap" VerticalContentAlignment="Top"
                   HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>

          <TextBlock Grid.Row="6" Grid.Column="0" Text="Timeout"/>
          <TextBox x:Name="TimeoutBox" Grid.Row="6" Grid.Column="1"/>

          <TextBox x:Name="ConfigValidationText" Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2"
                   FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun"
                   FontSize="12" AcceptsReturn="True" TextWrapping="Wrap"
                   HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"
                   IsReadOnly="True"/>
        </Grid>
      </TabItem>
      <TabItem Header="Template">
        <Grid Margin="8">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="150"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="150"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="130"/>
            <RowDefinition Height="90"/>
          </Grid.RowDefinitions>

          <TextBlock Grid.Row="0" Grid.Column="0" Text="Project"/>
          <TextBox x:Name="TemplateProjectBox" Grid.Row="0" Grid.Column="1"/>
          <TextBlock Grid.Row="0" Grid.Column="2" Text="Run Type"/>
          <TextBox x:Name="TemplateRunTypeBox" Grid.Row="0" Grid.Column="3"/>

          <TextBlock Grid.Row="1" Grid.Column="0" Text="Basis File"/>
          <TextBox x:Name="BasisSetFileBox" Grid.Row="1" Grid.Column="1"/>
          <TextBlock Grid.Row="1" Grid.Column="2" Text="Potential File"/>
          <TextBox x:Name="PotentialFileBox" Grid.Row="1" Grid.Column="3"/>

          <TextBlock Grid.Row="2" Grid.Column="0" Text="XC Functional"/>
          <TextBox x:Name="XcFunctionalBox" Grid.Row="2" Grid.Column="1"/>
          <TextBlock Grid.Row="2" Grid.Column="2" Text="EPS SCF"/>
          <TextBox x:Name="EpsScfBox" Grid.Row="2" Grid.Column="3"/>

          <TextBlock Grid.Row="3" Grid.Column="0" Text="Charge"/>
          <TextBox x:Name="ChargeBox" Grid.Row="3" Grid.Column="1"/>
          <TextBlock Grid.Row="3" Grid.Column="2" Text="Multiplicity"/>
          <TextBox x:Name="MultiplicityBox" Grid.Row="3" Grid.Column="3"/>

          <TextBlock Grid.Row="4" Grid.Column="0" Text="Cutoff"/>
          <TextBox x:Name="CutoffBox" Grid.Row="4" Grid.Column="1"/>
          <TextBlock Grid.Row="4" Grid.Column="2" Text="Rel Cutoff"/>
          <TextBox x:Name="RelCutoffBox" Grid.Row="4" Grid.Column="3"/>

          <TextBlock Grid.Row="5" Grid.Column="0" Text="Max SCF"/>
          <TextBox x:Name="MaxScfBox" Grid.Row="5" Grid.Column="1"/>
          <TextBlock Grid.Row="5" Grid.Column="2" Text="Optimizer"/>
          <TextBox x:Name="GeoOptimizerBox" Grid.Row="5" Grid.Column="3"/>

          <TextBlock Grid.Row="6" Grid.Column="0" Text="GEO Max Iter"/>
          <TextBox x:Name="GeoMaxIterBox" Grid.Row="6" Grid.Column="1"/>

          <TextBox x:Name="KindsText" Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="4"
                   FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun"
                   FontSize="12" AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                   HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>

          <DataGrid x:Name="DataLabelsGrid" Grid.Row="8" Grid.Column="0" Grid.ColumnSpan="4"
                    AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single"
                    HeadersVisibility="Column" GridLinesVisibility="Horizontal" FontSize="12">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Element" Binding="{Binding element}" Width="70"/>
              <DataGridTextColumn Header="Basis Sets" Binding="{Binding basis_sets}" Width="*"/>
              <DataGridTextColumn Header="Potentials" Binding="{Binding potentials}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>

          <TextBox x:Name="TemplateValidationText" Grid.Row="9" Grid.Column="0" Grid.ColumnSpan="4"
                   FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun"
                   FontSize="12" AcceptsReturn="True" TextWrapping="Wrap"
                   HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"
                   IsReadOnly="True"/>
        </Grid>
      </TabItem>
      <TabItem Header="Environment">
        <TextBox x:Name="EnvironmentText" FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Structure">
        <TextBox x:Name="StructureText" FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Input Preview">
        <TextBox x:Name="PreviewText" FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Job Log">
        <TextBox x:Name="LogText" FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="Wrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Artifacts">
        <Grid Margin="8">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="120"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <WrapPanel Grid.Row="0" Margin="0,0,0,6">
            <Button x:Name="ViewInputButton" Content="Input"/>
            <Button x:Name="ViewOutputButton" Content="Output"/>
            <Button x:Name="ViewMetadataButton" Content="Metadata"/>
            <Button x:Name="ViewStdoutButton" Content="Stdout"/>
            <Button x:Name="ViewStderrButton" Content="Stderr"/>
          </WrapPanel>
          <TextBox x:Name="ArtifactSummaryText" Grid.Row="1"
                   FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun"
                   FontSize="12" AcceptsReturn="True" TextWrapping="Wrap"
                   HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"
                   IsReadOnly="True"/>
          <TextBox x:Name="ArtifactText" Grid.Row="2"
                   FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun"
                   FontSize="12" AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                   HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"
                   IsReadOnly="True"/>
        </Grid>
      </TabItem>
      <TabItem Header="History">
        <DataGrid x:Name="HistoryGrid" AutoGenerateColumns="False" IsReadOnly="True"
                  SelectionMode="Single" HeadersVisibility="Column" GridLinesVisibility="Horizontal"
                  FontSize="12">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Completed" Binding="{Binding completed_at}" Width="155"/>
            <DataGridTextColumn Header="Mode" Binding="{Binding mode}" Width="115"/>
            <DataGridTextColumn Header="Status" Binding="{Binding status}" Width="90"/>
            <DataGridTextColumn Header="Code" Binding="{Binding returncode}" Width="55"/>
            <DataGridTextColumn Header="Warnings" Binding="{Binding warning_count}" Width="75"/>
            <DataGridTextColumn Header="Project/Input" Binding="{Binding project_name}" Width="160"/>
            <DataGridTextColumn Header="Output" Binding="{Binding output_path}" Width="*"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
    </TabControl>

    <StatusBar Grid.Row="3" Margin="0,10,0,0">
      <StatusBarItem>
        <TextBlock x:Name="StatusText" Text="Ready"/>
      </StatusBarItem>
      <Separator/>
      <StatusBarItem HorizontalAlignment="Stretch">
        <TextBlock x:Name="JobStatusText" Text="" TextTrimming="CharacterEllipsis"/>
      </StatusBarItem>
    </StatusBar>
  </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $controls = @{}
    $names = @(
        "WorkflowModeRadio", "ExistingInputModeRadio",
        "ConfigPathBox", "TemplatePathBox", "StructurePathBox", "ExistingInputPathBox",
        "JobDirBox", "ProjectNameBox",
        "DistroBox", "Cp2kCommandBox", "Cp2kDataDirBox", "MpirunCommandBox",
        "DefaultWorkspaceBox", "WslPreludeBox", "TimeoutBox", "ConfigValidationText",
        "TemplateProjectBox", "TemplateRunTypeBox", "BasisSetFileBox", "PotentialFileBox",
        "XcFunctionalBox", "ChargeBox", "MultiplicityBox", "CutoffBox", "RelCutoffBox",
        "EpsScfBox", "MaxScfBox", "GeoOptimizerBox", "GeoMaxIterBox", "KindsText",
        "DataLabelsGrid", "TemplateValidationText",
        "EnvironmentText", "StructureText", "PreviewText", "LogText",
        "ArtifactSummaryText", "ArtifactText", "HistoryGrid", "StatusText", "JobStatusText",
        "LoadConfigButton", "SaveConfigButton", "LoadTemplateButton", "SaveTemplateButton",
        "InspectDataButton", "DetectButton", "ImportButton",
        "PreviewButton", "RunButton", "CancelJobButton", "HistoryButton", "ClearButton",
        "ViewInputButton", "ViewOutputButton", "ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton",
        "BrowseConfigButton", "BrowseTemplateButton", "BrowseStructureButton",
        "BrowseExistingInputButton", "BrowseJobDirButton"
    )
    foreach ($name in $names) {
        $controls[$name] = $window.FindName($name)
    }

    $controls["ConfigPathBox"].Text = Resolve-WinQStepPath "examples\winqstep.config.json"
    $controls["TemplatePathBox"].Text = Resolve-WinQStepPath "examples\templates\energy_pbe.json"
    $controls["StructurePathBox"].Text = Resolve-WinQStepPath "tests\fixtures\structures\water.xyz"
    $controls["ExistingInputPathBox"].Text = Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"
    $controls["JobDirBox"].Text = Resolve-WinQStepPath "outputs\gui-preview"
    $controls["ProjectNameBox"].Text = "gui_preview"
    $controls["CancelJobButton"].IsEnabled = $false

    $artifactButtons = @{
        input = $controls["ViewInputButton"]
        output = $controls["ViewOutputButton"]
        metadata = $controls["ViewMetadataButton"]
        stdout = $controls["ViewStdoutButton"]
        stderr = $controls["ViewStderrButton"]
    }

    $actionButtons = @(
        $controls["LoadConfigButton"], $controls["SaveConfigButton"],
        $controls["LoadTemplateButton"], $controls["SaveTemplateButton"],
        $controls["InspectDataButton"], $controls["DetectButton"], $controls["ImportButton"],
        $controls["PreviewButton"], $controls["RunButton"],
        $controls["HistoryButton"], $controls["ClearButton"],
        $controls["ViewInputButton"], $controls["ViewOutputButton"], $controls["ViewMetadataButton"],
        $controls["ViewStdoutButton"], $controls["ViewStderrButton"], $controls["BrowseConfigButton"],
        $controls["BrowseTemplateButton"], $controls["BrowseStructureButton"],
        $controls["BrowseExistingInputButton"], $controls["BrowseJobDirButton"]
    )

    $TestIsExistingInputMode = {
        return [bool]$controls["ExistingInputModeRadio"].IsChecked
    }.GetNewClosure()

    $UpdateModeControls = {
        $isExistingInputMode = & $TestIsExistingInputMode
        foreach ($name in @("TemplatePathBox", "BrowseTemplateButton", "StructurePathBox", "BrowseStructureButton", "ProjectNameBox")) {
            $controls[$name].IsEnabled = -not $isExistingInputMode
        }
        foreach ($name in @("ExistingInputPathBox", "BrowseExistingInputButton")) {
            $controls[$name].IsEnabled = $isExistingInputMode
        }
        $controls["ImportButton"].IsEnabled = -not $isExistingInputMode
    }.GetNewClosure()

    $SetBusy = {
        param([bool]$IsBusy, [string]$Status)
        $controls["StatusText"].Text = $Status
        foreach ($button in $actionButtons) {
            $button.IsEnabled = -not $IsBusy
        }
        $window.Cursor = if ($IsBusy) { [System.Windows.Input.Cursors]::Wait } else { $null }
        if (-not $IsBusy) {
            & $UpdateModeControls
            & $UpdateArtifactControls
        }
        [System.Windows.Forms.Application]::DoEvents()
    }.GetNewClosure()

    $AppendLog = {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($controls["LogText"].Text)) {
            $controls["LogText"].Text = $Text
        }
        else {
            $controls["LogText"].AppendText("`r`n$Text")
        }
        $controls["LogText"].ScrollToEnd()
    }.GetNewClosure()

    $InvokeGuiAction = {
        param([string]$Status, [scriptblock]$Action)
        & $SetBusy $true $Status
        try {
            & $Action
        }
        catch {
            $message = $_.Exception.Message
            & $AppendLog "ERROR: $message"
            [System.Windows.MessageBox]::Show($window, $message, "WinQStep", "OK", "Error") | Out-Null
        }
        finally {
            & $SetBusy $false "Ready"
        }
    }.GetNewClosure()

    $SelectFilePath = {
        param([Parameter(Mandatory = $true)]$TextBox, [Parameter(Mandatory = $true)][string]$Filter)
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Filter = $Filter
        if ([System.IO.File]::Exists($TextBox.Text)) {
            $dialog.InitialDirectory = Split-Path -Parent $TextBox.Text
        }
        if ($dialog.ShowDialog($window)) {
            $TextBox.Text = $dialog.FileName
        }
    }.GetNewClosure()

    $SelectFolderPath = {
        param([Parameter(Mandatory = $true)]$TextBox)
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ([System.IO.Directory]::Exists($TextBox.Text)) {
            $dialog.SelectedPath = $TextBox.Text
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $TextBox.Text = $dialog.SelectedPath
        }
    }.GetNewClosure()

    $GetWorkflowArguments = {
        param([bool]$PrepareOnly)
        $arguments = @(
            "scripts\run_workflow.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--template", $controls["TemplatePathBox"].Text,
            "--structure", $controls["StructurePathBox"].Text,
            "--job-dir", $controls["JobDirBox"].Text,
            "--project-name", $controls["ProjectNameBox"].Text
        )
        if ($PrepareOnly) {
            $arguments += "--prepare-only"
        }
        return $arguments
    }.GetNewClosure()

    $GetExistingInputArguments = {
        param([bool]$PrepareOnly)
        $arguments = @(
            "scripts\run_existing_input.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--input", $controls["ExistingInputPathBox"].Text,
            "--job-dir", $controls["JobDirBox"].Text
        )
        if ($PrepareOnly) {
            $arguments += "--prepare-only"
        }
        return $arguments
    }.GetNewClosure()

    $GetActiveJobArguments = {
        param([bool]$PrepareOnly)
        if (& $TestIsExistingInputMode) {
            return (& $GetExistingInputArguments $PrepareOnly)
        }
        return (& $GetWorkflowArguments $PrepareOnly)
    }.GetNewClosure()

    $GetActiveInputPreviewPath = {
        param([Parameter(Mandatory = $true)]$Metadata)
        return [string]$Metadata.files.input.path
    }.GetNewClosure()

    $FormatLogWithSummary = {
        param([Parameter(Mandatory = $true)]$Metadata, [Parameter(Mandatory = $true)][string]$Output)
        $summaryText = Format-Cp2kSummary $Metadata
        if ([string]::IsNullOrWhiteSpace($summaryText)) {
            return $Output
        }
        return "$summaryText`r`n`r`n$Output"
    }.GetNewClosure()

    $jobState = @{ Current = $null }
    $artifactState = @{ Current = $null }
    $jobTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $jobTimer.Interval = [TimeSpan]::FromSeconds(1)

    $SetJobStatusText = {
        param([string]$Text)
        $controls["JobStatusText"].Text = $Text
        $controls["JobStatusText"].ToolTip = $Text
    }.GetNewClosure()

    $FormatRunningJobStatus = {
        param([Parameter(Mandatory = $true)][hashtable]$State)
        $process = [System.Diagnostics.Process]$State["Process"]
        return "Running PID $($process.Id) | job=$($State["JobDir"]) | output=$($State["OutputPath"])"
    }.GetNewClosure()

    $FormatFinishedJobStatus = {
        param([Parameter(Mandatory = $true)]$Metadata, [string]$FallbackStatus)
        $status = $FallbackStatus
        if ($null -ne $Metadata.PSObject.Properties["status"] -and $null -ne $Metadata.status) {
            $status = [string]$Metadata.status
        }
        $outputPath = ""
        if ($null -ne $Metadata.files -and $null -ne $Metadata.files.output -and $null -ne $Metadata.files.output.PSObject.Properties["path"]) {
            $outputPath = [string]$Metadata.files.output.path
        }
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            return "Last job: status=$status"
        }
        return "Last job: status=$status | output=$outputPath"
    }.GetNewClosure()

    $SetAsyncJobRunning = {
        param([bool]$IsRunning, [string]$Status)
        $controls["StatusText"].Text = $Status
        foreach ($button in $actionButtons) {
            $button.IsEnabled = -not $IsRunning
        }
        $controls["CancelJobButton"].IsEnabled = $IsRunning
        $window.Cursor = $null
        if (-not $IsRunning) {
            & $UpdateModeControls
            & $UpdateArtifactControls
        }
        else {
            foreach ($button in $artifactButtons.Values) {
                $button.IsEnabled = $false
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
    }.GetNewClosure()

    $AddTailSection = {
        param(
            [string[]]$Sections,
            [string]$Title,
            [string]$Path,
            [int]$LineCount = 80
        )
        $tail = Get-WinQStepFileTail $Path $LineCount
        if ([string]::IsNullOrWhiteSpace($tail)) {
            return $Sections
        }
        return @($Sections + "--- $Title ---`r`n$tail")
    }.GetNewClosure()

    $ReadMetadataFile = {
        param([string]$MetadataPath)
        $text = Read-WinQStepFileText $MetadataPath
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }
        try {
            return ($text | ConvertFrom-Json)
        }
        catch {
            return $null
        }
    }.GetNewClosure()

    $BuildAsyncJobLog = {
        param([Parameter(Mandatory = $true)][hashtable]$State)
        $process = [System.Diagnostics.Process]$State["Process"]
        $sections = @(
            "CP2K job running asynchronously.`r`nPID=$($process.Id)`r`njob_dir=$($State["JobDir"])`r`ninput=$($State["InputPath"])`r`noutput=$($State["OutputPath"])`r`nmetadata=$($State["MetadataPath"])`r`nwrapper_stdout=$($State["WrapperStdoutPath"])`r`nwrapper_stderr=$($State["WrapperStderrPath"])"
        )

        $metadata = & $ReadMetadataFile ([string]$State["MetadataPath"])
        if ($null -ne $metadata) {
            $summaryText = Format-Cp2kSummary $metadata
            if (-not [string]::IsNullOrWhiteSpace($summaryText)) {
                $sections += $summaryText
            }
            $sections += "metadata status=$($metadata.status), returncode=$($metadata.returncode)"
        }

        $sections = & $AddTailSection $sections "CP2K output tail" ([string]$State["OutputPath"]) 80
        $sections = & $AddTailSection $sections "CP2K stdout tail" ([string]$State["JobStdoutPath"]) 60
        $sections = & $AddTailSection $sections "CP2K stderr tail" ([string]$State["JobStderrPath"]) 60
        $sections = & $AddTailSection $sections "wrapper stderr tail" ([string]$State["WrapperStderrPath"]) 40
        return ($sections -join "`r`n`r`n")
    }.GetNewClosure()

    $AddMetadataTails = {
        param([string]$LogText, [Parameter(Mandatory = $true)]$Metadata)
        $sections = @($LogText)
        if ($null -ne $Metadata.files) {
            $sections = & $AddTailSection $sections "CP2K output tail" ([string]$Metadata.files.output.path) 80
            $sections = & $AddTailSection $sections "CP2K stdout tail" ([string]$Metadata.files.stdout.path) 60
            $sections = & $AddTailSection $sections "CP2K stderr tail" ([string]$Metadata.files.stderr.path) 60
        }
        return ($sections -join "`r`n`r`n")
    }.GetNewClosure()

    $CompleteAsyncJob = {
        param([Parameter(Mandatory = $true)][hashtable]$State)
        $jobTimer.Stop()
        $process = [System.Diagnostics.Process]$State["Process"]
        $process.Refresh()
        $exitCode = if ($process.HasExited) { [int]$process.ExitCode } else { $null }
        $captured = Save-WinQStepProcessOutput $process ([string]$State["WrapperStdoutPath"]) ([string]$State["WrapperStderrPath"])
        $stdout = [string]$captured.Stdout
        $stderr = [string]$captured.Stderr
        $metadata = $null
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            try {
                $metadata = ($stdout | ConvertFrom-Json)
            }
            catch {
                $metadata = $null
            }
        }

        if ([bool]$State["Cancelled"] -and [System.IO.File]::Exists([string]$State["MetadataPath"])) {
            $cancelArgs = @(
                "scripts\mark_job_cancelled.py",
                "--metadata", [string]$State["MetadataPath"],
                "--stdout-file", [string]$State["WrapperStdoutPath"],
                "--stderr-file", [string]$State["WrapperStderrPath"],
                "--compact"
            )
            if ($null -ne $exitCode) {
                $cancelArgs += @("--returncode", [string]$exitCode)
            }
            $cancelResult = Invoke-WinQStepPython $cancelArgs
            if ($cancelResult.ExitCode -eq 0) {
                $metadata = Get-JsonResult $cancelResult
            }
            else {
                $stderr = (($stderr, $cancelResult.Output) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
            }
        }

        if ($null -eq $metadata) {
            $metadata = & $ReadMetadataFile ([string]$State["MetadataPath"])
        }

        if ($null -ne $metadata) {
            $finalStatus = if ([bool]$State["Cancelled"]) { "Cancelled" } elseif ($exitCode -eq 0) { "Ready" } else { "Finished with errors" }
            $logText = & $FormatLogWithSummary $metadata $stdout
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                $logText = "$logText`r`n`r`n--- wrapper stderr ---`r`n$stderr"
            }
            $controls["LogText"].Text = & $AddMetadataTails $logText $metadata
            & $SetArtifactsFromMetadata $metadata
        }
        else {
            $parts = @("CP2K wrapper exited without JSON metadata. exit_code=$exitCode")
            if (-not [string]::IsNullOrWhiteSpace($stdout)) {
                $parts += "--- wrapper stdout ---`r`n$stdout"
            }
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                $parts += "--- wrapper stderr ---`r`n$stderr"
            }
            $controls["LogText"].Text = ($parts -join "`r`n`r`n")
            $finalStatus = if ([bool]$State["Cancelled"]) { "Cancelled" } else { "Finished with errors" }
            & $SetJobStatusText "Last job: status=$finalStatus | metadata=$($State["MetadataPath"])"
        }

        $controls["LogText"].ScrollToEnd()
        $jobState["Current"] = $null
        & $SetAsyncJobRunning $false $finalStatus
    }.GetNewClosure()

    $RefreshAsyncJob = {
        $current = $jobState["Current"]
        if ($null -eq $current) {
            $jobTimer.Stop()
            return
        }

        $process = [System.Diagnostics.Process]$current["Process"]
        if ($process.HasExited) {
            & $CompleteAsyncJob $current
            return
        }

        & $SetJobStatusText (& $FormatRunningJobStatus $current)
        $controls["LogText"].Text = & $BuildAsyncJobLog $current
        $controls["LogText"].ScrollToEnd()
    }.GetNewClosure()

    $jobTimer.Add_Tick({
        & $RefreshAsyncJob
    }.GetNewClosure())

    $GetJsonProperty = {
        param($Object, [Parameter(Mandatory = $true)][string]$Name, [string]$Default = "")
        if ($null -eq $Object) {
            return $Default
        }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property -or $null -eq $property.Value) {
            return $Default
        }
        return [string]$property.Value
    }.GetNewClosure()

    $GetNestedPath = {
        param($Object, [Parameter(Mandatory = $true)][string[]]$Names)
        $current = $Object
        foreach ($name in $Names) {
            if ($null -eq $current) {
                return ""
            }
            $property = $current.PSObject.Properties[$name]
            if ($null -eq $property -or $null -eq $property.Value) {
                return ""
            }
            $current = $property.Value
        }
        return [string]$current
    }.GetNewClosure()

    $GetMetadataFilePath = {
        param($Metadata, [Parameter(Mandatory = $true)][string]$Key)
        return (& $GetNestedPath $Metadata @("files", $Key, "path"))
    }.GetNewClosure()

    $BuildArtifactSummary = {
        param([Parameter(Mandatory = $true)][hashtable]$Artifacts)
        $lines = @(
            "status=$($Artifacts["status"])",
            "returncode=$($Artifacts["returncode"])",
            "cp2k_output=$($Artifacts["output_status"]), warnings=$($Artifacts["warning_count"]), program_ended=$($Artifacts["program_ended"])"
        )
        if (-not [string]::IsNullOrWhiteSpace([string]$Artifacts["ended_at"])) {
            $lines += "ended_at=$($Artifacts["ended_at"])"
        }
        foreach ($key in @("input", "output", "metadata", "stdout", "stderr")) {
            $path = [string]$Artifacts["paths"][$key]
            $exists = if (-not [string]::IsNullOrWhiteSpace($path) -and [System.IO.File]::Exists($path)) { "exists" } else { "missing" }
            $lines += "$key=[$exists] $path"
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $UpdateArtifactControls = {
        $current = $artifactState["Current"]
        foreach ($entry in $artifactButtons.GetEnumerator()) {
            $enabled = $false
            if ($null -ne $current -and $null -ne $current["paths"]) {
                $path = [string]$current["paths"][$entry.Key]
                $enabled = (-not [string]::IsNullOrWhiteSpace($path)) -and [System.IO.File]::Exists($path)
            }
            $entry.Value.IsEnabled = $enabled
        }
    }.GetNewClosure()

    $SetArtifactsFromMetadata = {
        param([Parameter(Mandatory = $true)]$Metadata)
        $summary = $Metadata.cp2k_output
        $artifacts = @{
            status = (& $GetJsonProperty $Metadata "status" "")
            returncode = (& $GetJsonProperty $Metadata "returncode" "")
            output_status = (& $GetJsonProperty $summary "status" "")
            warning_count = (& $GetJsonProperty $summary "warning_count" "")
            program_ended = (& $GetJsonProperty $summary "program_ended" "")
            ended_at = (& $GetJsonProperty $summary "ended_at" "")
            paths = @{
                input = (& $GetMetadataFilePath $Metadata "input")
                output = (& $GetMetadataFilePath $Metadata "output")
                metadata = (& $GetMetadataFilePath $Metadata "metadata")
                stdout = (& $GetMetadataFilePath $Metadata "stdout")
                stderr = (& $GetMetadataFilePath $Metadata "stderr")
            }
        }
        $artifactState["Current"] = $artifacts
        $controls["ArtifactSummaryText"].Text = & $BuildArtifactSummary $artifacts
        & $UpdateArtifactControls
        & $SetJobStatusText (& $FormatFinishedJobStatus $Metadata ([string]$artifacts["status"]))
    }.GetNewClosure()

    $SetArtifactsFromHistoryItem = {
        param([Parameter(Mandatory = $true)]$Item)
        $artifacts = @{
            status = (& $GetJsonProperty $Item "status" "")
            returncode = (& $GetJsonProperty $Item "returncode" "")
            output_status = (& $GetJsonProperty $Item "output_status" "")
            warning_count = (& $GetJsonProperty $Item "warning_count" "")
            program_ended = (& $GetJsonProperty $Item "program_ended" "")
            ended_at = ""
            paths = @{
                input = (& $GetJsonProperty $Item "input_path" "")
                output = (& $GetJsonProperty $Item "output_path" "")
                metadata = (& $GetJsonProperty $Item "metadata_path" "")
                stdout = (& $GetJsonProperty $Item "stdout_path" "")
                stderr = (& $GetJsonProperty $Item "stderr_path" "")
            }
        }
        $artifactState["Current"] = $artifacts
        $controls["ArtifactSummaryText"].Text = & $BuildArtifactSummary $artifacts
        & $UpdateArtifactControls
        & $SetJobStatusText "Selected job: status=$($artifacts["status"]) | output=$($artifacts["paths"]["output"])"
    }.GetNewClosure()

    $ReadMetadataArtifact = {
        param([string]$MetadataPath)
        if ([string]::IsNullOrWhiteSpace($MetadataPath) -or -not [System.IO.File]::Exists($MetadataPath)) {
            return $null
        }
        try {
            return ([System.IO.File]::ReadAllText($MetadataPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
        }
        catch {
            return $null
        }
    }.GetNewClosure()

    $ViewArtifact = {
        param([Parameter(Mandatory = $true)][string]$Key)
        $current = $artifactState["Current"]
        if ($null -eq $current -or $null -eq $current["paths"]) {
            throw "No job artifact is selected."
        }
        $path = [string]$current["paths"][$Key]
        if ([string]::IsNullOrWhiteSpace($path) -or -not [System.IO.File]::Exists($path)) {
            throw "Artifact is not available: $Key"
        }
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $controls["ArtifactText"].Text = "--- ${Key}: $path ---`r`n$text"
        if ($Key -in @("input", "output")) {
            $controls["PreviewText"].Text = $text
        }
        else {
            $controls["LogText"].Text = $text
        }
    }.GetNewClosure()

    $FormatConfigValidation = {
        param([Parameter(Mandatory = $true)]$Payload)
        $validation = $Payload.validation
        $lines = @()
        if ($null -ne $validation -and [bool]$validation.valid) {
            $lines += "Config valid"
        }
        else {
            $lines += "Config invalid"
        }
        if ($null -ne $validation -and $null -ne $validation.errors) {
            foreach ($errorText in @($validation.errors)) {
                $lines += "ERROR: $errorText"
            }
        }
        if ($null -ne $validation -and $null -ne $validation.warnings) {
            foreach ($warningText in @($validation.warnings)) {
                $lines += "WARNING: $warningText"
            }
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $SetConfigFieldsFromPayload = {
        param([Parameter(Mandatory = $true)]$Payload)
        $config = $Payload.config
        $controls["DistroBox"].Text = & $GetJsonProperty $config "distro"
        $controls["Cp2kCommandBox"].Text = & $GetJsonProperty $config "cp2k_command"
        $controls["Cp2kDataDirBox"].Text = & $GetJsonProperty $config "cp2k_data_dir"
        $controls["MpirunCommandBox"].Text = & $GetJsonProperty $config "mpirun_command"
        $controls["DefaultWorkspaceBox"].Text = & $GetJsonProperty $config "default_windows_workspace"
        $controls["WslPreludeBox"].Text = & $GetJsonProperty $config "wsl_shell_prelude"
        $controls["TimeoutBox"].Text = & $GetJsonProperty $config "timeout"
        $workspace = $controls["DefaultWorkspaceBox"].Text
        if (-not [string]::IsNullOrWhiteSpace($workspace)) {
            $controls["JobDirBox"].Text = $workspace
        }
        $controls["ConfigValidationText"].Text = & $FormatConfigValidation $Payload
    }.GetNewClosure()

    $ReadConfigManagerResult = {
        param([Parameter(Mandatory = $true)]$Result)
        try {
            $payload = $Result.Output | ConvertFrom-Json
        }
        catch {
            throw "Command did not return JSON. Raw output:`n$($Result.Output)"
        }
        if ($null -ne $payload.config) {
            & $SetConfigFieldsFromPayload $payload
        }
        if ($Result.ExitCode -ne 0) {
            throw (& $FormatConfigValidation $payload)
        }
        return $payload
    }.GetNewClosure()

    $GetConfigFieldsJson = {
        $fields = [ordered]@{
            distro = $controls["DistroBox"].Text
            cp2k_command = $controls["Cp2kCommandBox"].Text
            mpirun_command = $controls["MpirunCommandBox"].Text
            cp2k_data_dir = $controls["Cp2kDataDirBox"].Text
            default_windows_workspace = $controls["DefaultWorkspaceBox"].Text
            wsl_shell_prelude = $controls["WslPreludeBox"].Text
            timeout = $controls["TimeoutBox"].Text
        }
        return ($fields | ConvertTo-Json -Compress)
    }.GetNewClosure()

    $LoadConfigFields = {
        param([bool]$WriteLog)
        $result = Invoke-WinQStepPython @(
            "scripts\manage_config.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--compact"
        )
        $payload = & $ReadConfigManagerResult $result
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $SaveConfigFields = {
        param([bool]$RequireExecution, [bool]$WriteLog)
        $arguments = @(
            "scripts\manage_config.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--write",
            "--fields-json", (& $GetConfigFieldsJson),
            "--compact"
        )
        if ($RequireExecution) {
            $arguments += "--require-execution"
        }
        $result = Invoke-WinQStepPython $arguments
        $payload = & $ReadConfigManagerResult $result
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $FormatTemplateValidation = {
        param([Parameter(Mandatory = $true)]$Payload)
        $validation = $Payload.validation
        $lines = @()
        if ($null -ne $validation -and [bool]$validation.valid) {
            $lines += "Template valid"
        }
        else {
            $lines += "Template invalid"
        }
        if ($null -ne $validation -and $null -ne $validation.errors) {
            foreach ($errorText in @($validation.errors)) {
                $lines += "ERROR: $errorText"
            }
        }
        if ($null -ne $validation -and $null -ne $validation.warnings) {
            foreach ($warningText in @($validation.warnings)) {
                $lines += "WARNING: $warningText"
            }
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $SetTemplateFieldsFromPayload = {
        param([Parameter(Mandatory = $true)]$Payload)
        $template = $Payload.template
        $dft = $template.dft
        $geoOpt = $template.geo_opt
        $controls["TemplateProjectBox"].Text = & $GetJsonProperty $template "project_name"
        $controls["TemplateRunTypeBox"].Text = & $GetJsonProperty $template "run_type"
        $controls["BasisSetFileBox"].Text = & $GetJsonProperty $dft "basis_set_file_name"
        $controls["PotentialFileBox"].Text = & $GetJsonProperty $dft "potential_file_name"
        $controls["XcFunctionalBox"].Text = & $GetJsonProperty $dft "xc_functional"
        $controls["ChargeBox"].Text = & $GetJsonProperty $dft "charge"
        $controls["MultiplicityBox"].Text = & $GetJsonProperty $dft "multiplicity"
        $controls["CutoffBox"].Text = & $GetJsonProperty $dft "cutoff"
        $controls["RelCutoffBox"].Text = & $GetJsonProperty $dft "rel_cutoff"
        $controls["EpsScfBox"].Text = & $GetJsonProperty $dft "eps_scf"
        $controls["MaxScfBox"].Text = & $GetJsonProperty $dft "max_scf"
        $controls["GeoOptimizerBox"].Text = & $GetJsonProperty $geoOpt "optimizer"
        $controls["GeoMaxIterBox"].Text = & $GetJsonProperty $geoOpt "max_iter"
        $controls["KindsText"].Text = & $GetJsonProperty $Payload "kinds_text"
        $controls["TemplateValidationText"].Text = & $FormatTemplateValidation $Payload
    }.GetNewClosure()

    $ReadTemplateManagerResult = {
        param([Parameter(Mandatory = $true)]$Result)
        try {
            $payload = $Result.Output | ConvertFrom-Json
        }
        catch {
            throw "Command did not return JSON. Raw output:`n$($Result.Output)"
        }
        if ($null -ne $payload.template) {
            & $SetTemplateFieldsFromPayload $payload
        }
        if ($Result.ExitCode -ne 0) {
            throw (& $FormatTemplateValidation $payload)
        }
        return $payload
    }.GetNewClosure()

    $GetTemplateFieldsJson = {
        $fields = [ordered]@{
            project_name = $controls["TemplateProjectBox"].Text
            run_type = $controls["TemplateRunTypeBox"].Text
            basis_set_file_name = $controls["BasisSetFileBox"].Text
            potential_file_name = $controls["PotentialFileBox"].Text
            xc_functional = $controls["XcFunctionalBox"].Text
            charge = $controls["ChargeBox"].Text
            multiplicity = $controls["MultiplicityBox"].Text
            cutoff = $controls["CutoffBox"].Text
            rel_cutoff = $controls["RelCutoffBox"].Text
            eps_scf = $controls["EpsScfBox"].Text
            max_scf = $controls["MaxScfBox"].Text
            optimizer = $controls["GeoOptimizerBox"].Text
            geo_opt_max_iter = $controls["GeoMaxIterBox"].Text
            kinds_text = $controls["KindsText"].Text
        }
        return ($fields | ConvertTo-Json -Compress)
    }.GetNewClosure()

    $LoadTemplateFields = {
        param([bool]$WriteLog)
        $result = Invoke-WinQStepPython @(
            "scripts\manage_template.py",
            "--template", $controls["TemplatePathBox"].Text,
            "--compact"
        )
        $payload = & $ReadTemplateManagerResult $result
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $SaveTemplateFields = {
        param([bool]$WriteLog)
        $result = Invoke-WinQStepPython @(
            "scripts\manage_template.py",
            "--template", $controls["TemplatePathBox"].Text,
            "--write",
            "--fields-json", (& $GetTemplateFieldsJson),
            "--compact"
        )
        $payload = & $ReadTemplateManagerResult $result
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $GetDataInspectionCachePath = {
        $workspace = $controls["DefaultWorkspaceBox"].Text
        if ([string]::IsNullOrWhiteSpace($workspace)) {
            $workspace = $controls["JobDirBox"].Text
        }
        [System.IO.Directory]::CreateDirectory($workspace) | Out-Null
        return (Join-Path $workspace "cp2k-data.winqstep-cache.json")
    }.GetNewClosure()

    $SetDataLabelsFromPayload = {
        param([Parameter(Mandatory = $true)]$Payload)
        $rows = @()
        if ($null -ne $Payload.labels_by_element) {
            foreach ($property in @($Payload.labels_by_element.PSObject.Properties | Sort-Object Name)) {
                $value = $property.Value
                $rows += [pscustomobject]@{
                    element = $property.Name
                    basis_sets = (@($value.basis_sets) -join ", ")
                    potentials = (@($value.potentials) -join ", ")
                }
            }
        }
        $controls["DataLabelsGrid"].ItemsSource = $rows
        $cachePath = & $GetJsonProperty $Payload "cache_path"
        $controls["TemplateValidationText"].Text = "CP2K data labels: elements=$($rows.Count), files=$($Payload.counts.files)`r`ncache=$cachePath"
    }.GetNewClosure()

    $InspectCp2kData = {
        param([bool]$WriteLog)
        $null = & $SaveConfigFields $true $false
        $cachePath = & $GetDataInspectionCachePath
        $result = Invoke-WinQStepPython @(
            "scripts\inspect_cp2k_data.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--cache", $cachePath,
            "--compact"
        )
        $payload = Get-JsonResult $result
        & $SetDataLabelsFromPayload $payload
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $SelectPreferredLabel = {
        param([string]$Text, [string[]]$PreferredPatterns)
        $values = @(
            foreach ($value in ($Text -split ",")) {
                $trimmed = $value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                    $trimmed
                }
            }
        )
        foreach ($pattern in $PreferredPatterns) {
            $match = @($values | Where-Object { $_ -match $pattern } | Select-Object -First 1)
            if ($match.Count -gt 0) {
                return [string]$match[0]
            }
        }
        if ($values.Count -gt 0) {
            return [string]$values[0]
        }
        return ""
    }.GetNewClosure()

    $ApplySelectedDataLabel = {
        $item = $controls["DataLabelsGrid"].SelectedItem
        if ($null -eq $item) {
            return
        }
        $element = [string]$item.element
        $basis = & $SelectPreferredLabel ([string]$item.basis_sets) @("DZVP-MOLOPT-SR-GTH", "MOLOPT")
        $potential = & $SelectPreferredLabel ([string]$item.potentials) @("GTH-PBE-q", "GTH-PBE")
        if ([string]::IsNullOrWhiteSpace($element) -or [string]::IsNullOrWhiteSpace($basis) -or [string]::IsNullOrWhiteSpace($potential)) {
            return
        }
        $newLine = "$element $basis $potential"
        $updated = $false
        $lines = @()
        foreach ($line in @($controls["KindsText"].Text -split "`r?`n")) {
            if ($line.Trim() -match "^$([regex]::Escape($element))\s+") {
                $lines += $newLine
                $updated = $true
            }
            elseif (-not [string]::IsNullOrWhiteSpace($line)) {
                $lines += $line
            }
        }
        if (-not $updated) {
            $lines += $newLine
        }
        $controls["KindsText"].Text = ($lines -join "`r`n")
    }.GetNewClosure()

    $LoadHistory = {
        $result = Invoke-WinQStepPython @(
            "scripts\list_job_history.py",
            "--workspace", $controls["JobDirBox"].Text,
            "--compact"
        )
        $history = Get-JsonResult $result
        $jobs = @()
        if ($null -ne $history.jobs) {
            $jobs = @($history.jobs)
        }
        $errors = @()
        if ($null -ne $history.errors) {
            $errors = @($history.errors)
        }
        $controls["HistoryGrid"].ItemsSource = $jobs
        $controls["LogText"].Text = "History jobs: $($jobs.Count), errors: $($errors.Count)`r`n`r`n$($result.Output)"
    }.GetNewClosure()

    $OpenSelectedHistory = {
        $item = $controls["HistoryGrid"].SelectedItem
        if ($null -eq $item) {
            return
        }

        & $SetArtifactsFromHistoryItem $item
        $metadataPath = [string]$item.metadata_path
        if (-not [string]::IsNullOrWhiteSpace($metadataPath) -and [System.IO.File]::Exists($metadataPath)) {
            $controls["LogText"].Text = [System.IO.File]::ReadAllText($metadataPath, [System.Text.Encoding]::UTF8)
            $metadata = & $ReadMetadataArtifact $metadataPath
            if ($null -ne $metadata) {
                & $SetArtifactsFromMetadata $metadata
            }
        }
        else {
            $controls["LogText"].Text = "Metadata file was not found: $metadataPath"
        }

        $outputPath = [string]$item.output_path
        if (-not [string]::IsNullOrWhiteSpace($outputPath) -and [System.IO.File]::Exists($outputPath)) {
            $controls["PreviewText"].Text = [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::UTF8)
        }
        else {
            $controls["PreviewText"].Text = "CP2K output was not found: $outputPath"
        }
    }.GetNewClosure()

    $StartAsyncJob = {
        if ($null -ne $jobState["Current"]) {
            & $AppendLog "A CP2K job is already running."
            return
        }

        & $SetBusy $true "Preparing CP2K job"
        try {
            $null = & $SaveConfigFields $true $false
            if (-not (& $TestIsExistingInputMode)) {
                $null = & $SaveTemplateFields $false
            }

            $prepareArguments = @(& $GetActiveJobArguments $true)
            $prepareArguments += "--compact"
            $prepareResult = Invoke-WinQStepPython $prepareArguments
            $preparedMetadata = Get-JsonResult $prepareResult
            $inputPath = & $GetActiveInputPreviewPath $preparedMetadata
            if ([System.IO.File]::Exists($inputPath)) {
                $controls["PreviewText"].Text = [System.IO.File]::ReadAllText($inputPath, [System.Text.Encoding]::UTF8)
            }
            & $SetArtifactsFromMetadata $preparedMetadata

            $jobDir = [string]$preparedMetadata.dry_run.windows.job_dir
            [System.IO.Directory]::CreateDirectory($jobDir) | Out-Null
            $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
            $wrapperStdoutPath = Join-Path $jobDir "winqstep-gui-$stamp.stdout.json"
            $wrapperStderrPath = Join-Path $jobDir "winqstep-gui-$stamp.stderr.log"
            $runArguments = @(& $GetActiveJobArguments $false)
            $runArguments += "--compact"
            $process = Start-WinQStepPythonProcess -Arguments $runArguments -StdoutPath $wrapperStdoutPath -StderrPath $wrapperStderrPath

            $jobState["Current"] = @{
                Process = $process
                JobDir = $jobDir
                InputPath = [string]$preparedMetadata.files.input.path
                MetadataPath = [string]$preparedMetadata.files.metadata.path
                OutputPath = [string]$preparedMetadata.files.output.path
                JobStdoutPath = [string]$preparedMetadata.files.stdout.path
                JobStderrPath = [string]$preparedMetadata.files.stderr.path
                WrapperStdoutPath = $wrapperStdoutPath
                WrapperStderrPath = $wrapperStderrPath
                Cancelled = $false
            }
            $controls["LogText"].Text = & $BuildAsyncJobLog $jobState["Current"]
            & $SetJobStatusText (& $FormatRunningJobStatus $jobState["Current"])
            & $SetAsyncJobRunning $true "Running CP2K (PID $($process.Id))"
            $jobTimer.Start()
        }
        catch {
            $message = $_.Exception.Message
            & $AppendLog "ERROR: $message"
            [System.Windows.MessageBox]::Show($window, $message, "WinQStep", "OK", "Error") | Out-Null
            & $SetBusy $false "Ready"
        }
    }.GetNewClosure()

    $CancelAsyncJob = {
        $current = $jobState["Current"]
        if ($null -eq $current) {
            return
        }
        $current["Cancelled"] = $true
        $controls["CancelJobButton"].IsEnabled = $false
        $controls["StatusText"].Text = "Cancelling CP2K"
        & $AppendLog "Cancellation requested."
        try {
            Stop-WinQStepProcessTree ([System.Diagnostics.Process]$current["Process"])
        }
        catch {
            & $AppendLog "ERROR: failed to stop process tree: $($_.Exception.Message)"
        }
        & $RefreshAsyncJob
    }.GetNewClosure()

    $window.Add_Closing({
        param($sender, $eventArgs)
        $current = $jobState["Current"]
        if ($null -eq $current) {
            return
        }

        $process = [System.Diagnostics.Process]$current["Process"]
        if ($process.HasExited) {
            return
        }

        $eventArgs.Cancel = $true
        $message = "A CP2K job is still running.`r`n`r`nPID: $($process.Id)`r`nMetadata: $($current["MetadataPath"])`r`nOutput: $($current["OutputPath"])`r`n`r`nUse Stop before closing WinQStep."
        & $SetJobStatusText (& $FormatRunningJobStatus $current)
        & $AppendLog "Close blocked: CP2K job PID $($process.Id) is still running."
        [System.Windows.MessageBox]::Show($window, $message, "WinQStep", "OK", "Warning") | Out-Null
    }.GetNewClosure())

    $controls["LoadConfigButton"].Add_Click({
        & $InvokeGuiAction "Loading config" {
            $null = & $LoadConfigFields $true
        }
    }.GetNewClosure())

    $controls["SaveConfigButton"].Add_Click({
        & $InvokeGuiAction "Saving config" {
            $null = & $SaveConfigFields $false $true
        }
    }.GetNewClosure())

    $controls["LoadTemplateButton"].Add_Click({
        & $InvokeGuiAction "Loading template" {
            $null = & $LoadTemplateFields $true
        }
    }.GetNewClosure())

    $controls["SaveTemplateButton"].Add_Click({
        & $InvokeGuiAction "Saving template" {
            $null = & $SaveTemplateFields $true
        }
    }.GetNewClosure())

    $controls["InspectDataButton"].Add_Click({
        & $InvokeGuiAction "Inspecting CP2K data" {
            $null = & $InspectCp2kData $true
        }
    }.GetNewClosure())

    $controls["BrowseConfigButton"].Add_Click({
        & $SelectFilePath $controls["ConfigPathBox"] "JSON files (*.json)|*.json|All files (*.*)|*.*"
        & $InvokeGuiAction "Loading config" {
            $null = & $LoadConfigFields $true
        }
    }.GetNewClosure())
    $controls["BrowseTemplateButton"].Add_Click({
        & $SelectFilePath $controls["TemplatePathBox"] "JSON files (*.json)|*.json|All files (*.*)|*.*"
        & $InvokeGuiAction "Loading template" {
            $null = & $LoadTemplateFields $true
        }
    }.GetNewClosure())
    $controls["BrowseStructureButton"].Add_Click({ & $SelectFilePath $controls["StructurePathBox"] "Structures (*.xyz;*.cif;POSCAR;CONTCAR)|*.xyz;*.cif;POSCAR;CONTCAR|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseExistingInputButton"].Add_Click({ & $SelectFilePath $controls["ExistingInputPathBox"] "CP2K input files (*.inp)|*.inp|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseJobDirButton"].Add_Click({ & $SelectFolderPath $controls["JobDirBox"] }.GetNewClosure())
    $controls["WorkflowModeRadio"].Add_Checked({ & $UpdateModeControls }.GetNewClosure())
    $controls["ExistingInputModeRadio"].Add_Checked({ & $UpdateModeControls }.GetNewClosure())

    $controls["DetectButton"].Add_Click({
        & $InvokeGuiAction "Detecting environment" {
            $null = & $SaveConfigFields $false $false
            $result = Invoke-WinQStepPython @("scripts\detect_environment.py", "--config", $controls["ConfigPathBox"].Text)
            $controls["EnvironmentText"].Text = $result.Output
            & $AppendLog "detect_environment.py exited with code $($result.ExitCode)"
        }
    }.GetNewClosure())

    $controls["ImportButton"].Add_Click({
        & $InvokeGuiAction "Importing structure" {
            $result = Invoke-WinQStepPython @("scripts\import_structure.py", "--input", $controls["StructurePathBox"].Text)
            $controls["StructureText"].Text = $result.Output
            & $AppendLog "import_structure.py exited with code $($result.ExitCode)"
        }
    }.GetNewClosure())

    $controls["PreviewButton"].Add_Click({
        $status = if (& $TestIsExistingInputMode) { "Preparing existing input preview" } else { "Preparing workflow input preview" }
        & $InvokeGuiAction $status {
            $null = & $SaveConfigFields $true $false
            if (-not (& $TestIsExistingInputMode)) {
                $null = & $SaveTemplateFields $false
            }
            $result = Invoke-WinQStepPython (& $GetActiveJobArguments $true)
            $metadata = Get-JsonResult $result
            $inputPath = & $GetActiveInputPreviewPath $metadata
            if ([System.IO.File]::Exists($inputPath)) {
                $controls["PreviewText"].Text = [System.IO.File]::ReadAllText($inputPath, [System.Text.Encoding]::UTF8)
            }
            else {
                $controls["PreviewText"].Text = "Input file was not written: $inputPath"
            }
            $controls["LogText"].Text = & $FormatLogWithSummary $metadata $result.Output
            & $SetArtifactsFromMetadata $metadata
        }
    }.GetNewClosure())

    $controls["RunButton"].Add_Click({
        & $StartAsyncJob
    }.GetNewClosure())

    $controls["CancelJobButton"].Add_Click({
        & $CancelAsyncJob
    }.GetNewClosure())

    $controls["ViewInputButton"].Add_Click({
        & $InvokeGuiAction "Viewing input artifact" {
            & $ViewArtifact "input"
        }
    }.GetNewClosure())

    $controls["ViewOutputButton"].Add_Click({
        & $InvokeGuiAction "Viewing output artifact" {
            & $ViewArtifact "output"
        }
    }.GetNewClosure())

    $controls["ViewMetadataButton"].Add_Click({
        & $InvokeGuiAction "Viewing metadata artifact" {
            & $ViewArtifact "metadata"
        }
    }.GetNewClosure())

    $controls["ViewStdoutButton"].Add_Click({
        & $InvokeGuiAction "Viewing stdout artifact" {
            & $ViewArtifact "stdout"
        }
    }.GetNewClosure())

    $controls["ViewStderrButton"].Add_Click({
        & $InvokeGuiAction "Viewing stderr artifact" {
            & $ViewArtifact "stderr"
        }
    }.GetNewClosure())

    $controls["HistoryButton"].Add_Click({
        & $InvokeGuiAction "Loading job history" {
            & $LoadHistory
        }
    }.GetNewClosure())

    $controls["HistoryGrid"].Add_MouseDoubleClick({
        & $OpenSelectedHistory
    }.GetNewClosure())

    $controls["DataLabelsGrid"].Add_MouseDoubleClick({
        & $ApplySelectedDataLabel
    }.GetNewClosure())

    $controls["ClearButton"].Add_Click({
        $controls["EnvironmentText"].Clear()
        $controls["StructureText"].Clear()
        $controls["PreviewText"].Clear()
        $controls["LogText"].Clear()
        $controls["ArtifactSummaryText"].Clear()
        $controls["ArtifactText"].Clear()
        $controls["HistoryGrid"].ItemsSource = $null
        $controls["DataLabelsGrid"].ItemsSource = $null
        $artifactState["Current"] = $null
        & $SetJobStatusText ""
        & $UpdateArtifactControls
    }.GetNewClosure())

    try {
        $null = & $LoadConfigFields $false
    }
    catch {
        $controls["ConfigValidationText"].Text = $_.Exception.Message
    }
    try {
        $null = & $LoadTemplateFields $false
    }
    catch {
        $controls["TemplateValidationText"].Text = $_.Exception.Message
    }
    & $UpdateModeControls
    & $UpdateArtifactControls
    return $window
}

if ($LifecycleSmokeTest) {
    $report = [ordered]@{
        process_started = $false
        process_stopped = $false
        exit_code = $null
        stdout_exists = $false
        stderr_exists = $false
    }
    $process = $null
    $smokeDir = Resolve-WinQStepPath "outputs\lifecycle-smoke"
    [System.IO.Directory]::CreateDirectory($smokeDir) | Out-Null
    $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
    $stdoutPath = Join-Path $smokeDir "sleeper-$stamp.stdout.log"
    $stderrPath = Join-Path $smokeDir "sleeper-$stamp.stderr.log"
    try {
        $process = Start-WinQStepPythonProcess -Arguments @(
            "-c",
            "import time; time.sleep(30)"
        ) -StdoutPath $stdoutPath -StderrPath $stderrPath
        Start-Sleep -Milliseconds 500
        $report["process_started"] = (-not $process.HasExited)
        Stop-WinQStepProcessTree $process
        $report["process_stopped"] = $process.WaitForExit(3000)
        if ($report["process_stopped"]) {
            $null = Save-WinQStepProcessOutput $process $stdoutPath $stderrPath
        }
        if ($process.HasExited) {
            $report["exit_code"] = [int]$process.ExitCode
        }
        $report["stdout_exists"] = [System.IO.File]::Exists($stdoutPath)
        $report["stderr_exists"] = [System.IO.File]::Exists($stderrPath)
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-WinQStepProcessTree $process
        }
    }
    $report | ConvertTo-Json -Depth 5
    if ($report["process_started"] -and $report["process_stopped"]) {
        exit 0
    }
    exit 1
}

if ($SmokeTest) {
    $report = Test-WinQStepGuiPrerequisites
    $window = New-WinQStepWindow
    $expectedEncodingText = "$([char]0x4e2d)$([char]0x6587)$([char]0x8def)$([char]0x5f84):D:\Library\$([char]0x81ea)$([char]0x5236)$([char]0x54c1)"
    $chineseFolderName = "$([char]0x81ea)$([char]0x5236)$([char]0x54c1)"
    $encodingProbeResult = Invoke-WinQStepPython @(
        "-c",
        "import json; sep = chr(92); text = ''.join(chr(x) for x in [0x4e2d, 0x6587, 0x8def, 0x5f84]) + ':D:' + sep + 'Library' + sep + ''.join(chr(x) for x in [0x81ea, 0x5236, 0x54c1]); print(json.dumps(dict(text=text), ensure_ascii=False))"
    )
    $encodingProbe = Get-JsonResult $encodingProbeResult
    $previewResult = Invoke-WinQStepPython @(
        "scripts\run_workflow.py",
        "--config", (Resolve-WinQStepPath "examples\winqstep.config.json"),
        "--template", (Resolve-WinQStepPath "examples\templates\energy_pbe.json"),
        "--structure", (Resolve-WinQStepPath "tests\fixtures\structures\water.xyz"),
        "--job-dir", (Resolve-WinQStepPath "outputs\gui-smoke"),
        "--project-name", "gui_smoke",
        "--prepare-only",
        "--compact"
    )
    $previewMetadata = Get-JsonResult $previewResult
    $existingPreviewResult = Invoke-WinQStepPython @(
        "scripts\run_existing_input.py",
        "--config", (Resolve-WinQStepPath "examples\winqstep.config.json"),
        "--input", (Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"),
        "--job-dir", (Resolve-WinQStepPath "outputs\gui-existing-smoke"),
        "--prepare-only",
        "--compact"
    )
    $existingPreviewMetadata = Get-JsonResult $existingPreviewResult
    $historySmokeDir = Resolve-WinQStepPath "outputs\gui-history-smoke"
    [System.IO.Directory]::CreateDirectory($historySmokeDir) | Out-Null
    $historyMetadataPath = Join-Path $historySmokeDir "history_smoke.winqstep.json"
    $historyInputPath = Join-Path $historySmokeDir "history_smoke.inp"
    $historyOutputPath = Join-Path $historySmokeDir "history_smoke.out"
    $historyStdoutPath = Join-Path $historySmokeDir "history_smoke.stdout.log"
    $historyStderrPath = Join-Path $historySmokeDir "history_smoke.stderr.log"
    $historyMetadata = [ordered]@{
        status = "succeeded"
        created_at = "2026-06-29T00:00:00Z"
        completed_at = "2026-06-29T00:01:00Z"
        returncode = 0
        job = [ordered]@{
            mode = "existing_input"
            input_stem = "history_smoke"
        }
        files = [ordered]@{
            input = [ordered]@{ path = $historyInputPath }
            output = [ordered]@{ path = $historyOutputPath }
            stdout = [ordered]@{ path = $historyStdoutPath }
            stderr = [ordered]@{ path = $historyStderrPath }
            metadata = [ordered]@{ path = $historyMetadataPath }
        }
        cp2k_output = [ordered]@{
            status = "completed"
            warning_count = 0
            program_ended = $true
        }
    }
    [System.IO.File]::WriteAllText($historyInputPath, "&GLOBAL`n  PROJECT history_smoke`n&END GLOBAL`n", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($historyOutputPath, "The number of warnings for this run is : 0`nPROGRAM ENDED AT                 2026-06-29 00:01:00.000`n", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($historyStdoutPath, "", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($historyStderrPath, "", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText(
        $historyMetadataPath,
        (($historyMetadata | ConvertTo-Json -Depth 8) + "`n"),
        $Script:Utf8NoBomEncoding
    )
    $historyResult = Invoke-WinQStepPython @(
        "scripts\list_job_history.py",
        "--workspace", $historySmokeDir,
        "--compact"
    )
    $history = Get-JsonResult $historyResult
    $historyJobs = @()
    if ($null -ne $history.jobs) {
        $historyJobs = @($history.jobs)
    }
    $window.FindName("ExistingInputModeRadio").IsChecked = $true
    $configWorkspace = [string]$window.FindName("DefaultWorkspaceBox").Text
    $report["xaml_loaded"] = ($window -is [System.Windows.Window])
    $report["title"] = $window.Title
    $report["action_button_panel_wraps"] = ($window.FindName("ActionButtonPanel") -is [System.Windows.Controls.WrapPanel])
    $report["cancel_button_loaded"] = ($window.FindName("CancelJobButton") -is [System.Windows.Controls.Button])
    $report["cancel_button_initially_disabled"] = (-not [bool]$window.FindName("CancelJobButton").IsEnabled)
    $report["job_status_text_loaded"] = ($window.FindName("JobStatusText") -is [System.Windows.Controls.TextBlock])
    $report["job_status_text_initial"] = [string]$window.FindName("JobStatusText").Text
    $report["artifact_summary_loaded"] = ($window.FindName("ArtifactSummaryText") -is [System.Windows.Controls.TextBox])
    $report["artifact_text_loaded"] = ($window.FindName("ArtifactText") -is [System.Windows.Controls.TextBox])
    $report["artifact_view_buttons_loaded"] = @(
        "ViewInputButton", "ViewOutputButton", "ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton"
    ).Where({ $window.FindName($_) -is [System.Windows.Controls.Button] }).Count
    $report["artifact_view_buttons_initially_disabled"] = @(
        "ViewInputButton", "ViewOutputButton", "ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton"
    ).Where({ [bool]$window.FindName($_).IsEnabled }).Count -eq 0
    $report["config_tab_loaded"] = ($window.FindName("DistroBox") -is [System.Windows.Controls.TextBox])
    $report["config_distro"] = [string]$window.FindName("DistroBox").Text
    $report["config_cp2k_command"] = [string]$window.FindName("Cp2kCommandBox").Text
    $report["config_data_dir"] = [string]$window.FindName("Cp2kDataDirBox").Text
    $report["config_workspace_path"] = $configWorkspace
    $report["config_workspace_encoding_ok"] = $configWorkspace.Contains($chineseFolderName)
    $report["config_validation_text"] = [string]$window.FindName("ConfigValidationText").Text
    $report["template_tab_loaded"] = ($window.FindName("TemplateProjectBox") -is [System.Windows.Controls.TextBox])
    $report["template_project_name"] = [string]$window.FindName("TemplateProjectBox").Text
    $report["template_run_type"] = [string]$window.FindName("TemplateRunTypeBox").Text
    $report["template_cutoff"] = [string]$window.FindName("CutoffBox").Text
    $report["template_kinds_has_oxygen"] = ([string]$window.FindName("KindsText").Text).Contains("O")
    $report["template_validation_text"] = [string]$window.FindName("TemplateValidationText").Text
    $report["data_labels_grid_loaded"] = ($window.FindName("DataLabelsGrid") -is [System.Windows.Controls.DataGrid])
    $report["history_grid_loaded"] = ($window.FindName("HistoryGrid") -is [System.Windows.Controls.DataGrid])
    $report["console_output_encoding"] = [Console]::OutputEncoding.WebName
    $report["pythonioencoding"] = $env:PYTHONIOENCODING
    $report["encoding_probe_exit_code"] = $encodingProbeResult.ExitCode
    $report["encoding_probe_text"] = $encodingProbe.text
    $report["encoding_probe_ok"] = $encodingProbe.text -eq $expectedEncodingText
    $report["preview_exit_code"] = $previewResult.ExitCode
    $report["preview_input_exists"] = [System.IO.File]::Exists($previewMetadata.files.input.path)
    $report["preview_summary_status"] = $previewMetadata.cp2k_output.status
    $report["existing_preview_exit_code"] = $existingPreviewResult.ExitCode
    $report["existing_preview_mode"] = $existingPreviewMetadata.job.mode
    $report["existing_preview_input_exists"] = [System.IO.File]::Exists($existingPreviewMetadata.files.input.path)
    $report["existing_preview_summary_status"] = $existingPreviewMetadata.cp2k_output.status
    $report["existing_preview_input_path"] = [string]$existingPreviewMetadata.files.input.path
    $report["existing_preview_path_encoding_ok"] = ([string]$existingPreviewMetadata.files.input.path).Contains($chineseFolderName)
    $report["history_exit_code"] = $historyResult.ExitCode
    $report["history_job_count"] = $historyJobs.Count
    $report["history_first_mode"] = if ($historyJobs.Count -gt 0) { [string]$historyJobs[0].mode } else { "" }
    $report["history_first_warning_count"] = if ($historyJobs.Count -gt 0) { $historyJobs[0].warning_count } else { $null }
    $report["existing_mode_input_enabled"] = [bool]$window.FindName("ExistingInputPathBox").IsEnabled
    $report["existing_mode_import_enabled"] = [bool]$window.FindName("ImportButton").IsEnabled
    $report | ConvertTo-Json -Depth 5
    exit 0
}

[void](Test-WinQStepGuiPrerequisites)
$app = [System.Windows.Application]::new()
$window = New-WinQStepWindow
[void]$app.Run($window)

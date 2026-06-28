#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:RepoRoot = Split-Path -Parent $PSScriptRoot
$Script:PythonCommand = "python"

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
        "examples\winqstep.config.json",
        "examples\templates\energy_pbe.json",
        "tests\fixtures\structures\water.xyz"
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
    try {
        $output = & $Script:PythonCommand @Arguments 2>&1
        $exitCode = if ($null -eq $global:LASTEXITCODE) { 0 } else { $global:LASTEXITCODE }
    }
    finally {
        Pop-Location
    }

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = (($output | Out-String).TrimEnd())
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

function New-WinQStepWindow {
    Add-WinQStepWpfAssemblies

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinQStep" Height="760" Width="1120" MinHeight="620" MinWidth="900"
        Background="#F5F7FA" FontFamily="Segoe UI" WindowStartupLocation="CenterScreen">
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

    <DockPanel Grid.Row="0">
      <TextBlock Text="WinQStep" FontSize="22" FontWeight="SemiBold" DockPanel.Dock="Left"/>
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
        <Button x:Name="DetectButton" Content="Detect"/>
        <Button x:Name="ImportButton" Content="Import"/>
        <Button x:Name="PreviewButton" Content="Preview"/>
        <Button x:Name="RunButton" Content="Run"/>
        <Button x:Name="ClearButton" Content="Clear"/>
      </StackPanel>
    </DockPanel>

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
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Config"/>
        <TextBox x:Name="ConfigPathBox" Grid.Row="0" Grid.Column="1"/>
        <Button x:Name="BrowseConfigButton" Grid.Row="0" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="Template"/>
        <TextBox x:Name="TemplatePathBox" Grid.Row="1" Grid.Column="1"/>
        <Button x:Name="BrowseTemplateButton" Grid.Row="1" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="Structure"/>
        <TextBox x:Name="StructurePathBox" Grid.Row="2" Grid.Column="1"/>
        <Button x:Name="BrowseStructureButton" Grid.Row="2" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="3" Grid.Column="0" Text="Job Folder"/>
        <TextBox x:Name="JobDirBox" Grid.Row="3" Grid.Column="1"/>
        <Button x:Name="BrowseJobDirButton" Grid.Row="3" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="4" Grid.Column="0" Text="Project"/>
        <TextBox x:Name="ProjectNameBox" Grid.Row="4" Grid.Column="1"/>
      </Grid>
    </GroupBox>

    <TabControl Grid.Row="2">
      <TabItem Header="Environment">
        <TextBox x:Name="EnvironmentText" FontFamily="Consolas" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Structure">
        <TextBox x:Name="StructureText" FontFamily="Consolas" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Input Preview">
        <TextBox x:Name="PreviewText" FontFamily="Consolas" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Job Log">
        <TextBox x:Name="LogText" FontFamily="Consolas" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="Wrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
    </TabControl>

    <StatusBar Grid.Row="3" Margin="0,10,0,0">
      <StatusBarItem>
        <TextBlock x:Name="StatusText" Text="Ready"/>
      </StatusBarItem>
    </StatusBar>
  </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $controls = @{}
    $names = @(
        "ConfigPathBox", "TemplatePathBox", "StructurePathBox", "JobDirBox", "ProjectNameBox",
        "EnvironmentText", "StructureText", "PreviewText", "LogText", "StatusText",
        "DetectButton", "ImportButton", "PreviewButton", "RunButton", "ClearButton",
        "BrowseConfigButton", "BrowseTemplateButton", "BrowseStructureButton", "BrowseJobDirButton"
    )
    foreach ($name in $names) {
        $controls[$name] = $window.FindName($name)
    }

    $controls["ConfigPathBox"].Text = Resolve-WinQStepPath "examples\winqstep.config.json"
    $controls["TemplatePathBox"].Text = Resolve-WinQStepPath "examples\templates\energy_pbe.json"
    $controls["StructurePathBox"].Text = Resolve-WinQStepPath "tests\fixtures\structures\water.xyz"
    $controls["JobDirBox"].Text = Resolve-WinQStepPath "outputs\gui-preview"
    $controls["ProjectNameBox"].Text = "gui_preview"

    $actionButtons = @(
        $controls["DetectButton"], $controls["ImportButton"], $controls["PreviewButton"],
        $controls["RunButton"], $controls["ClearButton"], $controls["BrowseConfigButton"],
        $controls["BrowseTemplateButton"], $controls["BrowseStructureButton"], $controls["BrowseJobDirButton"]
    )

    function Set-Busy {
        param([bool]$IsBusy, [string]$Status)
        $controls["StatusText"].Text = $Status
        foreach ($button in $actionButtons) {
            $button.IsEnabled = -not $IsBusy
        }
        $window.Cursor = if ($IsBusy) { [System.Windows.Input.Cursors]::Wait } else { $null }
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Append-Log {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($controls["LogText"].Text)) {
            $controls["LogText"].Text = $Text
        }
        else {
            $controls["LogText"].AppendText("`r`n$Text")
        }
        $controls["LogText"].ScrollToEnd()
    }

    function Invoke-GuiAction {
        param([string]$Status, [scriptblock]$Action)
        Set-Busy $true $Status
        try {
            & $Action
        }
        catch {
            $message = $_.Exception.Message
            Append-Log "ERROR: $message"
            [System.Windows.MessageBox]::Show($window, $message, "WinQStep", "OK", "Error") | Out-Null
        }
        finally {
            Set-Busy $false "Ready"
        }
    }

    function Select-FilePath {
        param([Parameter(Mandatory = $true)]$TextBox, [Parameter(Mandatory = $true)][string]$Filter)
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Filter = $Filter
        if ([System.IO.File]::Exists($TextBox.Text)) {
            $dialog.InitialDirectory = Split-Path -Parent $TextBox.Text
        }
        if ($dialog.ShowDialog($window)) {
            $TextBox.Text = $dialog.FileName
        }
    }

    function Select-FolderPath {
        param([Parameter(Mandatory = $true)]$TextBox)
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ([System.IO.Directory]::Exists($TextBox.Text)) {
            $dialog.SelectedPath = $TextBox.Text
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $TextBox.Text = $dialog.SelectedPath
        }
    }

    function Get-WorkflowArguments {
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
    }

    $controls["BrowseConfigButton"].Add_Click({ Select-FilePath $controls["ConfigPathBox"] "JSON files (*.json)|*.json|All files (*.*)|*.*" })
    $controls["BrowseTemplateButton"].Add_Click({ Select-FilePath $controls["TemplatePathBox"] "JSON files (*.json)|*.json|All files (*.*)|*.*" })
    $controls["BrowseStructureButton"].Add_Click({ Select-FilePath $controls["StructurePathBox"] "Structures (*.xyz;*.cif;POSCAR;CONTCAR)|*.xyz;*.cif;POSCAR;CONTCAR|All files (*.*)|*.*" })
    $controls["BrowseJobDirButton"].Add_Click({ Select-FolderPath $controls["JobDirBox"] })

    $controls["DetectButton"].Add_Click({
        Invoke-GuiAction "Detecting environment" {
            $result = Invoke-WinQStepPython @("scripts\detect_environment.py", "--config", $controls["ConfigPathBox"].Text)
            $controls["EnvironmentText"].Text = $result.Output
            Append-Log "detect_environment.py exited with code $($result.ExitCode)"
        }
    })

    $controls["ImportButton"].Add_Click({
        Invoke-GuiAction "Importing structure" {
            $result = Invoke-WinQStepPython @("scripts\import_structure.py", "--input", $controls["StructurePathBox"].Text)
            $controls["StructureText"].Text = $result.Output
            Append-Log "import_structure.py exited with code $($result.ExitCode)"
        }
    })

    $controls["PreviewButton"].Add_Click({
        Invoke-GuiAction "Preparing input preview" {
            $result = Invoke-WinQStepPython (Get-WorkflowArguments $true)
            $metadata = Get-JsonResult $result
            $inputPath = $metadata.files.input.path
            if ([System.IO.File]::Exists($inputPath)) {
                $controls["PreviewText"].Text = [System.IO.File]::ReadAllText($inputPath, [System.Text.Encoding]::UTF8)
            }
            else {
                $controls["PreviewText"].Text = "Input file was not written: $inputPath"
            }
            $controls["LogText"].Text = $result.Output
        }
    })

    $controls["RunButton"].Add_Click({
        Invoke-GuiAction "Running CP2K" {
            $result = Invoke-WinQStepPython (Get-WorkflowArguments $false)
            $metadata = Get-JsonResult $result
            $logText = $result.Output
            $outputPath = $metadata.files.output.path
            if ([System.IO.File]::Exists($outputPath)) {
                $tail = Get-Content -LiteralPath $outputPath -Tail 80 | Out-String
                $logText = "$logText`r`n`r`n--- CP2K output tail ---`r`n$tail"
            }
            $controls["LogText"].Text = $logText
        }
    })

    $controls["ClearButton"].Add_Click({
        $controls["EnvironmentText"].Clear()
        $controls["StructureText"].Clear()
        $controls["PreviewText"].Clear()
        $controls["LogText"].Clear()
    })

    return $window
}

if ($SmokeTest) {
    $report = Test-WinQStepGuiPrerequisites
    $window = New-WinQStepWindow
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
    $report["xaml_loaded"] = ($window -is [System.Windows.Window])
    $report["title"] = $window.Title
    $report["preview_exit_code"] = $previewResult.ExitCode
    $report["preview_input_exists"] = [System.IO.File]::Exists($previewMetadata.files.input.path)
    $report | ConvertTo-Json -Depth 5
    exit 0
}

[void](Test-WinQStepGuiPrerequisites)
$app = [System.Windows.Application]::new()
$window = New-WinQStepWindow
[void]$app.Run($window)

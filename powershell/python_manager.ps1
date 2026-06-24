<#
CHEN Python Version Manager

Place this file at:
  powershell/python_manager.ps1

Requires:
  powershell/common.ps1 in the same folder
  Chocolatey installed and available as choco.exe

Purpose:
  GUI tool for installing/uninstalling selected Python versions with Chocolatey.
  It explicitly manages the SYSTEM Path so only the selected managed Python
  version is the default `python`/`pip` on PATH.
#>

[CmdletBinding()]
param(
    # Optional Chocolatey source. Leave blank to use the machine's configured Chocolatey sources.
    [string]$ChocolateySource = "",

    # Optional switch for troubleshooting. Prevents self-elevation if not admin.
    [switch]$NoSelfElevate
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ======================================================================================
# Load shared CHEN helper functions
# ======================================================================================
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CommonScriptPath = Join-Path $ScriptDirectory "common.ps1"

if (-not (Test-Path $CommonScriptPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "common.ps1 was not found next to this script.`nExpected: $CommonScriptPath",
        "CHEN Python Manager",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

. $CommonScriptPath

# ======================================================================================
# Version configuration
# ======================================================================================
# Main recommended versions: 3.14, 3.13, 3.12
# Older compatibility versions: 3.11, 3.10
$PythonVersions = @(
    [pscustomobject]@{ Label = "Python 3.14"; Version = "3.14"; Package = "python314"; InstallDir = "C:\Python314"; Group = "Recommended"; Notes = "Latest stable" },
    [pscustomobject]@{ Label = "Python 3.13"; Version = "3.13"; Package = "python313"; InstallDir = "C:\Python313"; Group = "Recommended"; Notes = "Stable fallback" },
    [pscustomobject]@{ Label = "Python 3.12"; Version = "3.12"; Package = "python312"; InstallDir = "C:\Python312"; Group = "Recommended"; Notes = "Best compatibility" },
    [pscustomobject]@{ Label = "Python 3.11"; Version = "3.11"; Package = "python311"; InstallDir = "C:\Python311"; Group = "Older Compatibility"; Notes = "Legacy projects" },
    [pscustomobject]@{ Label = "Python 3.10"; Version = "3.10"; Package = "python310"; InstallDir = "C:\Python310"; Group = "Older Compatibility"; Notes = "Oldest supported legacy" }
)

# Valid Chocolatey enhanced exit codes.
# 0 = success, 1605 = already uninstalled, 1614 = product uninstalled, 1641/3010 = reboot required/success.
$ValidChocolateyExitCodes = @(0, 1605, 1614, 1641, 3010)

# ======================================================================================
# Admin / elevation
# ======================================================================================
if (-not (Test-IsAdmin)) {
    if ($NoSelfElevate) {
        Write-Error "This tool must run as Administrator because it installs system software and edits the SYSTEM Path."
        exit 1
    }

    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    )

    if (-not [string]::IsNullOrWhiteSpace($ChocolateySource)) {
        $argumentList += @("-ChocolateySource", "`"$ChocolateySource`"")
    }

    Start-Process -FilePath "powershell.exe" -ArgumentList $argumentList -Verb RunAs | Out-Null
    exit 0
}

# ======================================================================================
# WinForms setup
# ======================================================================================
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "CHEN Python Version Manager"
$form.Size = New-Object System.Drawing.Size(980, 690)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(940, 620)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Python Version Manager"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(16, 14)
$form.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "Installs Python through Chocolatey and manages the SYSTEM Path default Python version."
$subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object System.Drawing.Point(18, 48)
$form.Controls.Add($subtitleLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready."
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(18, 76)
$form.Controls.Add($statusLabel)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(18, 105)
$grid.Size = New-Object System.Drawing.Size(925, 250)
$grid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.MultiSelect = $false
$grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$grid.ReadOnly = $true
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$grid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::AutoSize
$form.Controls.Add($grid)

$grid.Columns.Add("Label", "Version") | Out-Null
$grid.Columns.Add("Package", "Choco Package") | Out-Null
$grid.Columns.Add("InstallDir", "Install Dir") | Out-Null
$grid.Columns.Add("Group", "Group") | Out-Null
$grid.Columns.Add("Installed", "Installed") | Out-Null
$grid.Columns.Add("OnPath", "On SYSTEM Path") | Out-Null
$grid.Columns.Add("Notes", "Notes") | Out-Null

$grid.Columns[0].FillWeight = 80
$grid.Columns[1].FillWeight = 80
$grid.Columns[2].FillWeight = 120
$grid.Columns[3].FillWeight = 100
$grid.Columns[4].FillWeight = 65
$grid.Columns[5].FillWeight = 95
$grid.Columns[6].FillWeight = 120

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(18, 370)
$buttonPanel.Size = New-Object System.Drawing.Size(925, 92)
$buttonPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($buttonPanel)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(18, 475)
$logBox.Size = New-Object System.Drawing.Size(925, 150)
$logBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($logBox)

# ======================================================================================
# Logging and GUI helpers
# ======================================================================================
function Add-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] $Message"
    $logBox.AppendText($line + [Environment]::NewLine)
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
    $form.Refresh()
}

function Set-StatusText {
    param([string]$Message, [int]$Percent = 0)

    $statusLabel.Text = $Message
    Send-GuiProgress -Percent $Percent -Message $Message
    $form.Refresh()
}

function Set-BusyState {
    param([bool]$Busy)

    foreach ($control in $buttonPanel.Controls) {
        $control.Enabled = -not $Busy
    }
    $grid.Enabled = -not $Busy
    $form.UseWaitCursor = $Busy
    $form.Refresh()
}

function Get-SelectedPythonVersion {
    if ($grid.SelectedRows.Count -lt 1) {
        [System.Windows.Forms.MessageBox]::Show(
            "Select a Python version first.",
            "CHEN Python Manager",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return $null
    }

    $package = [string]$grid.SelectedRows[0].Cells["Package"].Value
    return $PythonVersions | Where-Object { $_.Package -eq $package } | Select-Object -First 1
}

# ======================================================================================
# PATH helpers
# ======================================================================================
function Normalize-PathSegment {
    param([string]$PathSegment)

    if ([string]::IsNullOrWhiteSpace($PathSegment)) { return "" }

    $expanded = [Environment]::ExpandEnvironmentVariables($PathSegment.Trim().Trim('"'))
    $expanded = $expanded.TrimEnd('\')
    return $expanded.ToLowerInvariant()
}

function Get-MachinePathSegments {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ([string]::IsNullOrWhiteSpace($machinePath)) { return @() }

    return @($machinePath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Set-MachinePathSegments {
    param([string[]]$Segments)

    $cleanSegments = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($segment in $Segments) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        $trimmed = $segment.Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        $key = Normalize-PathSegment -PathSegment $trimmed
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $cleanSegments.Add($trimmed)
        }
    }

    $newPath = [string]::Join(';', $cleanSegments.ToArray())
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}

function Get-VersionPathEntries {
    param($VersionInfo)

    return @(
        $VersionInfo.InstallDir,
        (Join-Path $VersionInfo.InstallDir "Scripts")
    )
}

function Get-AllManagedPathEntries {
    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($version in $PythonVersions) {
        foreach ($entry in (Get-VersionPathEntries -VersionInfo $version)) {
            $entries.Add($entry)
        }
    }
    return $entries.ToArray()
}

function Remove-PathsFromMachinePath {
    param([string[]]$PathsToRemove)

    $removeSet = @{}
    foreach ($pathToRemove in $PathsToRemove) {
        $key = Normalize-PathSegment -PathSegment $pathToRemove
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $removeSet[$key] = $true
        }
    }

    $kept = @()
    foreach ($segment in (Get-MachinePathSegments)) {
        $key = Normalize-PathSegment -PathSegment $segment
        if (-not $removeSet.ContainsKey($key)) {
            $kept += $segment
        }
    }

    Set-MachinePathSegments -Segments $kept
}

function Remove-VersionFromMachinePath {
    param($VersionInfo)

    Remove-PathsFromMachinePath -PathsToRemove (Get-VersionPathEntries -VersionInfo $VersionInfo)
}

function Set-VersionAsDefaultOnMachinePath {
    param($VersionInfo)

    # Only one managed Python should be the default `python` on PATH.
    Remove-PathsFromMachinePath -PathsToRemove (Get-AllManagedPathEntries)

    $currentSegments = Get-MachinePathSegments
    $versionEntries = Get-VersionPathEntries -VersionInfo $VersionInfo

    # Python root first for python.exe; Scripts second for pip.exe and script shims.
    Set-MachinePathSegments -Segments (@($versionEntries[0], $versionEntries[1]) + $currentSegments)
}

function Test-VersionOnMachinePath {
    param($VersionInfo)

    $machineSegments = Get-MachinePathSegments
    $normalizedSegments = @{}
    foreach ($segment in $machineSegments) {
        $normalizedSegments[(Normalize-PathSegment -PathSegment $segment)] = $true
    }

    foreach ($entry in (Get-VersionPathEntries -VersionInfo $VersionInfo)) {
        if ($normalizedSegments.ContainsKey((Normalize-PathSegment -PathSegment $entry))) {
            return $true
        }
    }

    return $false
}

# ======================================================================================
# Chocolatey helpers
# ======================================================================================
function Get-ChocoPath {
    $command = Get-Command choco.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        $defaultPath = "C:\ProgramData\chocolatey\bin\choco.exe"
        if (Test-Path $defaultPath) { return $defaultPath }
        return $null
    }
    return $command.Source
}

function Invoke-ChocoCommand {
    param(
        [string[]]$Arguments,
        [string]$Description
    )

    $chocoPath = Get-ChocoPath
    if ($null -eq $chocoPath) {
        throw "Chocolatey was not found. Install Chocolatey first, then reopen this tool."
    }

    Add-Log "Running: choco $($Arguments -join ' ')"
    Set-StatusText -Message $Description -Percent 20

    $output = & $chocoPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($output) {
        foreach ($line in $output) {
            Add-Log ([string]$line)
        }
    }

    Add-Log "Chocolatey exit code: $exitCode"

    if ($ValidChocolateyExitCodes -notcontains $exitCode) {
        throw "Chocolatey failed with exit code $exitCode."
    }

    return $exitCode
}

function Install-PythonVersion {
    param($VersionInfo)

    Set-StatusText -Message "Installing $($VersionInfo.Label)..." -Percent 10

    $arguments = @(
        "upgrade",
        $VersionInfo.Package,
        "-y",
        "--no-progress",
        "--params",
        "/InstallDir:$($VersionInfo.InstallDir)"
    )

    if (-not [string]::IsNullOrWhiteSpace($ChocolateySource)) {
        $arguments += @("--source", $ChocolateySource)
    }

    Invoke-ChocoCommand -Arguments $arguments -Description "Installing $($VersionInfo.Label) with Chocolatey..." | Out-Null

    Set-StatusText -Message "Adding $($VersionInfo.Label) to SYSTEM Path as default..." -Percent 80
    Set-VersionAsDefaultOnMachinePath -VersionInfo $VersionInfo

    Set-StatusText -Message "$($VersionInfo.Label) installed and set as PATH default." -Percent 100
    Add-Log "$($VersionInfo.Label) installed and set as default PATH Python."
}

function Uninstall-PythonVersion {
    param($VersionInfo)

    Set-StatusText -Message "Removing $($VersionInfo.Label) from SYSTEM Path..." -Percent 10
    Remove-VersionFromMachinePath -VersionInfo $VersionInfo

    $arguments = @(
        "uninstall",
        $VersionInfo.Package,
        "-y",
        "--no-progress"
    )

    if (-not [string]::IsNullOrWhiteSpace($ChocolateySource)) {
        $arguments += @("--source", $ChocolateySource)
    }

    Invoke-ChocoCommand -Arguments $arguments -Description "Uninstalling $($VersionInfo.Label) with Chocolatey..." | Out-Null

    Set-StatusText -Message "$($VersionInfo.Label) uninstalled and removed from SYSTEM Path." -Percent 100
    Add-Log "$($VersionInfo.Label) uninstalled and removed from PATH."
}

function Test-PythonInstalled {
    param($VersionInfo)

    $pythonExe = Join-Path $VersionInfo.InstallDir "python.exe"
    if (Test-Path $pythonExe) { return $true }

    $chocoPath = Get-ChocoPath
    if ($null -eq $chocoPath) { return $false }

    try {
        $result = & $chocoPath list --local-only --exact $VersionInfo.Package --limit-output 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($result | Out-String))) {
            return $true
        }
    }
    catch {
        return $false
    }

    return $false
}

# ======================================================================================
# Refresh/display
# ======================================================================================
function Refresh-VersionGrid {
    $grid.Rows.Clear()

    foreach ($version in $PythonVersions) {
        $installedText = if (Test-PythonInstalled -VersionInfo $version) { "Yes" } else { "No" }
        $pathText = if (Test-VersionOnMachinePath -VersionInfo $version) { "Yes" } else { "No" }

        $rowIndex = $grid.Rows.Add(
            $version.Label,
            $version.Package,
            $version.InstallDir,
            $version.Group,
            $installedText,
            $pathText,
            $version.Notes
        )

        if ($pathText -eq "Yes") {
            $grid.Rows[$rowIndex].DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        }
    }

    if ($grid.Rows.Count -gt 0 -and $grid.SelectedRows.Count -eq 0) {
        $grid.Rows[0].Selected = $true
    }
}

function Run-OperationSafely {
    param(
        [scriptblock]$Operation,
        [string]$SuccessMessage
    )

    Set-BusyState -Busy $true
    try {
        & $Operation
        Refresh-VersionGrid
        [System.Windows.Forms.MessageBox]::Show(
            $SuccessMessage,
            "CHEN Python Manager",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        $message = $_.Exception.Message
        Add-Log "ERROR: $message"
        Set-StatusText -Message "Error: $message" -Percent 0
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            "CHEN Python Manager Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    finally {
        Set-BusyState -Busy $false
    }
}

# ======================================================================================
# Buttons
# ======================================================================================
function New-ManagerButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [scriptblock]$OnClick
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $button.Add_Click($OnClick)
    $buttonPanel.Controls.Add($button)
    return $button
}

New-ManagerButton -Text "Install / Update + Make Default" -X 0 -Y 0 -Width 210 -Height 36 -OnClick {
    $selected = Get-SelectedPythonVersion
    if ($null -eq $selected) { return }

    Run-OperationSafely -SuccessMessage "$($selected.Label) installed/updated and set as the default PATH Python." -Operation {
        Install-PythonVersion -VersionInfo $selected
    }
} | Out-Null

New-ManagerButton -Text "Uninstall + Remove PATH" -X 220 -Y 0 -Width 170 -Height 36 -OnClick {
    $selected = Get-SelectedPythonVersion
    if ($null -eq $selected) { return }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Uninstall $($selected.Label) and remove its SYSTEM Path entries?",
        "Confirm Uninstall",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Run-OperationSafely -SuccessMessage "$($selected.Label) uninstalled and removed from PATH." -Operation {
        Uninstall-PythonVersion -VersionInfo $selected
    }
} | Out-Null

New-ManagerButton -Text "Make Selected Default PATH" -X 400 -Y 0 -Width 190 -Height 36 -OnClick {
    $selected = Get-SelectedPythonVersion
    if ($null -eq $selected) { return }

    Run-OperationSafely -SuccessMessage "$($selected.Label) is now the default managed Python on SYSTEM Path." -Operation {
        Set-StatusText -Message "Setting $($selected.Label) as default PATH Python..." -Percent 50
        Set-VersionAsDefaultOnMachinePath -VersionInfo $selected
        Set-StatusText -Message "$($selected.Label) is now the PATH default." -Percent 100
        Add-Log "$($selected.Label) set as default managed PATH Python."
    }
} | Out-Null

New-ManagerButton -Text "Remove Selected From PATH" -X 600 -Y 0 -Width 170 -Height 36 -OnClick {
    $selected = Get-SelectedPythonVersion
    if ($null -eq $selected) { return }

    Run-OperationSafely -SuccessMessage "$($selected.Label) removed from SYSTEM Path." -Operation {
        Set-StatusText -Message "Removing $($selected.Label) from SYSTEM Path..." -Percent 50
        Remove-VersionFromMachinePath -VersionInfo $selected
        Set-StatusText -Message "$($selected.Label) removed from SYSTEM Path." -Percent 100
        Add-Log "$($selected.Label) removed from PATH."
    }
} | Out-Null

New-ManagerButton -Text "Refresh Status" -X 780 -Y 0 -Width 125 -Height 36 -OnClick {
    Run-OperationSafely -SuccessMessage "Status refreshed." -Operation {
        Set-StatusText -Message "Refreshing Python status..." -Percent 25
        Refresh-VersionGrid
        Set-StatusText -Message "Status refreshed." -Percent 100
        Add-Log "Status refreshed."
    }
} | Out-Null

New-ManagerButton -Text "Remove ALL Managed Python PATH Entries" -X 0 -Y 48 -Width 260 -Height 36 -OnClick {
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Remove all managed C:\Python310 through C:\Python314 entries from the SYSTEM Path?`nThis does not uninstall Python.",
        "Confirm PATH Cleanup",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Run-OperationSafely -SuccessMessage "All managed Python PATH entries were removed." -Operation {
        Set-StatusText -Message "Removing all managed Python entries from SYSTEM Path..." -Percent 50
        Remove-PathsFromMachinePath -PathsToRemove (Get-AllManagedPathEntries)
        Set-StatusText -Message "All managed Python PATH entries removed." -Percent 100
        Add-Log "Removed all managed Python PATH entries."
    }
} | Out-Null

New-ManagerButton -Text "Open System Environment Variables" -X 270 -Y 48 -Width 235 -Height 36 -OnClick {
    Start-Process "SystemPropertiesAdvanced.exe" | Out-Null
} | Out-Null

New-ManagerButton -Text "Close" -X 515 -Y 48 -Width 100 -Height 36 -OnClick {
    $form.Close()
} | Out-Null

# ======================================================================================
# Launch
# ======================================================================================
Add-Log "Loaded CHEN Python Version Manager."
Add-Log "Chocolatey source: $(if ([string]::IsNullOrWhiteSpace($ChocolateySource)) { '<configured default>' } else { $ChocolateySource })"
Add-Log "This tool manages only these PATH folders: $((Get-AllManagedPathEntries) -join ', ')"
Set-StatusText -Message "Ready. Select a Python version and choose an action." -Percent 0
Refresh-VersionGrid

[void]$form.ShowDialog()

[CmdletBinding()]
param(
    [string]$StartPath = "",
    [string]$ExpressInstallPath = "",
    [string]$LogFile = "C:\Logs\matlab_installer_log.txt",
    [switch]$PauseOnExit
)

$ErrorActionPreference = "Stop"

# ==========================
# Load shared helper script
# ==========================
$commonScript = Join-Path $PSScriptRoot "common.ps1"

if (-not (Test-Path -LiteralPath $commonScript)) {
    Write-Error "common.ps1 not found at: $commonScript"
    exit 1
}

. $commonScript

# ==========================
# Override progress output safely
# This prevents CHEN_PROGRESS lines from being captured as function return values.
# ==========================
function Send-GuiProgress {
    param(
        [int]$Percent,
        [string]$Message
    )

    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }

    [Console]::Out.WriteLine("CHEN_PROGRESS|$Percent|$Message")
    [Console]::Out.Flush()
}

# ==========================
# Script-level variables
# ==========================
$script:LogFile = $LogFile
$script:LicenseFile = ""

# The real server/root is supplied by the GUI through CHEN_NETWORK_ROOT.
$script:MatlabNetworkRelativePath = "Support\Software\MatLab\Software\MatLabR2026A\Windows"

# ==========================
# Logging
# ==========================
function Write-InstallerLog {
    param(
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level,

        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    try {
        $logFolder = Split-Path $script:LogFile -Parent

        if (-not (Test-Path -LiteralPath $logFolder)) {
            New-Item -ItemType Directory -Force -Path $logFolder | Out-Null
        }

        Add-Content -LiteralPath $script:LogFile -Value $line
    }
    catch {
        [Console]::Out.WriteLine("ERROR writing to MATLAB log file: $($_.Exception.Message)")
        [Console]::Out.Flush()
    }
}

# ==========================
# Dialog helpers
# ==========================
function Initialize-WindowsForms {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName Microsoft.VisualBasic
}

function Show-InputBox {
    param(
        [string]$Prompt,
        [string]$Title,
        [string]$DefaultValue = ""
    )

    Initialize-WindowsForms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size -ArgumentList 650, 310
    $form.MinimumSize = New-Object System.Drawing.Size -ArgumentList 650, 310
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.FormBorderStyle = "FixedDialog"
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    $mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $mainLayout.Dock = "Fill"
    $mainLayout.ColumnCount = 1
    $mainLayout.RowCount = 5
    $mainLayout.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 24, 18, 24, 18
    $mainLayout.BackColor = $form.BackColor

    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 95)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))

    $form.Controls.Add($mainLayout)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.Dock = "Fill"
    $titleLabel.TextAlign = "MiddleCenter"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::Black
    $mainLayout.Controls.Add($titleLabel, 0, 0)

    $promptLabel = New-Object System.Windows.Forms.Label
    $promptLabel.Text = $Prompt
    $promptLabel.Dock = "Fill"
    $promptLabel.TextAlign = "MiddleCenter"
    $promptLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $promptLabel.ForeColor = [System.Drawing.Color]::FromArgb(35, 35, 35)
    $mainLayout.Controls.Add($promptLabel, 0, 1)

    $pathTextBox = New-Object System.Windows.Forms.TextBox
    $pathTextBox.Dock = "Fill"
    $pathTextBox.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 6, 16, 6
    $pathTextBox.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $pathTextBox.Text = $DefaultValue
    $mainLayout.Controls.Add($pathTextBox, 0, 2)

    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = "Fill"
    $bottomPanel.BackColor = $form.BackColor
    $mainLayout.Controls.Add($bottomPanel, 0, 4)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Width = 110
    $okButton.Height = 30
    $okButton.Location = New-Object System.Drawing.Point -ArgumentList 350, 7
    $okButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $okButton.FlatStyle = "Flat"
    $okButton.BackColor = [System.Drawing.Color]::White
    $okButton.ForeColor = [System.Drawing.Color]::Black
    $okButton.UseVisualStyleBackColor = $false
    $bottomPanel.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Width = 110
    $cancelButton.Height = 30
    $cancelButton.Location = New-Object System.Drawing.Point -ArgumentList 470, 7
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $cancelButton.FlatStyle = "Flat"
    $cancelButton.BackColor = [System.Drawing.Color]::WhiteSmoke
    $cancelButton.ForeColor = [System.Drawing.Color]::Black
    $cancelButton.UseVisualStyleBackColor = $false
    $bottomPanel.Controls.Add($cancelButton)

    $state = @{
        Value = ""
    }

    $okButton.Add_Click({
        $state.Value = $pathTextBox.Text.Trim()
        $form.Close()
    })

    $cancelButton.Add_Click({
        $state.Value = ""
        $form.Close()
    })

    $pathTextBox.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $state.Value = $pathTextBox.Text.Trim()
            $form.Close()
        }
    })

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    [void]$form.ShowDialog()

    return $state.Value
}

function Show-YesNoPrompt {
    param(
        [string]$Message,
        [string]$Title = "CHEN MATLAB Installer"
    )

    Initialize-WindowsForms

    $result = [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Normalize-NetworkRoot {
    param(
        [string]$NetworkRoot
    )

    if ([string]::IsNullOrWhiteSpace($NetworkRoot)) {
        return ""
    }

    $cleanRoot = $NetworkRoot.Trim().Replace("/", "\")
    $cleanRoot = $cleanRoot -replace "[\\\/]+$", ""

    if (-not $cleanRoot.StartsWith("\\")) {
        $cleanRoot = "\\" + ($cleanRoot -replace "^[\\\/]+", "")
    }

    return $cleanRoot
}

function Get-MatlabVersionFromPath {
    param(
        [string]$PathText
    )

    if ($PathText -match "(?i)MatLabR\d{4}[A-Z]") {
        $rawVersion = $matches[0]

        if ($rawVersion -match "(?i)MatLab(R\d{4}[A-Z])") {
            return "MatLab $($matches[1].ToUpper())"
        }

        return $rawVersion
    }

    return "Current MatLab Version"
}

function Get-ExpressInstallPath {
    param(
        [string]$NetworkRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ExpressInstallPath)) {
        Write-InstallerLog INFO "Using explicit ExpressInstallPath parameter."
        return $ExpressInstallPath
    }

    $cleanRoot = Normalize-NetworkRoot -NetworkRoot $NetworkRoot

    if ([string]::IsNullOrWhiteSpace($cleanRoot)) {
        return ""
    }

    return Join-Path $cleanRoot $script:MatlabNetworkRelativePath
}

function Resolve-InitialFolder {
    param(
        [string]$InitialPath
    )

    if ([string]::IsNullOrWhiteSpace($InitialPath)) {
        Write-InstallerLog INFO "No initial path provided; defaulting to C:\"
        return "C:\"
    }

    $cleanPath = $InitialPath.Trim('"')

    try {
        if (-not (Test-Path -LiteralPath $cleanPath)) {
            Write-InstallerLog WARN "Initial path does not exist; falling back to C:\. Path entered: $cleanPath"
            return "C:\"
        }

        $item = Get-Item -LiteralPath $cleanPath

        if ($item.PSIsContainer) {
            Write-InstallerLog INFO "Initial path is a directory; using: $($item.FullName)"
            return $item.FullName
        }

        $parent = Split-Path $item.FullName -Parent
        Write-InstallerLog INFO "Initial path is a file; using parent folder: $parent"

        if ([string]::IsNullOrWhiteSpace($parent) -or -not (Test-Path -LiteralPath $parent)) {
            Write-InstallerLog WARN "Could not resolve file parent folder; falling back to C:\"
            return "C:\"
        }

        return $parent
    }
    catch {
        Write-InstallerLog WARN "Failed to resolve initial path; falling back to C:\. Error: $($_.Exception.Message)"
        return "C:\"
    }
}

function Select-Folder {
    param(
        [string]$InitialPath = ""
    )

    Initialize-WindowsForms

    $startFolder = Resolve-InitialFolder -InitialPath $InitialPath

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select a MATLAB installer folder"
    $dialog.ShowNewFolderButton = $true
    $dialog.SelectedPath = $startFolder

    $result = $dialog.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }

    Write-InstallerLog WARN "User cancelled folder browser."
    return ""
}

function Select-LicenseFile {
    param(
        [string]$InitialFolder = "C:\"
    )

    Initialize-WindowsForms

    if ([string]::IsNullOrWhiteSpace($InitialFolder) -or -not (Test-Path -LiteralPath $InitialFolder)) {
        $InitialFolder = "C:\"
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select license.dat"
    $dialog.InitialDirectory = $InitialFolder
    $dialog.Filter = "License file (license.dat)|license.dat|DAT files (*.dat)|*.dat|All files (*.*)|*.*"

    $result = $dialog.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }

    Write-InstallerLog WARN "User cancelled license.dat file picker."
    return ""
}

function Show-MatlabSourceForm {
    param(
        [string]$NetworkRoot,
        [string]$ExpressPath,
        [string]$VersionName
    )

    Initialize-WindowsForms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select MATLAB Installer Source"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size -ArgumentList 650, 360
    $form.MinimumSize = New-Object System.Drawing.Size -ArgumentList 650, 360
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.FormBorderStyle = "FixedDialog"
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    $mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $mainLayout.Dock = "Fill"
    $mainLayout.ColumnCount = 1
    $mainLayout.RowCount = 7
    $mainLayout.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 24, 18, 24, 18
    $mainLayout.BackColor = $form.BackColor

    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 48)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 48)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 48)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))

    $form.Controls.Add($mainLayout)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Choose MATLAB Installer Source"
    $titleLabel.Dock = "Fill"
    $titleLabel.TextAlign = "MiddleCenter"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::Black
    $mainLayout.Controls.Add($titleLabel, 0, 0)

    $networkLabel = New-Object System.Windows.Forms.Label
    $networkLabel.Dock = "Fill"
    $networkLabel.TextAlign = "MiddleCenter"
    $networkLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)

    if ([string]::IsNullOrWhiteSpace($NetworkRoot)) {
        $networkLabel.Text = "No network root was provided by the GUI. Express install is unavailable."
        $networkLabel.ForeColor = [System.Drawing.Color]::DarkRed
    }
    else {
        $networkLabel.Text = "Network Root: $NetworkRoot"
        $networkLabel.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    }

    $mainLayout.Controls.Add($networkLabel, 0, 1)

    $buttonFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)

    $expressButton = New-Object System.Windows.Forms.Button
    $expressButton.Text = "Install $VersionName From Network Root"
    $expressButton.Dock = "Fill"
    $expressButton.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 6, 16, 6
    $expressButton.Font = $buttonFont
    $expressButton.FlatStyle = "Flat"
    $expressButton.BackColor = [System.Drawing.Color]::White
    $expressButton.ForeColor = [System.Drawing.Color]::Black
    $expressButton.UseVisualStyleBackColor = $false
    $expressButton.Enabled = -not [string]::IsNullOrWhiteSpace($NetworkRoot)

    if (-not $expressButton.Enabled) {
        $expressButton.Text = "Express Install Unavailable - No Network Root"
        $expressButton.BackColor = [System.Drawing.Color]::Gainsboro
        $expressButton.ForeColor = [System.Drawing.Color]::DimGray
    }

    $mainLayout.Controls.Add($expressButton, 0, 2)

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Text = "Open Folder Browser From C:\"
    $browseButton.Dock = "Fill"
    $browseButton.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 6, 16, 6
    $browseButton.Font = $buttonFont
    $browseButton.FlatStyle = "Flat"
    $browseButton.BackColor = [System.Drawing.Color]::White
    $browseButton.ForeColor = [System.Drawing.Color]::Black
    $browseButton.UseVisualStyleBackColor = $false
    $mainLayout.Controls.Add($browseButton, 0, 3)

    $specificButton = New-Object System.Windows.Forms.Button
    $specificButton.Text = "Open Folder Browser From Specific Path"
    $specificButton.Dock = "Fill"
    $specificButton.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 6, 16, 6
    $specificButton.Font = $buttonFont
    $specificButton.FlatStyle = "Flat"
    $specificButton.BackColor = [System.Drawing.Color]::White
    $specificButton.ForeColor = [System.Drawing.Color]::Black
    $specificButton.UseVisualStyleBackColor = $false
    $mainLayout.Controls.Add($specificButton, 0, 4)

    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = "Fill"
    $bottomPanel.BackColor = $form.BackColor
    $mainLayout.Controls.Add($bottomPanel, 0, 6)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Width = 110
    $cancelButton.Height = 30
    $cancelButton.Location = New-Object System.Drawing.Point -ArgumentList 470, 7
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $cancelButton.FlatStyle = "Flat"
    $cancelButton.BackColor = [System.Drawing.Color]::WhiteSmoke
    $cancelButton.ForeColor = [System.Drawing.Color]::Black
    $cancelButton.UseVisualStyleBackColor = $false
    $bottomPanel.Controls.Add($cancelButton)

    $selection = @{
        Action = "Cancel"
        Path = ""
    }

    $expressButton.Add_Click({
        $selection.Action = "Express"
        $selection.Path = $ExpressPath
        $form.Close()
    })

    $browseButton.Add_Click({
        $selection.Action = "BrowseC"
        $selection.Path = "C:\"
        $form.Close()
    })

    $specificButton.Add_Click({
        $selection.Action = "Specific"
        $selection.Path = ""
        $form.Close()
    })

    $cancelButton.Add_Click({
        $selection.Action = "Cancel"
        $selection.Path = ""
        $form.Close()
    })

    $form.CancelButton = $cancelButton

    [void]$form.ShowDialog()

    return $selection
}

function Select-MatlabInstallerFolder {
    $networkRoot = Normalize-NetworkRoot -NetworkRoot $env:CHEN_NETWORK_ROOT
    $expressPath = Get-ExpressInstallPath -NetworkRoot $networkRoot

    if (-not [string]::IsNullOrWhiteSpace($ExpressInstallPath)) {
        $versionName = Get-MatlabVersionFromPath -PathText $ExpressInstallPath
    }
    else {
        $versionName = Get-MatlabVersionFromPath -PathText $script:MatlabNetworkRelativePath
    }

    if (-not [string]::IsNullOrWhiteSpace($StartPath)) {
        Write-InstallerLog INFO "StartPath parameter provided; opening folder browser from resolved StartPath."
        Send-GuiProgress 10 "Opening folder browser from provided path"
        return Select-Folder -InitialPath $StartPath
    }

    Write-InstallerLog INFO "Opening MATLAB source selection form."
    Send-GuiProgress 10 "Opening MATLAB source selection form"

    $selection = Show-MatlabSourceForm `
        -NetworkRoot $networkRoot `
        -ExpressPath $expressPath `
        -VersionName $versionName

    switch ($selection.Action) {
        "Express" {
            if ([string]::IsNullOrWhiteSpace($networkRoot)) {
                Write-InstallerLog WARN "Express install selected, but no CHEN_NETWORK_ROOT value was provided. Falling back to C:\ folder browser."
                Send-GuiProgress 10 "Network root missing; opening folder browser"
                return Select-Folder -InitialPath "C:\"
            }

            if ([string]::IsNullOrWhiteSpace($expressPath)) {
                Write-InstallerLog WARN "Express install path could not be built. Falling back to C:\ folder browser."
                Send-GuiProgress 10 "Express path unavailable; opening folder browser"
                return Select-Folder -InitialPath "C:\"
            }

            Write-InstallerLog INFO "Express install selected. Built express path: $expressPath"

            if (-not (Test-Path -LiteralPath $expressPath)) {
                Write-InstallerLog WARN "Express install path was not found: $expressPath. Falling back to C:\ folder browser."
                Send-GuiProgress 10 "Express path not found; opening folder browser"
                return Select-Folder -InitialPath "C:\"
            }

            Write-InstallerLog INFO "Express install path exists: $expressPath"
            Send-GuiProgress 15 "Using network express install path"
            return $expressPath
        }

        "BrowseC" {
            Write-InstallerLog INFO "User selected normal folder browser from C:\."
            Send-GuiProgress 10 "Opening folder browser"
            return Select-Folder -InitialPath "C:\"
        }

        "Specific" {
            Write-InstallerLog INFO "User selected specific path option."

            $specificPath = Show-InputBox `
                -Prompt "Enter a start path or exact path to the MATLAB installer folder.`n`nIf the path is a file, the picker will open from the file's parent folder.`nIf the path does not exist, the picker will open from C:\" `
                -Title "Specific MATLAB Path" `
                -DefaultValue ""

            if ([string]::IsNullOrWhiteSpace($specificPath)) {
                Write-InstallerLog WARN "No specific path was entered. Falling back to C:\ folder browser."
                Send-GuiProgress 10 "Opening folder browser"
                return Select-Folder -InitialPath "C:\"
            }

            $resolvedStartFolder = Resolve-InitialFolder -InitialPath $specificPath

            Write-InstallerLog INFO "Opening folder browser from resolved specific path: $resolvedStartFolder"
            Send-GuiProgress 10 "Opening folder browser from specific path"

            return Select-Folder -InitialPath $resolvedStartFolder
        }

        default {
            Write-InstallerLog WARN "User cancelled MATLAB source selection."
            return ""
        }
    }
}

# ==========================
# Validation
# ==========================
function Validate-MatlabFolder {
    param(
        [string]$MatlabFolder
    )

    if ([string]::IsNullOrWhiteSpace($MatlabFolder)) {
        throw "No MATLAB folder was selected."
    }

    if (-not (Test-Path -LiteralPath $MatlabFolder)) {
        throw "Selected folder does not exist: $MatlabFolder"
    }

    $setupExe = Join-Path $MatlabFolder "setup.exe"
    $inputFile = Join-Path $MatlabFolder "installer_input.txt"

    if (-not (Test-Path -LiteralPath $setupExe)) {
        throw "setup.exe not found in: $MatlabFolder"
    }

    if (-not (Test-Path -LiteralPath $inputFile)) {
        throw "installer_input.txt not found in: $MatlabFolder"
    }

    Write-InstallerLog INFO "Found setup.exe"
    Write-InstallerLog INFO "Found installer_input.txt"
    Write-InstallerLog INFO "Selected folder passed validation"
}

function Validate-LicenseFile {
    param(
        [string]$MatlabFolder
    )

    $licenseFile = Join-Path $MatlabFolder "license.dat"

    if (Test-Path -LiteralPath $licenseFile) {
        $script:LicenseFile = $licenseFile
        Write-InstallerLog INFO "Found license.dat in selected folder"
    }
    else {
        Write-InstallerLog WARN "license.dat not found in: $MatlabFolder"

        $chooseDifferentFile = Show-YesNoPrompt `
            -Message "license.dat was not found in the selected MATLAB folder.`n`nWould you like to select a license.dat from a different location?"

        if (-not $chooseDifferentFile) {
            throw "User chose not to select a license file."
        }

        Write-InstallerLog INFO "User chose to select a license file"
        $script:LicenseFile = Select-LicenseFile -InitialFolder $MatlabFolder
    }

    if ([string]::IsNullOrWhiteSpace($script:LicenseFile)) {
        throw "No license file selected."
    }

    if (-not (Test-Path -LiteralPath $script:LicenseFile)) {
        throw "License file does not exist: $script:LicenseFile"
    }

    $serverLine = Select-String `
        -LiteralPath $script:LicenseFile `
        -Pattern "^SERVER " `
        -CaseSensitive:$false `
        -Quiet

    if (-not $serverLine) {
        throw "license.dat is invalid: missing SERVER line."
    }

    $useServerLine = Select-String `
        -LiteralPath $script:LicenseFile `
        -Pattern "USE_SERVER" `
        -CaseSensitive:$false `
        -Quiet

    if (-not $useServerLine) {
        throw "license.dat is invalid: missing USE_SERVER."
    }

    Write-InstallerLog INFO "license.dat format passed validation"
    Write-InstallerLog INFO "Using license file: $script:LicenseFile"
}

function Get-MatlabDestinationFolder {
    param(
        [string]$InstallerInputFile
    )

    if (-not (Test-Path -LiteralPath $InstallerInputFile)) {
        return ""
    }

    foreach ($line in Get-Content -LiteralPath $InstallerInputFile) {
        if ($line -match "^\s*destinationFolder\s*=(.+?)\s*$") {
            return $matches[1].Trim().Trim('"')
        }
    }

    return ""
}

# ==========================
# Process wait helpers
# ==========================
function Wait-ForProcessStart {
    param(
        [string]$ProcessName,
        [int]$PollSeconds = 2,
        [int]$TimeoutSeconds = 0
    )

    $elapsed = 0

    while ($true) {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

        if ($process) {
            return $true
        }

        Start-Sleep -Seconds $PollSeconds

        if ($TimeoutSeconds -gt 0) {
            $elapsed += $PollSeconds

            if ($elapsed -ge $TimeoutSeconds) {
                return $false
            }
        }
    }
}

function Wait-ForProcessFinish {
    param(
        [string]$ProcessName,
        [int]$PollSeconds = 15,
        [int]$ProgressPercent = 65,
        [string]$ProgressMessage = "Waiting for process to finish"
    )

    while ($true) {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

        if (-not $process) {
            return
        }

        Send-GuiProgress $ProgressPercent $ProgressMessage
        Start-Sleep -Seconds $PollSeconds
    }
}

# ==========================
# MATLAB install logic
# ==========================
function Install-Matlab {
    param(
        [string]$MatlabFolder
    )

    $setupExe = Join-Path $MatlabFolder "setup.exe"
    $inputFile = Join-Path $MatlabFolder "installer_input.txt"

    $matlabInstallLocation = Get-MatlabDestinationFolder -InstallerInputFile $inputFile

    if (-not [string]::IsNullOrWhiteSpace($matlabInstallLocation)) {
        if (Test-Path -LiteralPath $matlabInstallLocation) {
            Write-InstallerLog WARN "Existing MATLAB install located at $matlabInstallLocation"

            $continueInstall = Show-YesNoPrompt `
                -Message "An existing MATLAB install appears to exist at:`n`n$matlabInstallLocation`n`nWould you like to continue the install?"

            if ($continueInstall) {
                Write-InstallerLog INFO "User chose to continue install"
            }
            else {
                throw "User chose not to continue install."
            }
        }
    }

    Send-GuiProgress 40 "Running MATLAB installer"
    Write-InstallerLog INFO "Running MATLAB installer..."
    Write-InstallerLog INFO "Command: $setupExe -inputFile $inputFile"

    $setupProcess = Start-Process `
        -FilePath $setupExe `
        -ArgumentList @("-inputFile", $inputFile) `
        -PassThru

    while (-not $setupProcess.HasExited) {
        Send-GuiProgress 45 "MATLAB setup.exe is still running"
        Start-Sleep -Seconds 15
        $setupProcess.Refresh()
    }

    if ($setupProcess.ExitCode -ne 0) {
        throw "MATLAB setup.exe failed with exit code $($setupProcess.ExitCode)."
    }

    Send-GuiProgress 55 "Waiting for MATLAB installer background process"
    Write-InstallerLog INFO "Waiting for MATLAB installer background process to start..."

    $started = Wait-ForProcessStart `
        -ProcessName "MathWorksProductInstaller" `
        -PollSeconds 2 `
        -TimeoutSeconds 0

    if (-not $started) {
        throw "MathWorksProductInstaller process did not start."
    }

    Write-InstallerLog INFO "MATLAB installer background process found."
    Write-InstallerLog INFO "Waiting for MATLAB installer to finish."

    Send-GuiProgress 65 "Waiting for MATLAB installer to finish"

    Wait-ForProcessFinish `
        -ProcessName "MathWorksProductInstaller" `
        -PollSeconds 15 `
        -ProgressPercent 65 `
        -ProgressMessage "MATLAB installer is still running"

    Write-InstallerLog INFO "MATLAB installer completed successfully"
}

function Install-LicenseFile {
    param(
        [string]$MatlabFolder
    )

    $inputFile = Join-Path $MatlabFolder "installer_input.txt"
    $matlabInstallLocation = Get-MatlabDestinationFolder -InstallerInputFile $inputFile

    if ([string]::IsNullOrWhiteSpace($matlabInstallLocation)) {
        throw "destinationFolder was not found in installer_input.txt."
    }

    $matlabInstallLocation = $matlabInstallLocation.Trim('"')
    $matlabLicenseFolder = Join-Path $matlabInstallLocation "licenses"
    $targetLicenseFile = Join-Path $matlabLicenseFolder "license.dat"

    Write-InstallerLog INFO "MATLAB install location: $matlabInstallLocation"

    if (-not (Test-Path -LiteralPath $matlabLicenseFolder)) {
        Write-InstallerLog INFO "Creating licenses folder: $matlabLicenseFolder"
        New-Item -ItemType Directory -Force -Path $matlabLicenseFolder | Out-Null
    }
    else {
        Write-InstallerLog INFO "Licenses folder already exists: $matlabLicenseFolder"
    }

    if (-not (Test-Path -LiteralPath $targetLicenseFile)) {
        Write-InstallerLog INFO "Copying license.dat to MATLAB licenses folder..."
        Copy-Item -LiteralPath $script:LicenseFile -Destination $targetLicenseFile -Force
        Write-InstallerLog INFO "Copied license.dat to: $targetLicenseFile"
    }
    else {
        Write-InstallerLog WARN "MATLAB license.dat file already exists"
        Write-InstallerLog INFO "Check that the license info is correct if MATLAB will not activate."
    }
}

# ==========================
# Main
# ==========================
function Invoke-Main {
    New-Item -ItemType Directory -Force -Path "C:\Logs" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Temp" | Out-Null

    Send-GuiProgress 5 "Starting MATLAB installer"
    Write-InstallerLog INFO "Starting matlab_installer.ps1"

    $networkRoot = Normalize-NetworkRoot -NetworkRoot $env:CHEN_NETWORK_ROOT

    if ([string]::IsNullOrWhiteSpace($networkRoot)) {
        Write-InstallerLog WARN "No CHEN_NETWORK_ROOT value was provided by the GUI. Express install will be unavailable."
    }
    else {
        Write-InstallerLog INFO "CHEN_NETWORK_ROOT received from GUI: $networkRoot"
    }

    $selectedFolder = Select-MatlabInstallerFolder

    if ([string]::IsNullOrWhiteSpace($selectedFolder)) {
        throw "No MATLAB installer folder was selected."
    }

    $selectedFolder = $selectedFolder.Trim()

    Write-InstallerLog INFO "Selected folder: $selectedFolder"

    Send-GuiProgress 20 "Validating selected MATLAB folder"
    Write-InstallerLog INFO "Validating selected folder..."
    Validate-MatlabFolder -MatlabFolder $selectedFolder

    Send-GuiProgress 30 "Validating license file"
    Write-InstallerLog INFO "Validating license file..."
    Validate-LicenseFile -MatlabFolder $selectedFolder

    Send-GuiProgress 35 "Installing MATLAB"
    Write-InstallerLog INFO "Installing MATLAB..."
    Install-Matlab -MatlabFolder $selectedFolder

    Send-GuiProgress 85 "Configuring MATLAB license"
    Write-InstallerLog INFO "Configuring license..."
    Install-LicenseFile -MatlabFolder $selectedFolder

    Send-GuiProgress 100 "MATLAB install script finished"
    Write-InstallerLog INFO "Install script finished without errors!"
}

try {
    Invoke-Main
    $exitCode = 0
}
catch {
    Write-InstallerLog ERROR $_.Exception.Message
    Send-GuiProgress 100 "MATLAB install failed"
    $exitCode = 1
}
finally {
    Write-InstallerLog INFO "Log saved to $script:LogFile"
    [Console]::Out.WriteLine("Detailed MATLAB installer log saved to: $script:LogFile")
    [Console]::Out.Flush()

    if ($PauseOnExit) {
        Read-Host "Press Enter to exit"
    }
}

exit $exitCode

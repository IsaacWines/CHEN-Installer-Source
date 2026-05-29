# ~/powershell/COMSOL/COMSOL_installer.ps1
# ===========================================
# Installer PowerShell Script for COMSOL
# ===========================================
# Dynamically generates setupconfig.ini, supports express COMSOL 6.4 install/uninstall,
# version-specific setup.exe selection, GUI progress output, and reliable cleanup.

param(
    # Optional manual setup.exe override. Most GUI runs should leave this blank.
    [string]$InstallerPath = "",

    # Shared setupconfig.ini template used for every COMSOL version.
    [string]$SetupConfigUrl = "https://raw.githubusercontent.com/IsaacWines/CHEN-Installer-Source/refs/heads/main/powershell/COMSOL/setupconfig.ini",

    # Shared helper file downloaded beside this script by the GUI.
    [string]$CommonPath = "$PSScriptRoot\common.ps1",

    # Optional script behaviors.
    [switch]$NoComsolGui,
    [switch]$NoConfirm
)

$ErrorActionPreference = "Stop"
$script:FinalExitCode = 0

# ==========================
# Constants
# ==========================

$script:Comsol64VersionText = "6.4"
$script:Comsol64InstallDir = "C:\Program Files\COMSOL\COMSOL64\Multiphysics"
$script:Comsol64NetworkRelativeSetupPath = "Support\Software\Comsol Multiphysics\Software\Comsol 6.4\378\setup.exe"
$script:ComsolNetworkSoftwareRootRelativePath = "Support\Software\Comsol Multiphysics\Software"

$script:TempDir = "C:\Temp"
$script:DownloadedConfigPath = Join-Path $script:TempDir "setupconfig.comsol.downloaded.ini"
$script:FinalConfigPath = Join-Path $script:TempDir "setupconfig.ini"
$script:WrapperLogPath = Join-Path $script:TempDir "comsol_install_wrapper.log"
$script:InstallerOutputLogPath = Join-Path $script:TempDir "comsol_installer_output.log"

# ==========================
# Load common.ps1
# ==========================

if (Test-Path -Path $CommonPath -PathType Leaf) {
    . $CommonPath
}
else {
    [Console]::Out.WriteLine("WARNING: common.ps1 not found at: $CommonPath")
}

# Fallback only. Normal GUI flow should use Get-GuiNetworkRoot from common.ps1.
if (-not (Get-Command -Name Get-GuiNetworkRoot -ErrorAction SilentlyContinue)) {
    function Get-GuiNetworkRoot {
        if ([string]::IsNullOrWhiteSpace($env:CHEN_NETWORK_ROOT)) {
            return ""
        }

        $cleanRoot = $env:CHEN_NETWORK_ROOT.Trim().Replace("/", "\")
        $cleanRoot = $cleanRoot -replace "[\\\/]+$", ""

        if (-not $cleanRoot.StartsWith("\\")) {
            $cleanRoot = "\\" + ($cleanRoot -replace "^[\\\/]+", "")
        }

        return $cleanRoot
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

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Dock = "Fill"
    $textBox.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 6, 16, 6
    $textBox.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $textBox.Text = $DefaultValue
    $mainLayout.Controls.Add($textBox, 0, 2)

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

    $state = @{ Value = "" }

    $okButton.Add_Click({
        $state.Value = $textBox.Text.Trim()
        $form.Close()
    })

    $cancelButton.Add_Click({
        $state.Value = ""
        $form.Close()
    })

    $textBox.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $state.Value = $textBox.Text.Trim()
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
        [string]$Title = "CHEN COMSOL Installer"
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

function Show-ErrorPrompt {
    param(
        [string]$Message,
        [string]$Title = "CHEN COMSOL Installer"
    )

    Initialize-WindowsForms

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Show-TwoButtonChoice {
    param(
        [string]$Title,
        [string]$Message,
        [string]$LeftButtonText,
        [string]$RightButtonText
    )

    Initialize-WindowsForms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size -ArgumentList 650, 260
    $form.MinimumSize = New-Object System.Drawing.Size -ArgumentList 650, 260
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.FormBorderStyle = "FixedDialog"
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    $mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $mainLayout.Dock = "Fill"
    $mainLayout.ColumnCount = 1
    $mainLayout.RowCount = 4
    $mainLayout.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 24, 18, 24, 18
    $mainLayout.BackColor = $form.BackColor
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 54)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
    $form.Controls.Add($mainLayout)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.Dock = "Fill"
    $titleLabel.TextAlign = "MiddleCenter"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $mainLayout.Controls.Add($titleLabel, 0, 0)

    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Text = $Message
    $messageLabel.Dock = "Fill"
    $messageLabel.TextAlign = "MiddleCenter"
    $messageLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $messageLabel.ForeColor = [System.Drawing.Color]::FromArgb(35, 35, 35)
    $mainLayout.Controls.Add($messageLabel, 0, 1)

    $buttonPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $buttonPanel.Dock = "Fill"
    $buttonPanel.ColumnCount = 2
    $buttonPanel.RowCount = 1
    $buttonPanel.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 5, 16, 5
    [void]$buttonPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$buttonPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    $mainLayout.Controls.Add($buttonPanel, 0, 2)

    $leftButton = New-Object System.Windows.Forms.Button
    $leftButton.Text = $LeftButtonText
    $leftButton.Dock = "Fill"
    $leftButton.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 6, 6, 6, 6
    $leftButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $leftButton.FlatStyle = "Flat"
    $leftButton.BackColor = [System.Drawing.Color]::White
    $leftButton.UseVisualStyleBackColor = $false
    $buttonPanel.Controls.Add($leftButton, 0, 0)

    $rightButton = New-Object System.Windows.Forms.Button
    $rightButton.Text = $RightButtonText
    $rightButton.Dock = "Fill"
    $rightButton.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 6, 6, 6, 6
    $rightButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $rightButton.FlatStyle = "Flat"
    $rightButton.BackColor = [System.Drawing.Color]::White
    $rightButton.UseVisualStyleBackColor = $false
    $buttonPanel.Controls.Add($rightButton, 1, 0)

    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = "Fill"
    $bottomPanel.BackColor = $form.BackColor
    $mainLayout.Controls.Add($bottomPanel, 0, 3)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Width = 110
    $cancelButton.Height = 30
    $cancelButton.Location = New-Object System.Drawing.Point -ArgumentList 470, 7
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $cancelButton.FlatStyle = "Flat"
    $cancelButton.BackColor = [System.Drawing.Color]::WhiteSmoke
    $cancelButton.UseVisualStyleBackColor = $false
    $bottomPanel.Controls.Add($cancelButton)

    $selection = @{ Value = "Cancel" }

    $leftButton.Add_Click({ $selection.Value = "Left"; $form.Close() })
    $rightButton.Add_Click({ $selection.Value = "Right"; $form.Close() })
    $cancelButton.Add_Click({ $selection.Value = "Cancel"; $form.Close() })
    $form.CancelButton = $cancelButton

    [void]$form.ShowDialog()
    return $selection.Value
}

function Show-ComsolWorkflowPrompt {
    param(
        [string]$NetworkRoot
    )

    Initialize-WindowsForms

    $hasNetworkRoot = -not [string]::IsNullOrWhiteSpace($NetworkRoot)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select COMSOL Installer Mode"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size -ArgumentList 720, 410
    $form.MinimumSize = New-Object System.Drawing.Size -ArgumentList 720, 410
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.FormBorderStyle = "FixedDialog"
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    $mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $mainLayout.Dock = "Fill"
    $mainLayout.ColumnCount = 1
    $mainLayout.RowCount = 8
    $mainLayout.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 24, 18, 24, 18
    $mainLayout.BackColor = $form.BackColor
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
    $form.Controls.Add($mainLayout)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Choose COMSOL Action"
    $titleLabel.Dock = "Fill"
    $titleLabel.TextAlign = "MiddleCenter"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $mainLayout.Controls.Add($titleLabel, 0, 0)

    $networkLabel = New-Object System.Windows.Forms.Label
    $networkLabel.Dock = "Fill"
    $networkLabel.TextAlign = "MiddleCenter"
    $networkLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    if ($hasNetworkRoot) {
        $networkLabel.Text = "Network root received from GUI. Express network options are available."
        $networkLabel.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    }
    else {
        $networkLabel.Text = "No network root was received from the GUI. Only the no-network-root option is available."
        $networkLabel.ForeColor = [System.Drawing.Color]::DarkRed
    }
    $mainLayout.Controls.Add($networkLabel, 0, 1)

    $buttonFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)

    $expressInstallButton = New-Object System.Windows.Forms.Button
    $expressInstallButton.Text = "Express COMSOL 6.4 Install"
    $expressInstallButton.Dock = "Fill"
    $expressInstallButton.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 6, 16, 6
    $expressInstallButton.Font = $buttonFont
    $expressInstallButton.FlatStyle = "Flat"
    $expressInstallButton.BackColor = [System.Drawing.Color]::White
    $expressInstallButton.UseVisualStyleBackColor = $false
    $expressInstallButton.Enabled = $hasNetworkRoot
    if (-not $hasNetworkRoot) { $expressInstallButton.BackColor = [System.Drawing.Color]::Gainsboro }
    $mainLayout.Controls.Add($expressInstallButton, 0, 2)

    $expressUninstallButton = New-Object System.Windows.Forms.Button
    $expressUninstallButton.Text = "Express COMSOL 6.4 Uninstall"
    $expressUninstallButton.Dock = "Fill"
    $expressUninstallButton.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 6, 16, 6
    $expressUninstallButton.Font = $buttonFont
    $expressUninstallButton.FlatStyle = "Flat"
    $expressUninstallButton.BackColor = [System.Drawing.Color]::White
    $expressUninstallButton.UseVisualStyleBackColor = $false
    $expressUninstallButton.Enabled = $hasNetworkRoot
    if (-not $hasNetworkRoot) { $expressUninstallButton.BackColor = [System.Drawing.Color]::Gainsboro }
    $mainLayout.Controls.Add($expressUninstallButton, 0, 3)

    $networkPickButton = New-Object System.Windows.Forms.Button
    $networkPickButton.Text = "Pick COMSOL Version From Network Root"
    $networkPickButton.Dock = "Fill"
    $networkPickButton.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 6, 16, 6
    $networkPickButton.Font = $buttonFont
    $networkPickButton.FlatStyle = "Flat"
    $networkPickButton.BackColor = [System.Drawing.Color]::White
    $networkPickButton.UseVisualStyleBackColor = $false
    $networkPickButton.Enabled = $hasNetworkRoot
    if (-not $hasNetworkRoot) { $networkPickButton.BackColor = [System.Drawing.Color]::Gainsboro }
    $mainLayout.Controls.Add($networkPickButton, 0, 4)

    $noNetworkButton = New-Object System.Windows.Forms.Button
    $noNetworkButton.Text = "Pick setup.exe Without Network Root"
    $noNetworkButton.Dock = "Fill"
    $noNetworkButton.Margin = New-Object System.Windows.Forms.Padding -ArgumentList 16, 6, 16, 6
    $noNetworkButton.Font = $buttonFont
    $noNetworkButton.FlatStyle = "Flat"
    $noNetworkButton.BackColor = [System.Drawing.Color]::White
    $noNetworkButton.UseVisualStyleBackColor = $false
    $mainLayout.Controls.Add($noNetworkButton, 0, 5)

    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = "Fill"
    $bottomPanel.BackColor = $form.BackColor
    $mainLayout.Controls.Add($bottomPanel, 0, 7)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Width = 110
    $cancelButton.Height = 30
    $cancelButton.Location = New-Object System.Drawing.Point -ArgumentList 560, 7
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $cancelButton.FlatStyle = "Flat"
    $cancelButton.BackColor = [System.Drawing.Color]::WhiteSmoke
    $cancelButton.UseVisualStyleBackColor = $false
    $bottomPanel.Controls.Add($cancelButton)

    $selection = @{ Action = "Cancel" }

    $expressInstallButton.Add_Click({ $selection.Action = "Express64Install"; $form.Close() })
    $expressUninstallButton.Add_Click({ $selection.Action = "Express64Uninstall"; $form.Close() })
    $networkPickButton.Add_Click({ $selection.Action = "NetworkPick"; $form.Close() })
    $noNetworkButton.Add_Click({ $selection.Action = "NoNetworkPick"; $form.Close() })
    $cancelButton.Add_Click({ $selection.Action = "Cancel"; $form.Close() })
    $form.CancelButton = $cancelButton

    [void]$form.ShowDialog()
    return $selection.Action
}

function Show-ComsolSetupFilePicker {
    param(
        [string]$InitialDirectory = "C:\"
    )

    Initialize-WindowsForms

    if ([string]::IsNullOrWhiteSpace($InitialDirectory) -or -not (Test-Path -LiteralPath $InitialDirectory -PathType Container)) {
        $InitialDirectory = "C:\"
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select COMSOL setup.exe"
    $dialog.Filter = "COMSOL setup.exe|setup.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*"
    $dialog.CheckFileExists = $true
    $dialog.CheckPathExists = $true
    $dialog.Multiselect = $false
    $dialog.FileName = "setup.exe"
    $dialog.InitialDirectory = $InitialDirectory

    $result = $dialog.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return ""
    }

    return $dialog.FileName
}

# ==========================
# Logging / GUI progress
# ==========================

function Send-ProgressSafe {
    param(
        [int]$Percent,
        [string]$Message
    )

    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }

    $cmd = Get-Command -Name Send-GuiProgress -ErrorAction SilentlyContinue

    if ($null -ne $cmd) {
        try {
            Send-GuiProgress -Percent $Percent -Message $Message
            return
        }
        catch {
            # Fall through to plain progress format.
        }
    }

    [Console]::Out.WriteLine("CHEN_PROGRESS|$Percent|$Message")
    [Console]::Out.Flush()
}

function Write-GuiLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [int]$Percent = -1,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    if ($Level -eq "INFO") {
        $displayLine = $Message
    }
    else {
        $displayLine = "[$Level] $Message"
    }

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $fileLine = "$stamp [$Level] $Message"

    try {
        Add-Content -Path $script:WrapperLogPath -Value $fileLine
    }
    catch {
        # Do not fail script because logging failed.
    }

    if ($Percent -ge 0) {
        Send-ProgressSafe -Percent $Percent -Message $displayLine
    }
    else {
        [Console]::Out.WriteLine($displayLine)
        [Console]::Out.Flush()
    }
}

function Test-CurrentProcessIsAdmin {
    $cmd = Get-Command -Name Test-IsAdmin -ErrorAction SilentlyContinue

    if ($null -ne $cmd) {
        try {
            return [bool](Test-IsAdmin)
        }
        catch {
            Write-GuiLog -Message "Test-IsAdmin from common.ps1 failed; using fallback admin check." -Level "WARN"
        }
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-ComsolTempFiles {
    $filesToDelete = @(
        $script:DownloadedConfigPath,
        $script:FinalConfigPath
    )

    foreach ($file in $filesToDelete) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($file) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
                Remove-Item -LiteralPath $file -Force -ErrorAction Stop
                Write-GuiLog -Message "Deleted temporary file: $file"
            }
        }
        catch {
            Write-GuiLog -Message "Failed to delete temporary file: $file. Error: $($_.Exception.Message)" -Level "WARN"
        }
    }
}

# ==========================
# Path helpers
# ==========================

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

function Get-NativeFileSystemPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop | Select-Object -First 1

    if ($null -eq $resolved) {
        throw "Could not resolve path: $Path"
    }

    if ($resolved.Provider.Name -ne "FileSystem") {
        throw "Resolved path is not a FileSystem path: $Path"
    }

    return $resolved.ProviderPath
}

function Test-ComsolSetupExe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path

    return ($item.Name -eq "setup.exe")
}

function Get-ComsolInstallDirectoryForVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionText
    )

    $cleanVersion = $VersionText.Trim()
    $cleanVersion = $cleanVersion -replace "\s+", ""
    $cleanVersion = $cleanVersion -replace "\.", ""

    if ([string]::IsNullOrWhiteSpace($cleanVersion)) {
        throw "COMSOL version number cannot be blank."
    }

    return "C:\Program Files\COMSOL\COMSOL$cleanVersion\Multiphysics"
}

function Get-ComsolVersionFromUser {
    while ($true) {
        $version = Show-InputBox `
            -Title "COMSOL Version" `
            -Prompt "Enter the COMSOL version number for the selected setup.exe.`n`nExamples: 6.4, 6.3, 4.4a.`nThe dot will be removed when building the install directory." `
            -DefaultValue ""

        if (-not [string]::IsNullOrWhiteSpace($version)) {
            return $version.Trim()
        }

        $retry = Show-YesNoPrompt -Title "Required Version" -Message "A COMSOL version number is required. Do you want to try again?"
        if (-not $retry) {
            throw "COMSOL version entry was cancelled."
        }
    }
}

function Get-InstallModeFromTwoButtonPrompt {
    $choice = Show-TwoButtonChoice `
        -Title "Install or Uninstall" `
        -Message "Choose whether to install or uninstall the selected COMSOL version." `
        -LeftButtonText "Install" `
        -RightButtonText "Uninstall"

    switch ($choice) {
        "Left" { return "install" }
        "Right" { return "uninstall" }
        default { throw "Install/uninstall selection was cancelled." }
    }
}

# ==========================
# Prompt / workflow helpers
# ==========================

function Get-RequiredValue {
    param(
        [string]$CurrentValue,
        [string]$Prompt,
        [string]$Title,
        [string]$DefaultValue = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue.Trim()
    }

    while ($true) {
        $value = Show-InputBox -Prompt $Prompt -Title $Title -DefaultValue $DefaultValue

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }

        $retry = Show-YesNoPrompt -Title "Required Value" -Message "This value is required. Do you want to try again?"

        if (-not $retry) {
            throw "Required value was cancelled: $Title"
        }
    }
}

function Get-LicensePort {
    param(
        [string]$CurrentValue
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        $clean = $CurrentValue.Trim()
        $port = 0
        $valid = [int]::TryParse($clean, [ref]$port)

        if ($valid -and $port -ge 1 -and $port -le 65535) {
            return $clean
        }

        throw "Invalid license port passed from GUI. Must be a number from 1 to 65535."
    }

    while ($true) {
        $raw = Show-InputBox `
            -Title "COMSOL License Port" `
            -Prompt "Enter the COMSOL license server port." `
            -DefaultValue ""

        $raw = $raw.Trim()
        $port = 0
        $valid = [int]::TryParse($raw, [ref]$port)

        if ($valid -and $port -ge 1 -and $port -le 65535) {
            return $raw
        }

        $retry = Show-YesNoPrompt `
            -Title "Invalid Port" `
            -Message "The port must be a number from 1 to 65535. Do you want to try again?"

        if (-not $retry) {
            throw "Invalid port cancelled by user."
        }
    }
}

function Get-ComsolInstallDetails {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Workflow
    )

    if ($Workflow.InstallMode -eq "uninstall") {
        return [pscustomobject]@{
            InstallDir  = $Workflow.InstallDir
            InstallMode = "uninstall"
            License     = ""
            Port        = ""
            Server      = ""
            LicenseNo   = ""
            Name        = ""
            Company     = ""
        }
    }

    Write-GuiLog -Message "Collecting COMSOL license and user values." -Percent 10

    $finalPort = Get-LicensePort -CurrentValue ""

    $finalServer = Get-RequiredValue `
        -CurrentValue "" `
        -Title "COMSOL License Server" `
        -Prompt "Enter the COMSOL license server hostname." `
        -DefaultValue ""

    $finalLicenseNo = Get-RequiredValue `
        -CurrentValue "" `
        -Title "COMSOL License Number" `
        -Prompt "Enter the COMSOL license number to write to licno." `
        -DefaultValue ""

    $finalName = Get-RequiredValue `
        -CurrentValue "" `
        -Title "COMSOL User Name" `
        -Prompt "Enter the name of the person using COMSOL." `
        -DefaultValue ""

    $finalCompany = Get-RequiredValue `
        -CurrentValue "" `
        -Title "COMSOL Company / Organization" `
        -Prompt "Enter the company or organization name." `
        -DefaultValue ""

    return [pscustomobject]@{
        InstallDir  = $Workflow.InstallDir
        InstallMode = "install"
        Port        = $finalPort
        Server      = $finalServer
        LicenseNo   = $finalLicenseNo
        Name        = $finalName
        Company     = $finalCompany
        License     = "$finalPort@$finalServer"
    }
}

function Select-ComsolSetupFromNetworkRoot {
    param(
        [string]$NetworkRoot
    )

    if ([string]::IsNullOrWhiteSpace($NetworkRoot)) {
        throw "A GUI network root is required for this option."
    }

    $softwareRoot = Join-Path -Path $NetworkRoot -ChildPath $script:ComsolNetworkSoftwareRootRelativePath

    if (-not (Test-Path -LiteralPath $softwareRoot -PathType Container)) {
        throw "COMSOL network software root does not exist."
    }

    $selectedPath = Show-ComsolSetupFilePicker -InitialDirectory $softwareRoot

    if ([string]::IsNullOrWhiteSpace($selectedPath)) {
        throw "No setup.exe was selected. Cancelling installation."
    }

    if (-not (Test-ComsolSetupExe -Path $selectedPath)) {
        throw "Selected file must be named setup.exe."
    }

    return Get-NativeFileSystemPath -Path $selectedPath
}

function Select-ComsolSetupWithoutNetworkRoot {
    $selectedPath = Show-ComsolSetupFilePicker -InitialDirectory "C:\"

    if ([string]::IsNullOrWhiteSpace($selectedPath)) {
        throw "No setup.exe was selected. Cancelling installation."
    }

    if (-not (Test-ComsolSetupExe -Path $selectedPath)) {
        throw "Selected file must be named setup.exe."
    }

    return Get-NativeFileSystemPath -Path $selectedPath
}

function Get-ComsolWorkflow {
    param(
        [string]$ManualInstallerPath = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($ManualInstallerPath)) {
        if (-not (Test-ComsolSetupExe -Path $ManualInstallerPath)) {
            throw "Manual installer path must point to setup.exe."
        }

        $version = Get-ComsolVersionFromUser
        $installDir = Get-ComsolInstallDirectoryForVersion -VersionText $version
        $mode = Get-InstallModeFromTwoButtonPrompt

        return [pscustomobject]@{
            Action        = "ManualOverride"
            InstallerPath = Get-NativeFileSystemPath -Path $ManualInstallerPath
            VersionText   = $version
            InstallDir    = $installDir
            InstallMode   = $mode
        }
    }

    $networkRoot = Get-GuiNetworkRoot
    $action = Show-ComsolWorkflowPrompt -NetworkRoot $networkRoot

    switch ($action) {
        "Express64Install" {
            if ([string]::IsNullOrWhiteSpace($networkRoot)) {
                throw "Express COMSOL 6.4 install requires a GUI network root."
            }

            $candidatePath = Join-Path -Path $networkRoot -ChildPath $script:Comsol64NetworkRelativeSetupPath

            if (-not (Test-ComsolSetupExe -Path $candidatePath)) {
                throw "Express COMSOL 6.4 setup.exe was not found from the GUI network root."
            }

            return [pscustomObject]@{
                Action        = "Express64Install"
                InstallerPath = Get-NativeFileSystemPath -Path $candidatePath
                VersionText   = $script:Comsol64VersionText
                InstallDir    = $script:Comsol64InstallDir
                InstallMode   = "install"
            }
        }

        "Express64Uninstall" {
            if ([string]::IsNullOrWhiteSpace($networkRoot)) {
                throw "Express COMSOL 6.4 uninstall requires a GUI network root."
            }

            $candidatePath = Join-Path -Path $networkRoot -ChildPath $script:Comsol64NetworkRelativeSetupPath

            if (-not (Test-ComsolSetupExe -Path $candidatePath)) {
                throw "Express COMSOL 6.4 setup.exe was not found from the GUI network root."
            }

            return [pscustomObject]@{
                Action        = "Express64Uninstall"
                InstallerPath = Get-NativeFileSystemPath -Path $candidatePath
                VersionText   = $script:Comsol64VersionText
                InstallDir    = $script:Comsol64InstallDir
                InstallMode   = "uninstall"
            }
        }

        "NetworkPick" {
            $selectedSetup = Select-ComsolSetupFromNetworkRoot -NetworkRoot $networkRoot
            $version = Get-ComsolVersionFromUser
            $installDir = Get-ComsolInstallDirectoryForVersion -VersionText $version
            $mode = Get-InstallModeFromTwoButtonPrompt

            return [pscustomObject]@{
                Action        = "NetworkPick"
                InstallerPath = $selectedSetup
                VersionText   = $version
                InstallDir    = $installDir
                InstallMode   = $mode
            }
        }

        "NoNetworkPick" {
            $selectedSetup = Select-ComsolSetupWithoutNetworkRoot
            $version = Get-ComsolVersionFromUser
            $installDir = Get-ComsolInstallDirectoryForVersion -VersionText $version
            $mode = Get-InstallModeFromTwoButtonPrompt

            return [pscustomObject]@{
                Action        = "NoNetworkPick"
                InstallerPath = $selectedSetup
                VersionText   = $version
                InstallDir    = $installDir
                InstallMode   = $mode
            }
        }

        default {
            throw "COMSOL action selection was cancelled."
        }
    }
}

# ==========================
# setupconfig.ini helpers
# ==========================

function Set-ConfigValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigText,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [AllowEmptyString()]
        [string]$Value = ""
    )

    if ($null -eq $Value) {
        $Value = ""
    }

    $escapedKey = [regex]::Escape($Key)
    $pattern = "(?m)^\s*$escapedKey\s*=.*$"
    $replacement = "$Key = $Value"

    if ($ConfigText -match $pattern) {
        return [regex]::Replace($ConfigText, $pattern, $replacement)
    }

    return $ConfigText.TrimEnd() + "`r`n$replacement`r`n"
}

function Save-FileFromUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $cmd = Get-Command -Name Invoke-FileDownload -ErrorAction SilentlyContinue

    if ($null -ne $cmd) {
        try {
            Invoke-FileDownload -Url $Url -OutputPath $OutputPath
            return
        }
        catch {
            Write-GuiLog -Message "Invoke-FileDownload failed. Falling back to Invoke-WebRequest." -Level "WARN"
        }
    }

    Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
}

function New-ComsolSetupConfig {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter(Mandatory = $true)]
        [string]$SetupConfigUrl,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($SetupConfigUrl)) {
        $SetupConfigUrl = Get-RequiredValue `
            -CurrentValue "" `
            -Title "COMSOL SetupConfig URL" `
            -Prompt "Enter the online setupconfig.ini URL." `
            -DefaultValue ""
    }

    Write-GuiLog -Message "Downloading COMSOL setupconfig.ini template." -Percent 25

    Save-FileFromUrl -Url $SetupConfigUrl -OutputPath $script:DownloadedConfigPath

    if (-not (Test-Path -LiteralPath $script:DownloadedConfigPath -PathType Leaf)) {
        throw "Failed to download setupconfig.ini template."
    }

    Write-GuiLog -Message "Downloaded setupconfig template." -Percent 35

    $config = Get-Content -LiteralPath $script:DownloadedConfigPath -Raw

    Write-GuiLog -Message "Applying dynamic setupconfig.ini values." -Percent 45

    $config = Set-ConfigValue -ConfigText $config -Key "installdir"  -Value $Settings.InstallDir
    $config = Set-ConfigValue -ConfigText $config -Key "installmode" -Value $Settings.InstallMode

    if ($Settings.InstallMode -eq "install") {
        $config = Set-ConfigValue -ConfigText $config -Key "license"     -Value $Settings.License
        $config = Set-ConfigValue -ConfigText $config -Key "name"        -Value $Settings.Name
        $config = Set-ConfigValue -ConfigText $config -Key "company"     -Value $Settings.Company
        $config = Set-ConfigValue -ConfigText $config -Key "licno"       -Value $Settings.LicenseNo
    }
    else {
        # For uninstall, only installdir and installmode matter. Blank license/user-specific fields.
        $config = Set-ConfigValue -ConfigText $config -Key "license"     -Value ""
        $config = Set-ConfigValue -ConfigText $config -Key "name"        -Value ""
        $config = Set-ConfigValue -ConfigText $config -Key "company"     -Value ""
        $config = Set-ConfigValue -ConfigText $config -Key "licno"       -Value ""
    }

    # Leave lictype blank by design.
    $config = Set-ConfigValue -ConfigText $config -Key "lictype" -Value ""

    # Keep terminal output enabled.
    $config = Set-ConfigValue -ConfigText $config -Key "quiet" -Value "0"

    if ($NoComsolGui) {
        $config = Set-ConfigValue -ConfigText $config -Key "showgui" -Value "0"
    }
    else {
        $config = Set-ConfigValue -ConfigText $config -Key "showgui" -Value "1"
    }

    Set-Content -LiteralPath $OutputPath -Value $config -Encoding ASCII

    Write-GuiLog -Message "Final setupconfig.ini created in C:\Temp." -Percent 55
}

# ==========================
# Process capture
# ==========================

function Invoke-ProcessWithGuiOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$OutputLogPath
    )

    $debugLogPath = Join-Path $script:TempDir "comsol_launch_debug.log"

    function Write-LaunchDebug {
        param([string]$Message)

        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "$stamp [LAUNCH DEBUG] $Message"

        try { Add-Content -LiteralPath $debugLogPath -Value $line } catch {}
        try { Add-Content -LiteralPath $script:WrapperLogPath -Value $line } catch {}
    }

    try {
        if (Test-Path -LiteralPath $OutputLogPath -PathType Leaf) {
            Remove-Item -LiteralPath $OutputLogPath -Force
        }

        if (Test-Path -LiteralPath $debugLogPath -PathType Leaf) {
            Remove-Item -LiteralPath $debugLogPath -Force
        }

        Write-LaunchDebug "Entered Invoke-ProcessWithGuiOutput."

        if ([string]::IsNullOrWhiteSpace($FilePath)) {
            throw "Installer FilePath is blank before launch."
        }

        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            throw "setup.exe could not be found before launch."
        }

        $nativeSetupExe = Get-NativeFileSystemPath -Path $FilePath
        $setupExeName = Split-Path -Path $nativeSetupExe -Leaf
        $setupRoot = Split-Path -Path $nativeSetupExe -Parent

        Write-LaunchDebug "nativeSetupExe: $nativeSetupExe"
        Write-LaunchDebug "setupExeName: $setupExeName"
        Write-LaunchDebug "setupRoot: $setupRoot"

        if ($setupExeName -ne "setup.exe") {
            throw "Installer file must be named setup.exe."
        }

        if ([string]::IsNullOrWhiteSpace($setupRoot) -or -not (Test-Path -LiteralPath $setupRoot -PathType Container)) {
            throw "Installer root folder could not be resolved."
        }

        $setupConfigPath = ""
        if ($Arguments.Count -ge 2) {
            $setupConfigPath = $Arguments[1]
        }

        if ([string]::IsNullOrWhiteSpace($setupConfigPath)) {
            throw "setupconfig.ini path was blank before launch."
        }

        if (-not (Test-Path -LiteralPath $setupConfigPath -PathType Leaf)) {
            throw "setupconfig.ini could not be found before launch."
        }

        $nativeSetupConfig = Get-NativeFileSystemPath -Path $setupConfigPath

        Write-LaunchDebug "nativeSetupConfig: $nativeSetupConfig"
        Write-LaunchDebug "Validated setup.exe and setupconfig.ini."

        Write-GuiLog -Message "Launching COMSOL installer process."
        Write-GuiLog -Message "Running setup.exe from installer root."
        Write-GuiLog -Message "Installer output log will be kept."

        $safeSetupRoot = $setupRoot.Replace("'", "''")
        $safeSetupConfigPath = $nativeSetupConfig.Replace("'", "''")

        $command = @"
`$ErrorActionPreference = 'Stop'

Write-Output "COMSOL launch script started."
Write-Output "Starting location: `$((Get-Location).Path)"
Write-Output "Setup root exists: `$((Test-Path -LiteralPath '$safeSetupRoot' -PathType Container))"
Write-Output "Setupconfig exists: `$((Test-Path -LiteralPath '$safeSetupConfigPath' -PathType Leaf))"

Push-Location -LiteralPath '$safeSetupRoot'

try {
    Write-Output "COMSOL launch cwd: `$((Get-Location).Path)"
    Write-Output "COMSOL launch command: .\setup.exe -s <setupconfig.ini>"

    & .\setup.exe -s '$safeSetupConfigPath'

    `$exitCode = `$LASTEXITCODE

    if (`$null -eq `$exitCode) {
        `$exitCode = 0
    }

    Write-Output "COMSOL setup.exe returned exit code: `$exitCode"
    exit `$exitCode
}
finally {
    Pop-Location
}
"@

        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
        $psi.WorkingDirectory = $script:TempDir
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        Write-LaunchDebug "ProcessStartInfo created."
        Write-LaunchDebug "psi.FileName: $($psi.FileName)"
        Write-LaunchDebug "psi.WorkingDirectory: $($psi.WorkingDirectory)"
        Write-LaunchDebug "psi.UseShellExecute: $($psi.UseShellExecute)"

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.EnableRaisingEvents = $true

        $process.add_OutputDataReceived({
            param($sender, $eventArgs)

            if ($null -ne $eventArgs -and $null -ne $eventArgs.Data -and $eventArgs.Data.Trim() -ne "") {
                $displayLine = "[COMSOL STDOUT] $($eventArgs.Data)"
                $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $fileLine = "$stamp $displayLine"

                [Console]::Out.WriteLine($displayLine)
                [Console]::Out.Flush()

                Add-Content -Path $script:InstallerOutputLogPath -Value $fileLine
                Add-Content -Path $script:WrapperLogPath -Value $fileLine
            }
        })

        $process.add_ErrorDataReceived({
            param($sender, $eventArgs)

            if ($null -ne $eventArgs -and $null -ne $eventArgs.Data -and $eventArgs.Data.Trim() -ne "") {
                $displayLine = "[COMSOL STDERR] $($eventArgs.Data)"
                $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $fileLine = "$stamp $displayLine"

                [Console]::Out.WriteLine($displayLine)
                [Console]::Out.Flush()

                Add-Content -Path $script:InstallerOutputLogPath -Value $fileLine
                Add-Content -Path $script:WrapperLogPath -Value $fileLine
            }
        })

        Write-LaunchDebug "Starting child PowerShell process."

        $started = $process.Start()
        Write-LaunchDebug "process.Start() returned: $started"

        if (-not $started) {
            throw "Child PowerShell process did not start."
        }

        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()

        Write-GuiLog -Message "COMSOL installer is running." -Percent 65

        $lastProgressTime = Get-Date

        while (-not $process.HasExited) {
            Start-Sleep -Seconds 2

            $now = Get-Date
            if (($now - $lastProgressTime).TotalSeconds -ge 20) {
                Write-GuiLog -Message "COMSOL installer still running." -Percent 70
                $lastProgressTime = $now
            }

            try { $process.Refresh() } catch {}
        }

        $process.WaitForExit()
        Start-Sleep -Milliseconds 500

        $exitCode = $process.ExitCode
        Write-LaunchDebug "Final child PowerShell exit code: $exitCode"

        $process.Dispose()

        return $exitCode
    }
    catch {
        Write-LaunchDebug "ERROR in Invoke-ProcessWithGuiOutput: $($_.Exception.Message)"
        throw
    }
    finally {
        Write-GuiLog -Message "COMSOL launch debug log kept at: $debugLogPath"
    }
}

function Handle-ComsolExitCode {
    param(
        [int]$ExitCode
    )

    $script:FinalExitCode = $ExitCode

    switch ($ExitCode) {
        0 {
            Write-GuiLog -Message "COMSOL installer completed successfully." -Percent 100
        }
        1 {
            Write-GuiLog -Message "COMSOL installer completed with at least one warning. Check logs." -Percent 100 -Level "WARN"
        }
        2 {
            Write-GuiLog -Message "COMSOL installer completed with at least one error. Exit code 2." -Percent 100 -Level "ERROR"
        }
        3 {
            Write-GuiLog -Message "COMSOL installer completed with at least one fatal error. Exit code 3." -Percent 100 -Level "ERROR"
        }
        4 {
            Write-GuiLog -Message "COMSOL installer exited before installation completed. Exit code 4." -Percent 100 -Level "ERROR"
        }
        default {
            Write-GuiLog -Message "COMSOL installer failed with unexpected exit code $ExitCode." -Percent 100 -Level "ERROR"
        }
    }
}

# ==========================
# Main
# ==========================

try {
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    if (Test-Path -LiteralPath $script:WrapperLogPath -PathType Leaf) {
        Remove-Item -LiteralPath $script:WrapperLogPath -Force
    }

    Write-GuiLog -Message "Starting CHEN COMSOL installer wrapper." -Percent 1

    $apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
    if ($apartment -ne "STA") {
        Write-GuiLog -Message "PowerShell is not running in STA mode. Dialogs may behave incorrectly." -Level "WARN"
    }

    if (-not (Test-CurrentProcessIsAdmin)) {
        Write-GuiLog -Message "PowerShell is not running as Administrator. COMSOL may fail if system-level changes are required." -Percent 2 -Level "WARN"
    }

    $workflow = Get-ComsolWorkflow -ManualInstallerPath $InstallerPath

    Write-GuiLog -Message "COMSOL installer source selected." -Percent 8
    Write-GuiLog -Message "Selected action: $($workflow.Action)"
    Write-GuiLog -Message "Selected mode: $($workflow.InstallMode)"
    Write-GuiLog -Message "Selected COMSOL version: $($workflow.VersionText)"

    $settings = Get-ComsolInstallDetails -Workflow $workflow

    if ($settings.InstallMode -eq "install") {
        Write-GuiLog -Message "COMSOL install values received. Sensitive values will not be logged."
    }
    else {
        Write-GuiLog -Message "COMSOL uninstall selected. License/user prompts skipped."
    }

    New-ComsolSetupConfig `
        -Settings $settings `
        -SetupConfigUrl $SetupConfigUrl `
        -OutputPath $script:FinalConfigPath

    if (-not $NoConfirm) {
        $message = @"
COMSOL installer is ready to run.

Mode:
$($settings.InstallMode)

Install Directory:
$($settings.InstallDir)

Temporary setupconfig.ini was generated in C:\Temp.
Sensitive license values are not displayed here.

Run installer now?
"@

        $confirmed = Show-YesNoPrompt -Title "Run COMSOL Installer" -Message $message

        if (-not $confirmed) {
            $script:FinalExitCode = 1
            throw "User cancelled before running COMSOL installer."
        }
    }

    Write-GuiLog -Message "Launching COMSOL installer." -Percent 60

    $exitCode = Invoke-ProcessWithGuiOutput `
        -FilePath $workflow.InstallerPath `
        -Arguments @("-s", $script:FinalConfigPath) `
        -OutputLogPath $script:InstallerOutputLogPath

    Write-GuiLog -Message "COMSOL installer exited with code $exitCode." -Percent 90

    Handle-ComsolExitCode -ExitCode $exitCode
}
catch {
    if ($script:FinalExitCode -eq 0) {
        $script:FinalExitCode = 1
    }

    $errorMessage = "ERROR: $($_.Exception.Message)"
    Write-GuiLog -Message $errorMessage -Percent 100 -Level "ERROR"

    try {
        Show-ErrorPrompt -Message $errorMessage
    }
    catch {
        # Terminal/log output already has the error.
    }
}
finally {
    Write-GuiLog -Message "Cleaning up temporary setupconfig files."
    Remove-ComsolTempFiles
    Write-GuiLog -Message "Cleanup finished."
    Write-GuiLog -Message "Wrapper log kept at: $script:WrapperLogPath"
    Write-GuiLog -Message "Installer output log kept at: $script:InstallerOutputLogPath"
}

exit $script:FinalExitCode

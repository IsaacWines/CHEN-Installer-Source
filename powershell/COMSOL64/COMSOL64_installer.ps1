# ~/powershell/COMSOL64/COMSOL64_installer.ps1
#
# ===========================================
# Installer Powershell Script for COMSOL 6.4
# ===========================================
# ---
# Utilizes a dynamically generated setupconfig.ini
# ---

param(

  # GUI Network Root 
  [string]$NetworkRoot = "",

  # Optional Manual Override
  [string]$InstallerPath = "",

  # setupconfig.ini File From Repo
  [string]$SetupConfigUrl = "https://raw.githubusercontent.com/IsaacWines/CHEN-Installer-Source/refs/heads/testing/powershell/COMSOL64/setupconfig.ini",

  # Initialize Common GUI Helper and Script Functions
  [string]$CommonPath = "$PSScriptRoot\common.ps1",

  # COMSOL Install Path
  [string]$InstallDirectory = "C:\Program Files\COMSOL\COMSOL64\Multiphysics",

  # Values From GUI Prompts 
  [string]$InstallMode = "install",
  [string]$LicensePort = "",
  [string]$LicenseServer = "",
  [string]$ComsolUserName = "",
  [string]$CompanyName = "",

  # Optional Script Behaviors
  [switch]$NoComsolGui,
  [switch]$NoConfirm
)

$ErrorActionPreference = "Stop"

$script:COMSOL64NetworkRelativePath = "Support\Software\Comsol Multiphysics\Software\Comsol 6.4\378\setup.exe"

$script:TempDir = "C:\Temp"
$script:DownloadedConfigPath = Join-Path $script:TempDir "setupconfig.comsol64.downloaded.ini"
$script:FinalConfigPath = Join-Path $script:TempDir "setupconfig.ini"
$script:WrapperLogPath = Join-Path $script:TempDir "comsol64_install_wrapper.log"
$script:InstallerOutputLogPath = Join-Path $script:TempDir "comsol64_installer_output.log"

# ==========================
# Load common.ps1
# ==========================

if (Test-Path -Path $CommonPath -PathType Leaf) {
    . $CommonPath
}
else {
    [Console]::Out.WriteLine("WARNING: common.ps1 not found at: $CommonPath")
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

function Show-ComsolSetupFilePicker {
    param(
        [string]$InitialDirectory = ""
    )

    Initialize-WindowsForms

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select COMSOL 6.4 setup.exe"
    $dialog.Filter = "COMSOL setup.exe|setup.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*"
    $dialog.CheckFileExists = $true
    $dialog.CheckPathExists = $true
    $dialog.Multiselect = $false
    $dialog.FileName = "setup.exe"

    if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and (Test-Path -Path $InitialDirectory -PathType Container)) {
        $dialog.InitialDirectory = $InitialDirectory
    }

    $result = $dialog.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return ""
    }

    return $dialog.FileName
}

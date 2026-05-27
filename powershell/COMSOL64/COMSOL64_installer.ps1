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

# ==========================
# Logging / GUI progress
# ==========================

function Send-ProgressSafe {
    param(
        [int]$Percent,
        [string]$Message
    )

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

        [string]$Level = "INFO"
    )

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$stamp [$Level] $Message"

    [Console]::Out.WriteLine($line)
    [Console]::Out.Flush()

    try {
        Add-Content -Path $script:WrapperLogPath -Value $line
    }
    catch {
        # Do not fail script because logging failed.
    }

    if ($Percent -ge 0) {
        Send-ProgressSafe -Percent $Percent -Message $Message
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

    if ($item.Name -ne "setup.exe") {
        return $false
    }

    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($item.FullName)

    $checkText = @(
        $item.FullName
        $versionInfo.FileDescription
        $versionInfo.ProductName
        $versionInfo.CompanyName
        $versionInfo.OriginalFilename
    ) -join " "

    if ($checkText -match "(?i)comsol") {
        return $true
    }

    return $false
}

function Resolve-ComsolInstallerPath {
    param(
        [string]$NetworkRoot,
        [string]$ManualInstallerPath = ""
    )

    Write-GuiLog -Message "Resolving COMSOL 6.4 installer path." -Percent 3

    if (-not [string]::IsNullOrWhiteSpace($ManualInstallerPath)) {
        Write-GuiLog -Message "Manual installer path was provided."

        if (Test-ComsolSetupExe -Path $ManualInstallerPath) {
            Write-GuiLog -Message "Manual installer path verified."
            return (Resolve-Path -LiteralPath $ManualInstallerPath).Path
        }

        Write-GuiLog -Message "Manual installer path was not a valid COMSOL setup.exe. Falling back to NetworkRoot/file picker." -Level "WARN"
    }

    $normalizedRoot = Normalize-NetworkRoot -NetworkRoot $NetworkRoot

    if (-not [string]::IsNullOrWhiteSpace($normalizedRoot)) {
        $candidatePath = Join-Path -Path $normalizedRoot -ChildPath $script:COMSOL64NetworkRelativePath

        Write-GuiLog -Message "Checking COMSOL installer path from NetworkRoot."

        if (Test-ComsolSetupExe -Path $candidatePath) {
            Write-GuiLog -Message "Found COMSOL installer from NetworkRoot."
            return (Resolve-Path -LiteralPath $candidatePath).Path
        }

        Write-GuiLog -Message "NetworkRoot did not lead to a valid COMSOL setup.exe." -Level "WARN"
    }
    else {
        Write-GuiLog -Message "No NetworkRoot was provided." -Level "WARN"
    }

    Write-GuiLog -Message "Opening file picker for COMSOL setup.exe." -Percent 5

    $initialDir = ""
    if (-not [string]::IsNullOrWhiteSpace($normalizedRoot) -and (Test-Path -Path $normalizedRoot -PathType Container)) {
        $initialDir = $normalizedRoot
    }

    $selectedPath = Show-ComsolSetupFilePicker -InitialDirectory $initialDir

    if ([string]::IsNullOrWhiteSpace($selectedPath)) {
        throw "No COMSOL setup.exe was selected. Cancelling installation."
    }

    Write-GuiLog -Message "User selected an installer path."

    if (-not (Test-ComsolSetupExe -Path $selectedPath)) {
        throw "Selected file is not a valid COMSOL setup.exe."
    }

    Write-GuiLog -Message "Selected COMSOL setup.exe verified."
    return (Resolve-Path -LiteralPath $selectedPath).Path
}

# ==========================
# Prompt / validation helpers
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

function Get-InstallMode {
    param(
        [string]$CurrentValue
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        $clean = $CurrentValue.Trim().ToLower()

        if ($clean -in @("install", "uninstall")) {
            return $clean
        }

        throw "Invalid install mode passed from GUI. Must be install or uninstall."
    }

    while ($true) {
        $value = Show-InputBox `
            -Title "COMSOL Install Mode" `
            -Prompt "Enter install mode. Valid options are: install or uninstall." `
            -DefaultValue ""

        $value = $value.Trim().ToLower()

        if ($value -in @("install", "uninstall")) {
            return $value
        }

        $retry = Show-YesNoPrompt `
            -Title "Invalid Install Mode" `
            -Message "Install mode must be either install or uninstall. Do you want to try again?"

        if (-not $retry) {
            throw "Invalid install mode cancelled by user."
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

function Get-ComsolSettings {
    Write-GuiLog -Message "Collecting COMSOL setup values." -Percent 10

    $finalInstallDir = Get-RequiredValue `
        -CurrentValue $InstallDirectory `
        -Title "COMSOL Install Directory" `
        -Prompt "Enter the COMSOL install directory. For uninstall, this should be the existing COMSOL installation directory." `
        -DefaultValue "C:\Program Files\COMSOL\COMSOL64\Multiphysics"

    $finalInstallMode = Get-InstallMode -CurrentValue $InstallMode

    if ($finalInstallMode -eq "uninstall" -and -not (Test-Path -LiteralPath $finalInstallDir -PathType Container)) {
        throw "Install directory does not exist for uninstall mode."
    }

    $finalPort = Get-LicensePort -CurrentValue $LicensePort

    $finalServer = Get-RequiredValue `
        -CurrentValue $LicenseServer `
        -Title "COMSOL License Server" `
        -Prompt "Enter the COMSOL license server hostname." `
        -DefaultValue ""

    $finalName = Get-RequiredValue `
        -CurrentValue $ComsolUserName `
        -Title "COMSOL User Name" `
        -Prompt "Enter the name of the person using COMSOL." `
        -DefaultValue ""

    $finalCompany = Get-RequiredValue `
        -CurrentValue $CompanyName `
        -Title "COMSOL Company / Organization" `
        -Prompt "Enter the company or organization name." `
        -DefaultValue ""

    return [pscustomobject]@{
        InstallDir  = $finalInstallDir
        InstallMode = $finalInstallMode
        Port        = $finalPort
        Server      = $finalServer
        Name        = $finalName
        Company     = $finalCompany
        License     = "$finalPort@$finalServer"
    }
}

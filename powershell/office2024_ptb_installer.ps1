<#
CHEN Office 2024 PTB Installer

Purpose:
  Runs the Office 2024 PTB Office Deployment Tool setup from the network root
  entered in the CHEN Installer GUI.

Network root requirement:
  This script intentionally only uses CHEN_NETWORK_ROOT from the parent GUI.
  If no network root was typed into the GUI, the script refuses to run.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# ======================================================================================
# Load shared CHEN helper functions
# ======================================================================================
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CommonScriptPath = Join-Path $ScriptDirectory "common.ps1"

if (-not (Test-Path $CommonScriptPath)) {
    [Console]::Out.WriteLine("CHEN_PROGRESS|0|common.ps1 was not found next to office2024_ptb_installer.ps1.")
    [Console]::Out.Flush()
    Write-Error "common.ps1 was not found next to this script. Expected: $CommonScriptPath"
    exit 1
}

. $CommonScriptPath

# The uploaded/common common.ps1 expects Normalize-NetworkRoot to exist for Get-GuiNetworkRoot.
# Keep this local fallback so the installer works even if common.ps1 has not been updated yet.
if (-not (Get-Command Normalize-NetworkRoot -ErrorAction SilentlyContinue)) {
    function Normalize-NetworkRoot {
        param([string]$NetworkRoot)

        if ([string]::IsNullOrWhiteSpace($NetworkRoot)) {
            return ""
        }

        $normalized = $NetworkRoot.Trim().Trim('"')

        while ($normalized.EndsWith("\") -and $normalized.Length -gt 3) {
            $normalized = $normalized.Substring(0, $normalized.Length - 1)
        }

        return $normalized
    }
}

function Write-Step {
    param(
        [int]$Percent,
        [string]$Message
    )

    Send-GuiProgress -Percent $Percent -Message $Message
    Write-Host $Message
}

function Join-NetworkPath {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    $cleanRoot = Normalize-NetworkRoot -NetworkRoot $Root
    $cleanRelative = $RelativePath.TrimStart('\', '/')

    return Join-Path $cleanRoot $cleanRelative
}

$OfficeSetupRelativePath = "support\software\Microsoft\Software\Office\Windows\Office 2024\PTB\setup.exe"
$OfficeConfigRelativePath = "support\software\Microsoft\Software\Office\Windows\Office 2024\PTB\Office-24-x64.xml"
$SuccessExitCodes = @(0, 3010)

try {
    Write-Step -Percent 0 -Message "Starting Office 2024 PTB installer..."

    if (-not (Test-IsAdmin)) {
        throw "This installer must be run from an elevated/admin CHEN Installer GUI. Please restart the main GUI as Administrator."
    }

    Write-Step -Percent 5 -Message "Checking for GUI-provided network root..."

    if ([string]::IsNullOrWhiteSpace($env:CHEN_NETWORK_ROOT)) {
        throw "No network root was typed into the CHEN Installer GUI. This installer is not allowed to run without CHEN_NETWORK_ROOT."
    }

    $NetworkRoot = Get-GuiNetworkRoot

    if ([string]::IsNullOrWhiteSpace($NetworkRoot)) {
        throw "The GUI network root was blank or invalid. Type the network root in the CHEN Installer GUI and run this again."
    }

    Write-Host "Network root: $NetworkRoot"

    $SetupPath = Join-NetworkPath -Root $NetworkRoot -RelativePath $OfficeSetupRelativePath
    $ConfigPath = Join-NetworkPath -Root $NetworkRoot -RelativePath $OfficeConfigRelativePath

    Write-Step -Percent 15 -Message "Validating Office setup files..."
    Write-Host "Setup path:  $SetupPath"
    Write-Host "Config path: $ConfigPath"

    if (-not (Test-Path $SetupPath -PathType Leaf)) {
        throw "Office setup.exe was not found: $SetupPath"
    }

    if (-not (Test-Path $ConfigPath -PathType Leaf)) {
        throw "Office configuration XML was not found: $ConfigPath"
    }

    Write-Step -Percent 30 -Message "Running Office 2024 PTB setup..."
    Write-Host ""
    Write-Host "> `"$SetupPath`" /configure `"$ConfigPath`""
    Write-Host ""

    & $SetupPath /configure $ConfigPath
    $exitCode = $LASTEXITCODE

    Write-Host ""
    Write-Host "Office setup exited with code: $exitCode"

    if ($SuccessExitCodes -notcontains $exitCode) {
        throw "Office 2024 PTB setup failed with exit code $exitCode."
    }

    if ($exitCode -eq 3010) {
        Write-Step -Percent 95 -Message "Office installed successfully. Restart required."
        Write-Host "Office setup reported success, but Windows needs a restart."
    }
    else {
        Write-Step -Percent 95 -Message "Office installed successfully."
    }

    Write-Step -Percent 100 -Message "Office 2024 PTB installer finished."
    exit 0
}
catch {
    Send-GuiProgress -Percent 100 -Message "Office 2024 PTB installer failed."
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host ""
    exit 1
}

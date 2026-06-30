<#
CHEN PDFgear Installer

Place this file at:
  powershell/pdfgear_installer.ps1

Requires:
  powershell/common.ps1 in the same folder
  Chocolatey installed and available as choco.exe

Purpose:
  Installs or upgrades PDFgear for all users through Chocolatey.
  This script intentionally does not open its own GUI so the parent CHEN Installer
  GUI can capture terminal output and CHEN_PROGRESS messages.
#>

[CmdletBinding()]
param(
    # Optional Chocolatey source. Leave blank to use the machine's configured Chocolatey sources.
    [string]$ChocolateySource = "",

    # Creates a shortcut on the Public Desktop when PDFgear is found after install.
    [bool]$CreatePublicDesktopShortcut = $true
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# ======================================================================================
# Load shared CHEN helper functions
# ======================================================================================
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CommonScriptPath = Join-Path $ScriptDirectory "common.ps1"

if (-not (Test-Path $CommonScriptPath)) {
    [Console]::Out.WriteLine("CHEN_PROGRESS|0|common.ps1 was not found next to pdfgear_installer.ps1.")
    [Console]::Out.Flush()
    Write-Error "common.ps1 was not found next to this script. Expected: $CommonScriptPath"
    exit 1
}

. $CommonScriptPath

# Chocolatey enhanced exit codes:
# 0 = success, 1605 = already uninstalled, 1614 = product uninstalled,
# 1641/3010 = success but reboot required.
$ValidChocolateyExitCodes = @(0, 1605, 1614, 1641, 3010)

function Write-Step {
    param(
        [int]$Percent,
        [string]$Message
    )

    Send-GuiProgress -Percent $Percent -Message $Message
    Write-Host $Message
}

function Get-ChocoCommandPath {
    $command = Get-Command choco.exe -ErrorAction SilentlyContinue

    if ($null -ne $command) {
        return $command.Source
    }

    $defaultPath = Join-Path $env:ProgramData "chocolatey\bin\choco.exe"
    if (Test-Path $defaultPath -PathType Leaf) {
        return $defaultPath
    }

    return ""
}

function Test-PDFgearInstalled {
    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($root in $uninstallRoots) {
        if (-not (Test-Path $root)) {
            continue
        }

        $match = Get-ChildItem $root -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue } |
            Where-Object { $_.DisplayName -like "PDFgear*" } |
            Select-Object -First 1

        if ($null -ne $match) {
            return $true
        }
    }

    if (Test-Path (Join-Path $env:ProgramFiles "PDFgear") -PathType Container) {
        return $true
    }

    return $false
}

function Get-PDFgearExecutablePath {
    $installDir = Join-Path $env:ProgramFiles "PDFgear"

    $candidatePaths = @(
        (Join-Path $installDir "PDFLauncher.exe"),
        (Join-Path $installDir "PDFgear.exe")
    )

    foreach ($candidate in $candidatePaths) {
        if (Test-Path $candidate -PathType Leaf) {
            return $candidate
        }
    }

    if (Test-Path $installDir -PathType Container) {
        $exe = Get-ChildItem -Path $installDir -Filter "*.exe" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "PDF|Launcher|gear" } |
            Sort-Object Name |
            Select-Object -First 1

        if ($null -ne $exe) {
            return $exe.FullName
        }
    }

    return ""
}

function Ensure-PublicDesktopShortcut {
    $exePath = Get-PDFgearExecutablePath

    if ([string]::IsNullOrWhiteSpace($exePath)) {
        Write-Host "PDFgear executable was not found, so no Public Desktop shortcut was created."
        return
    }

    $shortcutPath = Join-Path $env:PUBLIC "Desktop\PDFgear.lnk"

    if (Test-Path $shortcutPath -PathType Leaf) {
        Write-Host "Public Desktop shortcut already exists: $shortcutPath"
        return
    }

    New-Shortcut -TargetPath $exePath -ShortcutPath $shortcutPath -Description "PDFgear PDF editor and reader"
    Write-Host "Created Public Desktop shortcut: $shortcutPath"
}

try {
    Write-Step -Percent 0 -Message "Starting PDFgear installer..."

    if (-not (Test-IsAdmin)) {
        throw "This installer must be run from an elevated/admin CHEN Installer GUI so PDFgear installs for all users. Please restart the main GUI as Administrator."
    }

    Write-Step -Percent 10 -Message "Checking for Chocolatey..."
    $chocoPath = Get-ChocoCommandPath

    if ([string]::IsNullOrWhiteSpace($chocoPath)) {
        throw "choco.exe was not found. Install Chocolatey first, then run this installer again."
    }

    Write-Host "Chocolatey path: $chocoPath"

    $alreadyInstalled = Test-PDFgearInstalled
    if ($alreadyInstalled) {
        Write-Step -Percent 20 -Message "PDFgear is already installed. Running Chocolatey upgrade..."
    }
    else {
        Write-Step -Percent 20 -Message "PDFgear is not installed. Running Chocolatey install..."
    }

    $chocoArgs = @("upgrade", "pdfgear", "-y", "--no-progress")

    if (-not [string]::IsNullOrWhiteSpace($ChocolateySource)) {
        $chocoArgs += @("--source", $ChocolateySource)
        Write-Host "Chocolatey source: $ChocolateySource"
    }

    Write-Step -Percent 35 -Message "Installing PDFgear through Chocolatey..."
    Write-Host ""
    Write-Host "> `"$chocoPath`" $($chocoArgs -join ' ')"
    Write-Host ""

    & $chocoPath @chocoArgs
    $exitCode = $LASTEXITCODE

    Write-Host ""
    Write-Host "Chocolatey exited with code: $exitCode"

    if ($ValidChocolateyExitCodes -notcontains $exitCode) {
        throw "Chocolatey failed while installing PDFgear. Exit code: $exitCode"
    }

    if ($exitCode -eq 3010 -or $exitCode -eq 1641) {
        Write-Host "Chocolatey reported success, but Windows may need a restart."
    }

    Write-Step -Percent 80 -Message "Verifying PDFgear installation..."

    if (-not (Test-PDFgearInstalled)) {
        throw "Chocolatey finished, but PDFgear could not be detected in HKLM uninstall registry or Program Files."
    }

    $pdfgearExe = Get-PDFgearExecutablePath
    if (-not [string]::IsNullOrWhiteSpace($pdfgearExe)) {
        Write-Host "PDFgear executable: $pdfgearExe"
    }
    else {
        Write-Host "PDFgear install was detected, but the executable path could not be resolved automatically."
    }

    if ($CreatePublicDesktopShortcut) {
        Write-Step -Percent 90 -Message "Creating all-users desktop shortcut if needed..."
        Ensure-PublicDesktopShortcut
    }

    Write-Step -Percent 100 -Message "PDFgear installed successfully for all users."
    exit 0
}
catch {
    Send-GuiProgress -Percent 100 -Message "PDFgear installer failed."
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host ""
    exit 1
}

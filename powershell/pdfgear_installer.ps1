<#
CHEN PDFgear Installer

Purpose:
  Installs or upgrades PDFgear through Chocolatey.
  No GUI is opened by this script.
  Output is written to the parent CHEN Installer terminal.
  Progress is sent using CHEN_PROGRESS through common.ps1.

Important:
  This script intentionally does NOT inspect the Windows uninstall registry.
  It does NOT use DisplayName.
  It does NOT create shortcuts.
  It does NOT try to manually detect PDFgear through Program Files.
#>

[CmdletBinding()]
param(
    [string]$ChocolateySource = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CommonScriptPath = Join-Path $ScriptDirectory "common.ps1"

if (-not (Test-Path $CommonScriptPath -PathType Leaf)) {
    [Console]::Out.WriteLine("CHEN_PROGRESS|100|PDFgear installer failed.")
    [Console]::Out.Flush()
    Write-Host "ERROR: common.ps1 was not found next to pdfgear_installer.ps1."
    Write-Host "Expected: $CommonScriptPath"
    exit 1
}

. $CommonScriptPath

$PackageName = "pdfgear"

# Chocolatey success codes:
# 0    = success
# 1605 = product already uninstalled
# 1614 = product uninstalled
# 1641 = success, reboot initiated
# 3010 = success, reboot required
$ValidChocolateyExitCodes = @(0, 1605, 1614, 1641, 3010)

function Set-ChenProgress {
    param(
        [int]$Percent,
        [string]$Message
    )

    Send-GuiProgress -Percent $Percent -Message $Message
}

function Write-ChenLog {
    param(
        [string]$Message = ""
    )

    Write-Host $Message
}

function Get-ChocoPath {
    $command = Get-Command "choco.exe" -ErrorAction SilentlyContinue

    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    $fallbackPath = Join-Path $env:ProgramData "chocolatey\bin\choco.exe"

    if (Test-Path $fallbackPath -PathType Leaf) {
        return $fallbackPath
    }

    return ""
}

function Test-ChocoPackageInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChocoPath,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $output = & $ChocoPath list --local-only --exact $Name --limit-output 2>$null
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        return $false
    }

    foreach ($line in @($output)) {
        if ($line -match "^$([regex]::Escape($Name))\|") {
            return $true
        }
    }

    return $false
}

try {
    Set-ChenProgress -Percent 0 -Message "Starting PDFgear installer..."

    Write-ChenLog "Starting PDFgear installer."
    Write-ChenLog "Script version: 2026-06-30-simple-choco-only"
    Write-ChenLog ""

    if (-not (Test-IsAdmin)) {
        throw "The CHEN Installer GUI must be run as Administrator before installing PDFgear."
    }

    Set-ChenProgress -Percent 10 -Message "Checking for Chocolatey..."
    Write-ChenLog "Checking for Chocolatey..."

    $chocoPath = Get-ChocoPath

    if ([string]::IsNullOrWhiteSpace($chocoPath)) {
        throw "choco.exe was not found. Install Chocolatey first, then run this installer again."
    }

    Write-ChenLog "Chocolatey path: $chocoPath"
    Write-ChenLog ""

    Set-ChenProgress -Percent 20 -Message "Checking current Chocolatey package state..."

    $wasInstalled = Test-ChocoPackageInstalled -ChocoPath $chocoPath -Name $PackageName

    if ($wasInstalled) {
        Write-ChenLog "Chocolatey package '$PackageName' is already installed. Running upgrade to make sure it is current."
    }
    else {
        Write-ChenLog "Chocolatey package '$PackageName' is not installed. Running install through choco upgrade."
    }

    $chocoArgs = @(
        "upgrade",
        $PackageName,
        "-y",
        "--no-progress"
    )

    if (-not [string]::IsNullOrWhiteSpace($ChocolateySource)) {
        $chocoArgs += @("--source", $ChocolateySource)
        Write-ChenLog "Chocolatey source override: $ChocolateySource"
    }

    Write-ChenLog ""
    Write-ChenLog "Command:"
    Write-ChenLog "`"$chocoPath`" $($chocoArgs -join ' ')"
    Write-ChenLog ""

    Set-ChenProgress -Percent 35 -Message "Installing PDFgear through Chocolatey..."

    & $chocoPath @chocoArgs
    $chocoExitCode = $LASTEXITCODE

    Write-ChenLog ""
    Write-ChenLog "Chocolatey exit code: $chocoExitCode"

    if ($ValidChocolateyExitCodes -notcontains $chocoExitCode) {
        throw "Chocolatey failed while installing PDFgear. Exit code: $chocoExitCode."
    }

    if ($chocoExitCode -eq 1641 -or $chocoExitCode -eq 3010) {
        Write-ChenLog "Chocolatey reported success, but Windows may require a restart."
    }

    Set-ChenProgress -Percent 85 -Message "Verifying Chocolatey package registration..."

    $isInstalled = Test-ChocoPackageInstalled -ChocoPath $chocoPath -Name $PackageName

    if (-not $isInstalled) {
        throw "Chocolatey completed, but '$PackageName' is not listed as a locally installed Chocolatey package."
    }

    Write-ChenLog ""
    Write-ChenLog "PDFgear is installed according to Chocolatey."
    Write-ChenLog "Installer completed successfully."

    Set-ChenProgress -Percent 100 -Message "PDFgear installed successfully."
    exit 0
}
catch {
    Set-ChenProgress -Percent 100 -Message "PDFgear installer failed."

    Write-ChenLog ""
    Write-ChenLog "ERROR: $($_.Exception.Message)"
    Write-ChenLog ""

    exit 1
}

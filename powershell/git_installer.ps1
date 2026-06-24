<#
CHEN Git Installer

Place this file at:
  powershell/git_installer.ps1

Requires:
  powershell/common.ps1 in the same folder
  Chocolatey installed and available as choco.exe

Purpose:
  Installs or upgrades Git for Windows through Chocolatey.
  This script intentionally does not open its own GUI so the parent CHEN Installer
  GUI can capture terminal output and CHEN_PROGRESS messages.
#>

[CmdletBinding()]
param(
    # Optional Chocolatey source. Leave blank to use the machine's configured Chocolatey sources.
    [string]$ChocolateySource = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# ======================================================================================
# Load shared CHEN helper functions
# ======================================================================================
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CommonScriptPath = Join-Path $ScriptDirectory "common.ps1"

if (-not (Test-Path $CommonScriptPath)) {
    [Console]::Out.WriteLine("CHEN_PROGRESS|0|common.ps1 was not found next to git_installer.ps1.")
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

function Normalize-PathSegment {
    param([string]$Segment)

    if ([string]::IsNullOrWhiteSpace($Segment)) {
        return ""
    }

    $normalized = $Segment.Trim().Trim('"')

    while ($normalized.EndsWith("\") -and $normalized.Length -gt 3) {
        $normalized = $normalized.Substring(0, $normalized.Length - 1)
    }

    return $normalized
}

function Get-MachinePathSegments {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    if ([string]::IsNullOrWhiteSpace($machinePath)) {
        return @()
    }

    return @(
        $machinePath.Split(';') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { Normalize-PathSegment -Segment $_ }
    )
}

function Set-MachinePathSegments {
    param([string[]]$Segments)

    $cleanSegments = @(
        $Segments |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { Normalize-PathSegment -Segment $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    [Environment]::SetEnvironmentVariable("Path", ($cleanSegments -join ';'), "Machine")

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ([string]::IsNullOrWhiteSpace($userPath)) {
        $env:Path = $machinePath
    }
    elseif ([string]::IsNullOrWhiteSpace($machinePath)) {
        $env:Path = $userPath
    }
    else {
        $env:Path = "$machinePath;$userPath"
    }
}

function Test-MachinePathContains {
    param([string]$PathEntry)

    $target = Normalize-PathSegment -Segment $PathEntry
    $segments = Get-MachinePathSegments

    foreach ($segment in $segments) {
        if ($segment.Equals($target, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Add-MachinePathEntry {
    param([string]$PathEntry)

    $normalizedEntry = Normalize-PathSegment -Segment $PathEntry

    if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
        return
    }

    if (Test-MachinePathContains -PathEntry $normalizedEntry) {
        Write-Host "PATH already contains: $normalizedEntry"
        return
    }

    $segments = @(Get-MachinePathSegments)
    $segments += $normalizedEntry
    Set-MachinePathSegments -Segments $segments

    Write-Host "Added to SYSTEM Path: $normalizedEntry"
}

function Get-ChocolateyCommand {
    $command = Get-Command "choco.exe" -ErrorAction SilentlyContinue

    if ($null -eq $command) {
        throw "Chocolatey was not found on PATH. Install Chocolatey first, then run this installer again."
    }

    return $command.Source
}

function Invoke-Choco {
    param(
        [string]$ChocoPath,
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host "> choco $($Arguments -join ' ')"
    Write-Host ""

    & $ChocoPath @Arguments
    $exitCode = $LASTEXITCODE

    if ($ValidChocolateyExitCodes -notcontains $exitCode) {
        throw "Chocolatey failed with exit code $exitCode."
    }

    if ($exitCode -eq 1641 -or $exitCode -eq 3010) {
        Write-Host "Chocolatey reported success, but Windows may need a restart. Exit code: $exitCode"
    }

    return $exitCode
}

function Test-ChocoPackageInstalled {
    param(
        [string]$ChocoPath,
        [string]$PackageName
    )

    $output = & $ChocoPath list --local-only --exact $PackageName --limit-output 2>$null
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        return $false
    }

    foreach ($line in @($output)) {
        if ($line -match "^$([regex]::Escape($PackageName))\|") {
            return $true
        }
    }

    return $false
}

function Get-GitCmdPath {
    $candidateRoots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    )

    foreach ($root in $candidateRoots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        $candidate = Join-Path $root "Git\cmd"

        if (Test-Path (Join-Path $candidate "git.exe")) {
            return $candidate
        }
    }

    return ""
}

try {
    Write-Step -Percent 5 -Message "Starting Git installer..."

    if (-not (Test-IsAdmin)) {
        throw "This installer must be run as Administrator. Launch the main CHEN Installer GUI as Administrator, then run Git Installer again."
    }

    Write-Step -Percent 15 -Message "Checking Chocolatey..."
    $chocoPath = Get-ChocolateyCommand
    Write-Host "Chocolatey found at: $chocoPath"

    Write-Step -Percent 25 -Message "Checking current Git package state..."
    $gitIsInstalled = Test-ChocoPackageInstalled -ChocoPath $chocoPath -PackageName "git"

    $chocoArgs = @()

    if ($gitIsInstalled) {
        Write-Host "Git is already installed by Chocolatey. Running upgrade to make sure it is current."
        $chocoArgs = @("upgrade", "git", "-y", "--no-progress", "--execution-timeout=2700")
    }
    else {
        Write-Host "Git is not installed by Chocolatey. Running install."
        $chocoArgs = @("install", "git", "-y", "--no-progress", "--execution-timeout=2700")
    }

    if (-not [string]::IsNullOrWhiteSpace($ChocolateySource)) {
        $chocoArgs += @("--source", $ChocolateySource)
    }

    Write-Step -Percent 45 -Message "Installing or updating Git with Chocolatey..."
    Invoke-Choco -ChocoPath $chocoPath -Arguments $chocoArgs | Out-Null

    Write-Step -Percent 80 -Message "Checking Git PATH entry..."
    $gitCmdPath = Get-GitCmdPath

    if ([string]::IsNullOrWhiteSpace($gitCmdPath)) {
        Write-Host "Git install path was not found at the usual Program Files locations. Checking git.exe from PATH instead."
    }
    else {
        Add-MachinePathEntry -PathEntry $gitCmdPath
    }

    Write-Step -Percent 90 -Message "Verifying Git installation..."

    $gitExeToRun = ""
    $gitCommand = Get-Command "git.exe" -ErrorAction SilentlyContinue

    if ($null -ne $gitCommand) {
        $gitExeToRun = $gitCommand.Source
    }
    elseif (-not [string]::IsNullOrWhiteSpace($gitCmdPath)) {
        $gitExePath = Join-Path $gitCmdPath "git.exe"
        if (Test-Path $gitExePath) {
            $gitExeToRun = $gitExePath
        }
    }

    if ([string]::IsNullOrWhiteSpace($gitExeToRun)) {
        throw "Git installation completed, but git.exe could not be found. A new terminal or reboot may be required."
    }

    $gitVersion = & $gitExeToRun --version
    Write-Host "Verified: $gitVersion"
    Write-Host "Git executable: $gitExeToRun"

    Write-Step -Percent 100 -Message "Git installation complete."
    exit 0
}
catch {
    $errorMessage = $_.Exception.Message
    Send-GuiProgress -Percent 100 -Message "Git installation failed."
    Write-Error $errorMessage
    exit 1
}

# Shared helper functions for CHEN Installer scripts

function Send-GuiProgress {
    param(
        [int]$Percent,
        [string]$Message
    )

    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }

    Write-Output "CHEN_PROGRESS|$Percent|$Message"
}

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-Shortcut {
    param(
        [string]$TargetPath,
        [string]$ShortcutPath,
        [string]$Description = ""
    )

    if (-not (Test-Path $TargetPath)) {
        Write-Error "Shortcut target not found: $TargetPath"
        exit 1
    }

    $shortcutFolder = Split-Path $ShortcutPath -Parent

    if (-not (Test-Path $shortcutFolder)) {
        New-Item -ItemType Directory -Force -Path $shortcutFolder | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)

    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = Split-Path $TargetPath -Parent
    $shortcut.IconLocation = $TargetPath
    $shortcut.Description = $Description

    $shortcut.Save()
}

function Get-DownloadFileName {
    param(
        [string]$Url
    )

    return Split-Path ([Uri]$Url).AbsolutePath -Leaf
}

function Invoke-FileDownload {
    param(
        [string]$Url,
        [string]$OutputPath
    )

    $downloadFolder = Split-Path $OutputPath -Parent

    if (-not (Test-Path $downloadFolder)) {
        New-Item -ItemType Directory -Force -Path $downloadFolder | Out-Null
    }

    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force
    }

    $oldProgressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"

    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
    }
    finally {
        $ProgressPreference = $oldProgressPreference
    }

    if (-not (Test-Path $OutputPath)) {
        Write-Error "Download failed. File was not created: $OutputPath"
        exit 1
    }
}

function Expand-ZipToFolder {
    param(
        [string]$ZipPath,
        [string]$DestinationPath
    )

    if (-not (Test-Path $ZipPath)) {
        Write-Error "Zip file not found: $ZipPath"
        exit 1
    }

    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
    }

    Expand-Archive -Path $ZipPath -DestinationPath $DestinationPath -Force
}

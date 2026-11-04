# Shared helper functions for CHEN Installer scripts

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

function Get-GuiNetworkRoot {
    param(
        [string]$NetworkRootParameter = ""
    )

    # GUI provides the root through CHEN_NETWORK_ROOT.
    if (-not [string]::IsNullOrWhiteSpace($env:CHEN_NETWORK_ROOT)) {
        return Normalize-NetworkRoot -NetworkRoot $env:CHEN_NETWORK_ROOT
    }

    # Optional fallback for manual command-line testing.
    if (-not [string]::IsNullOrWhiteSpace($NetworkRootParameter)) {
        return Normalize-NetworkRoot -NetworkRoot $NetworkRootParameter
    }

    return ""
}

# Package-manager helpers shared by Steam, ArcGIS prerequisites and system tools.
function Get-ChenWinget {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $command) { throw 'WinGet is unavailable for this account. Install/update Microsoft App Installer, open it once, then restart CHEN. These scripts do not support the SYSTEM account.' }
    return $command.Source
}

function New-ChenLogDirectory {
    param([string]$Name)
    $root = $env:CHEN_LOG_ROOT
    if (-not $root) { $root = Join-Path $env:LOCALAPPDATA 'CHENInstaller\Logs' }
    $id = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N')
    $path = Join-Path $root ($Name + '_' + $id)
    [void](New-Item -ItemType Directory -Path $path -Force)
    return $path
}

function Get-ChenWingetArguments {
    param([string]$Id, [string]$LogPath, [string]$Architecture = '', [string]$Scope = '')
    $allowed = @('Valve.Steam', 'BitSum.ParkControl', 'REALiX.HWiNFO', 'Microsoft.DotNet.DesktopRuntime.8', 'Microsoft.DotNet.DesktopRuntime.10', 'Microsoft.EdgeWebView2Runtime')
    if ($Id -cnotin $allowed) { throw "Unsupported package ID: $Id" }
    if ($Architecture -and $Architecture -notin @('x64', 'arm64', 'x86')) { throw 'Invalid architecture.' }
    if ($Scope -and $Scope -notin @('machine', 'user')) { throw 'Invalid install scope.' }
    $arguments = @('install', '--id', $Id, '--exact', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity', '--log', $LogPath)
    if ($Architecture) { $arguments += @('--architecture', $Architecture) }
    if ($Scope) { $arguments += @('--scope', $Scope) }
    return $arguments
}

function Get-ChenWingetOutcome {
    param([long]$Code)
    # Normalize unsigned HRESULTs as well as native signed process exit codes.
    if ($Code -gt [int]::MaxValue) { $Code -= 4294967296 }
    switch ($Code) {
        { $_ -in @(0, -1978335189, -1978335135) } { return 'Success' }
        { $_ -in @(3010, -1978334967) } { return 'RestartRequired' }
        { $_ -in @(1641, -1978334965) } { return 'RestartInitiated' }
        default { return 'Failed' }
    }
}

function Invoke-ChenNativeWinget {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments | ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
}

function Invoke-ChenWingetPackage {
    param([string]$Id, [string]$LogDirectory, [string]$Architecture = '', [string]$Scope = '')
    $exe = Get-ChenWinget
    $arguments = @(Get-ChenWingetArguments -Id $Id -LogPath (Join-Path $LogDirectory "$Id-winget.log") -Architecture $Architecture -Scope $Scope)
    Write-Host "Installing/updating $Id using the exact WinGet community package."
    $code = Invoke-ChenNativeWinget -Executable $exe -Arguments $arguments
    $outcome = Get-ChenWingetOutcome -Code $code
    if ($outcome -eq 'Failed') { throw "WinGet failed for $Id (exit $code). Review $LogDirectory. A hash/source/policy error is not bypassed; update App Installer or its winget source and retry." }
    if ($outcome -like 'Restart*') { Write-Host "$Id requires a Windows restart." }
    return [pscustomobject]@{ Package=$Id; Outcome=$outcome; ExitCode=$code }
}

function Get-ChenNativeArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    switch ($architecture) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        'x86' { return 'x86' }
        default { throw 'Unable to detect Windows architecture.' }
    }
}

<# Installs/updates the Steam client. Does not uninstall Steam, change libraries or install games. #>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'common.ps1')

function Invoke-ChenSteamInstaller {
    $ErrorActionPreference = 'Stop'
    try {
        if ($env:OS -ne 'Windows_NT') { throw 'Steam Installer requires Windows.' }
        Send-GuiProgress 5 'Checking Windows Package Manager...'
        [void](Get-ChenWinget)
        $logs = New-ChenLogDirectory 'Steam'
        Send-GuiProgress 20 'Installing/updating Steam...'
        $result = Invoke-ChenWingetPackage -Id 'Valve.Steam' -LogDirectory $logs
        $result | ConvertTo-Json | Set-Content (Join-Path $logs 'results.json') -Encoding UTF8
        if ($result.Outcome -eq 'RestartInitiated') { Write-Host 'Windows restart initiated.' }
        Send-GuiProgress 100 'Steam client installation complete.'
        Write-Host "Logs: $logs"
        Write-Host 'Open Steam from the Start menu as your normal user. Sign in to download your games; Steam manages its own client updates.'
        return 0
    }
    catch { Write-Host "ERROR: $($_.Exception.Message)"; return 1 }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-ChenSteamInstaller) }

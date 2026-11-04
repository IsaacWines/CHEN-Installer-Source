<# Power management and monitoring for an Intel x64 Spectre. Does not claim HP firmware fan support. #>
[CmdletBinding()]
param([ValidateSet('Both', 'ParkControl', 'HWiNFO')][string]$Tools = 'Both', [switch]$NoUI)
. (Join-Path $PSScriptRoot 'common.ps1')

function Get-ChenSystemToolPackages {
    param([string]$Selection)
    switch ($Selection) {
        'Both' { return @('BitSum.ParkControl', 'REALiX.HWiNFO') }
        'ParkControl' { return @('BitSum.ParkControl') }
        'HWiNFO' { return @('REALiX.HWiNFO') }
        default { throw 'Choose Both, ParkControl or HWiNFO.' }
    }
}

function Show-ChenSystemToolSelector {
    param([string]$Initial)
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'CHEN | System Control Tools'
    $form.ClientSize = New-Object System.Drawing.Size(620, 300)
    $form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds(20, 20, 580, 95)
    $info.Text = "Lightweight power controls and hardware monitoring for your Spectre.`r`nThese tools do not replace HP-specific thermal/fan profiles. The installer does not change power settings or remove HP software.`r`nHWiNFO Free is for non-commercial use; organizational use requires the appropriate license."
    $form.Controls.Add($info)
    $power = New-Object System.Windows.Forms.CheckBox
    $power.Text = 'ParkControl - power plans and CPU power settings'; $power.SetBounds(20, 130, 580, 28)
    $power.Checked = $Initial -in @('Both', 'ParkControl'); $form.Controls.Add($power)
    $monitor = New-Object System.Windows.Forms.CheckBox
    $monitor.Text = 'HWiNFO - CPU/GPU temperatures, sensors and throttling'; $monitor.SetBounds(20, 168, 580, 28)
    $monitor.Checked = $Initial -in @('Both', 'HWiNFO'); $form.Controls.Add($monitor)
    $install = New-Object System.Windows.Forms.Button
    $install.Text = 'Install selected'; $install.SetBounds(350, 240, 130, 35)
    $install.Add_Click({
        if (-not $power.Checked -and -not $monitor.Checked) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Select at least one tool.'); return }
        $form.Tag = 'Both'
        if (-not $power.Checked) { $form.Tag = 'HWiNFO' }
        if (-not $monitor.Checked) { $form.Tag = 'ParkControl' }
        $form.DialogResult = 'OK'; $form.Close()
    })
    $form.Controls.Add($install)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.SetBounds(490, 240, 110, 35); $cancel.DialogResult = 'Cancel'
    $form.Controls.Add($cancel); $form.CancelButton = $cancel
    try { if ($form.ShowDialog() -eq 'OK') { return $form.Tag }; return $null }
    finally { $form.Dispose() }
}

function Invoke-ChenSystemTools {
    param([string]$Selection, [bool]$Headless)
    $ErrorActionPreference = 'Stop'
    try {
        if ($env:OS -ne 'Windows_NT') { throw 'System Control Tools requires Windows.' }
        if ((Get-ChenNativeArchitecture) -ne 'x64') { throw 'This system tools installer targets x64 Windows (including the Spectre 15-eb0xxx). ParkControl has no ARM64 package in this catalog.' }
        if (-not $Headless) {
            $Selection = Show-ChenSystemToolSelector $Selection
            if (-not $Selection) { Write-Host 'Selection cancelled; nothing installed.'; return 0 }
        }
        $packages = @(Get-ChenSystemToolPackages $Selection)
        [void](Get-ChenWinget)
        $logs = New-ChenLogDirectory 'SystemControl'
        $results = @(); $failed = $false
        foreach ($package in $packages) {
            Send-GuiProgress ([int](100 * $results.Count / $packages.Count)) "Installing/updating $package..."
            try {
                $result = Invoke-ChenWingetPackage -Id $package -LogDirectory $logs -Architecture 'x64'
                $results += $result
                if ($result.Outcome -eq 'RestartInitiated') {
                    $pending = @($packages | Select-Object -Skip $results.Count)
                    if ($pending.Count) { $failed = $true }
                    foreach ($id in $pending) { $results += [pscustomobject]@{ Package=$id; Outcome='NotAttempted'; Detail='Windows restart initiated.' } }
                    break
                }
            }
            catch { $failed = $true; $results += [pscustomobject]@{ Package=$package; Outcome='Failed'; Detail=$_.Exception.Message }; Write-Host "ERROR: $($_.Exception.Message)" }
        }
        $results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $logs 'results.json') -Encoding UTF8
        Write-Host "Logs: $logs"
        Write-Host 'Open the tools from Start. Choose power settings in ParkControl and Sensors-only in HWiNFO. No tuning preset was applied by this script.'
        Write-Host 'HP-specific fan profiles still need a verified model-compatible utility, such as HP Command Center. Firmware cooling remains in charge.'
        if ($failed) { Send-GuiProgress 100 'Some system tools were not installed; review the log.'; return 1 }
        Send-GuiProgress 100 'System control tools installed.'; return 0
    }
    catch { Write-Host "ERROR: $($_.Exception.Message)"; return 1 }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-ChenSystemTools -Selection $Tools -Headless $NoUI.IsPresent) }

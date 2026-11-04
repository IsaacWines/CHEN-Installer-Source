<#
TAMU ArcGIS Pro: install an authorized, extracted ArcGISPro.msi and its prerequisites.
Downloads/NetID authentication stay in the user's browser. No credentials or license keys are stored.
#>
[CmdletBinding()]
param(
    [string]$InstallerPath = '',
    [ValidateSet('AllUsers', 'CurrentUser')][string]$InstallScope = 'AllUsers',
    [switch]$AcceptEula,
    [switch]$NoUI,
    [switch]$PlanOnly
)
. (Join-Path $PSScriptRoot 'common.ps1')

function Get-ChenArcGISRuntime {
    param([version]$Version)
    if ($Version.Major -eq 3 -and $Version.Minor -eq 7) { return 'Microsoft.DotNet.DesktopRuntime.10' }
    if ($Version.Major -eq 3 -and $Version.Minor -in @(3, 4, 5, 6)) { return 'Microsoft.DotNet.DesktopRuntime.8' }
    throw "ArcGIS Pro $Version is outside the verified 3.3-3.7 runtime mapping. Check Esri requirements before extending this installer."
}

function Get-ChenMsiProperty {
    param([string]$Path, [ValidateSet('ProductName', 'ProductVersion')][string]$Property)
    $installer = $null; $database = $null; $view = $null; $record = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($Path, 0))
        $query = "SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '$Property'"
        $view = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database, @($query))
        [void]$view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
        $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
        if (-not $record) { throw "MSI property $Property is missing." }
        return $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @(1))
    }
    finally {
        foreach ($com in @($record, $view, $database, $installer)) {
            if ($null -ne $com) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($com) }
        }
    }
}

function Assert-ChenEsriSignature {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) { throw 'ArcGIS MSI must have a valid Esri Authenticode signature. Obtain a fresh authorized package; signature checks are not bypassed.' }
    $publisher = $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    if ($publisher -notmatch '^(Environmental Systems Research Institute(?:,? Inc\.?)?|Esri(?: Inc\.?)?)$') {
        throw "Unexpected MSI publisher: $publisher"
    }
}

function Get-ChenArcGISPackage {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.Path]::GetFileName($Path) -ine 'ArcGISPro.msi') {
        throw 'Select the extracted ArcGISPro.msi. Keep its companion files/folders beside it; do not select the downloaded self-extracting EXE.'
    }
    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    Assert-ChenEsriSignature $resolved
    $name = Get-ChenMsiProperty $resolved 'ProductName'
    if ($name -notmatch '^ArcGIS Pro(?:\s|$)') { throw "This MSI is not ArcGIS Pro: $name" }
    $version = [version](Get-ChenMsiProperty $resolved 'ProductVersion')
    $runtime = Get-ChenArcGISRuntime $version
    [pscustomobject]@{ Path=$resolved; Product=$name; Version=$version.ToString(); Runtime=$runtime; SHA256=(Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash }
}

function Get-ChenArcGISArguments {
    param([string]$Path, [string]$LogPath, [string]$Scope)
    if ($Path.Contains('"') -or $LogPath.Contains('"')) { throw 'Invalid quote in path.' }
    if ($Scope -notin @('AllUsers', 'CurrentUser')) { throw 'Invalid scope.' }
    $allUsers = 1; if ($Scope -eq 'CurrentUser') { $allUsers = 2 }
    return "/i `"$Path`" /qb /norestart /L*v `"$LogPath`" ALLUSERS=$allUsers ACCEPTEULA=YES AUTHORIZATION_TYPE=NAMED_USER LICENSE_URL=`"https://tamu.maps.arcgis.com`" PORTAL_LIST=`"https://tamu.maps.arcgis.com`" LOCK_AUTH_SETTINGS=FALSE"
}

function Show-ChenArcGISSelector {
    param([string]$InitialPath, [string]$InitialScope)
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'CHEN | ArcGIS Pro for Texas A&M'
    $form.ClientSize = New-Object System.Drawing.Size(700, 360)
    $form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds(20, 18, 660, 100)
    $info.Text = "1. Obtain ArcGIS Pro from TAMU Software or your licensed TAMU ArcGIS account.`r`n2. Run the downloaded EXE to extract it; uncheck Launch the setup program.`r`n3. Select the extracted ArcGISPro.msi below, leaving all companion files in place.`r`nThis tool installs prerequisites and configures TAMU Named User licensing. You sign in with NetID inside ArcGIS Pro afterward. A license must already be assigned to your account."
    $form.Controls.Add($info)
    $download = New-Object System.Windows.Forms.Button
    $download.Text = 'TAMU Software'; $download.SetBounds(20, 126, 160, 32)
    $download.Add_Click({ Start-Process 'https://software.tamu.edu/' }); $form.Controls.Add($download)
    $portal = New-Object System.Windows.Forms.Button
    $portal.Text = 'TAMU ArcGIS portal'; $portal.SetBounds(190, 126, 180, 32)
    $portal.Add_Click({ Start-Process 'https://tamu.maps.arcgis.com/' }); $form.Controls.Add($portal)
    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.SetBounds(20, 178, 540, 28); $pathBox.Text = $InitialPath; $form.Controls.Add($pathBox)
    $browse = New-Object System.Windows.Forms.Button
    $browse.Text = 'Browse MSI'; $browse.SetBounds(570, 174, 110, 32)
    $browse.Add_Click({
        $picker = New-Object System.Windows.Forms.OpenFileDialog
        $picker.Filter = 'ArcGIS Pro MSI (ArcGISPro.msi)|ArcGISPro.msi'; $picker.CheckFileExists = $true
        try { if ($picker.ShowDialog($form) -eq 'OK') { $pathBox.Text = $picker.FileName } }
        finally { $picker.Dispose() }
    })
    $form.Controls.Add($browse)
    $scope = New-Object System.Windows.Forms.ComboBox
    $scope.SetBounds(20, 220, 660, 28); $scope.DropDownStyle = 'DropDownList'
    [void]$scope.Items.Add('Everyone on this PC (administrator required)'); [void]$scope.Items.Add('This account')
    $scope.SelectedIndex = 0; if ($InitialScope -eq 'CurrentUser') { $scope.SelectedIndex = 1 }; $form.Controls.Add($scope)
    $eula = New-Object System.Windows.Forms.CheckBox
    $eula.Text = 'I accept the Esri license terms supplied with this download.'; $eula.SetBounds(20, 260, 660, 25); $form.Controls.Add($eula)
    $install = New-Object System.Windows.Forms.Button
    $install.Text = 'Install'; $install.SetBounds(450, 308, 110, 32)
    $install.Add_Click({
        if (-not $pathBox.Text.Trim() -or -not $eula.Checked) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Select ArcGISPro.msi and accept its license terms first.'); return }
        $selectedScope = 'AllUsers'; if ($scope.SelectedIndex -eq 1) { $selectedScope = 'CurrentUser' }
        $form.Tag = [pscustomobject]@{ Path=$pathBox.Text.Trim(); Scope=$selectedScope }
        $form.DialogResult = 'OK'; $form.Close()
    })
    $form.Controls.Add($install)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.SetBounds(570, 308, 110, 32); $cancel.DialogResult = 'Cancel'
    $form.Controls.Add($cancel); $form.CancelButton = $cancel
    try { if ($form.ShowDialog() -eq 'OK') { return $form.Tag }; return $null }
    finally { $form.Dispose() }
}

function Invoke-ChenArcGISInstaller {
    param([string]$Path, [string]$Scope, [bool]$EulaAccepted, [bool]$Headless, [bool]$Preview)
    $ErrorActionPreference = 'Stop'
    try {
        if ($env:OS -ne 'Windows_NT' -or (Get-ChenNativeArchitecture) -ne 'x64') { throw 'This ArcGIS Pro installer requires native x64 Windows. Check Esri requirements for your selected release.' }
        if (-not $Headless) {
            $choice = Show-ChenArcGISSelector $Path $Scope
            if (-not $choice) { Write-Host 'Selection cancelled; nothing installed.'; return 0 }
            $Path = $choice.Path; $Scope = $choice.Scope; $EulaAccepted = $true
        }
        $package = Get-ChenArcGISPackage $Path
        $plan = [pscustomobject]@{ Package=$package; Scope=$Scope; Prerequisites=@($package.Runtime, 'Microsoft.EdgeWebView2Runtime'); Portal='https://tamu.maps.arcgis.com'; LicenseType='Named User' }
        if ($Preview) { $plan | ConvertTo-Json -Depth 5 | Write-Host; return 0 }
        if (-not $EulaAccepted) { throw 'Unattended installation requires -AcceptEula after reviewing the Esri license terms.' }
        if ($Scope -eq 'AllUsers' -and -not (Test-IsAdmin)) { throw 'Launch CHEN or PowerShell as Administrator for an Everyone install.' }
        [void](Get-ChenWinget)
        $logs = New-ChenLogDirectory 'ArcGISPro_TAMU'
        $plan | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $logs 'plan.json') -Encoding UTF8
        $prerequisiteResults = @()
        Send-GuiProgress 10 "Installing/checking $($package.Runtime) x64..."
        foreach ($id in $plan.Prerequisites) {
            $result = Invoke-ChenWingetPackage -Id $id -LogDirectory $logs -Architecture 'x64' -Scope 'machine'
            $prerequisiteResults += $result
            $prerequisiteResults | ConvertTo-Json | Set-Content (Join-Path $logs 'prerequisites.json') -Encoding UTF8
            if ($result.Outcome -like 'Restart*') { throw 'A prerequisite requires a restart. Restart Windows and rerun this installer before installing ArcGIS Pro.' }
        }
        if ((Get-FileHash -LiteralPath $package.Path -Algorithm SHA256).Hash -ne $package.SHA256) { throw 'ArcGIS MSI changed after validation. Installation stopped.' }
        Send-GuiProgress 60 "Installing ArcGIS Pro $($package.Version) with TAMU portal..."
        $arguments = Get-ChenArcGISArguments -Path $package.Path -LogPath (Join-Path $logs 'ArcGISPro-msi.log') -Scope $Scope
        $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList $arguments -PassThru -Wait
        [pscustomobject]@{ Version=$package.Version; ExitCode=$process.ExitCode; Portal=$plan.Portal } | ConvertTo-Json | Set-Content (Join-Path $logs 'results.json') -Encoding UTF8
        if ($process.ExitCode -notin @(0, 3010, 1641)) { throw "ArcGIS Windows Installer returned $($process.ExitCode). See $logs. Match any existing installation's scope and close ArcGIS Pro before retrying." }
        if ($process.ExitCode -in @(3010, 1641)) { Write-Host 'Windows restart required.' }
        Send-GuiProgress 100 'ArcGIS Pro installed; TAMU NetID sign-in is still required.'
        Write-Host "Logs: $logs"
        Write-Host 'Open ArcGIS Pro as your normal user. Choose Your organization, tamu.maps.arcgis.com, then Texas A&M NetID Login. The assigned license determines your level/extensions; this installer does not grant an ArcInfo/Advanced license.'
        return 0
    }
    catch { Write-Host "ERROR: $($_.Exception.Message)"; return 1 }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-ChenArcGISInstaller -Path $InstallerPath -Scope $InstallScope -EulaAccepted $AcceptEula.IsPresent -Headless $NoUI.IsPresent -Preview $PlanOnly.IsPresent) }

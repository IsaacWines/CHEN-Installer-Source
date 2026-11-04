# Dependency-free: no real software installation or network requests.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '../powershell/arcgispro_tamu_installer.ps1')
. (Join-Path $PSScriptRoot '../powershell/steam_installer.ps1')
. (Join-Path $PSScriptRoot '../powershell/system_control_installer.ps1')
$script:passed = 0
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern='*')
    try { & $Action } catch { if ($_.Exception.Message -notlike $Pattern) { throw }; return }
    throw 'Expected an exception.'
}
function Test-Case { param([string]$Name, [scriptblock]$Action) & $Action; $script:passed++; Write-Host "PASS $Name" }
function With-Mocks {
    param([hashtable]$Mocks, [scriptblock]$Action)
    $saved = @{}
    foreach ($name in $Mocks.Keys) { $saved[$name] = (Get-Item "Function:$name").ScriptBlock; Set-Item "Function:script:$name" $Mocks[$name] }
    try { & $Action } finally { foreach ($name in $saved.Keys) { Set-Item "Function:script:$name" $saved[$name] } }
}

Test-Case 'All three scripts are enabled in the live catalog schema' {
    $catalog = Get-Content (Join-Path $PSScriptRoot '../installers.json') -Raw | ConvertFrom-Json
    foreach ($script in @('arcgispro_tamu_installer.ps1','steam_installer.ps1','system_control_installer.ps1')) {
        $entry = @($catalog | Where-Object scriptPath -eq "powershell/$script")
        Assert-True ($entry.Count -eq 1 -and $entry[0].enabled) "Missing $script"
    }
}
Test-Case 'All new scripts and shared helpers parse without errors' {
    foreach ($name in @('arcgispro_tamu_installer.ps1','steam_installer.ps1','system_control_installer.ps1','common.ps1')) {
        $tokens=$null; $errors=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "../powershell/$name"),[ref]$tokens,[ref]$errors)
        Assert-True ($errors.Count -eq 0) ($errors | Out-String)
    }
}
Test-Case 'Exact IDs, trusted source and silent operation preserve WinGet verification' {
    foreach ($id in @('Valve.Steam','BitSum.ParkControl','REALiX.HWiNFO','Microsoft.DotNet.DesktopRuntime.8','Microsoft.DotNet.DesktopRuntime.10','Microsoft.EdgeWebView2Runtime')) {
        $arguments = @(Get-ChenWingetArguments $id 'C:\logs folder\winget.log' 'x64' 'machine')
        Assert-True ($id -cin $arguments -and '--exact' -in $arguments -and 'winget' -in $arguments -and '--disable-interactivity' -in $arguments) 'Incorrect command.'
        Assert-True ('--ignore-security-hash' -notin $arguments -and '--force' -notin $arguments -and '--allow-reboot' -notin $arguments) 'Unsafe flags.'
        Assert-True ('C:\logs folder\winget.log' -in $arguments) 'Log path was split.'
    }
    Assert-Throws { Get-ChenWingetArguments 'Other.Package' 'log' }
    Assert-Throws { Get-ChenWingetArguments 'Valve.Steam' 'log' 'wrong' }
}
Test-Case 'WinGet success/current/reboot codes are distinct from genuine failures' {
    foreach ($code in @(0,-1978335189,-1978335135,2316632107)) { Assert-True ((Get-ChenWingetOutcome $code) -eq 'Success') "Code $code failed." }
    foreach ($code in @(3010,-1978334967)) { Assert-True ((Get-ChenWingetOutcome $code) -eq 'RestartRequired') 'Lost restart.' }
    Assert-True ((Get-ChenWingetOutcome 1641) -eq 'RestartInitiated') 'Lost restart initiation.'
    foreach ($code in @(1603,1602,-1978334966,-1978335215)) { Assert-True ((Get-ChenWingetOutcome $code) -eq 'Failed') 'Failure treated as success.' }
}
Test-Case 'Native package failures propagate and already-current packages succeed' {
    With-Mocks @{
        'Get-ChenWinget' = { 'fixture-winget' }
        'Invoke-ChenNativeWinget' = { param($Executable,$Arguments) return -1978335189 }
    } {
        Assert-True ((Invoke-ChenWingetPackage 'Valve.Steam' '.').Outcome -eq 'Success') 'Current package failed.'
    }
    With-Mocks @{
        'Get-ChenWinget' = { 'fixture-winget' }
        'Invoke-ChenNativeWinget' = { param($Executable,$Arguments) return 1603 }
    } { Assert-Throws { Invoke-ChenWingetPackage 'Valve.Steam' '.' } '*WinGet failed*' }
}
Test-Case 'Runtime mapping selects the correct supported major and fails closed for unknown versions' {
    foreach ($version in @('3.3.0','3.4.3','3.5.0','3.6.5')) { Assert-True ((Get-ChenArcGISRuntime $version) -eq 'Microsoft.DotNet.DesktopRuntime.8') 'Wrong runtime.' }
    Assert-True ((Get-ChenArcGISRuntime '3.7.3') -eq 'Microsoft.DotNet.DesktopRuntime.10') 'Wrong 3.7 runtime.'
    foreach ($version in @('2.9.0','3.2.0','3.8.0','4.0.0')) { Assert-Throws { Get-ChenArcGISRuntime $version } '*outside the verified*' }
}
Test-Case 'TAMU MSI arguments configure Named User without keys or a forced Advanced license' {
    $arguments = Get-ChenArcGISArguments 'C:\setup folder\ArcGISPro.msi' 'C:\logs folder\msi.log' 'AllUsers'
    Assert-True ($arguments.Contains('ALLUSERS=1') -and $arguments.Contains('AUTHORIZATION_TYPE=NAMED_USER') -and $arguments.Contains('LICENSE_URL="https://tamu.maps.arcgis.com"')) 'Missing licensing config.'
    Assert-True ($arguments.Contains('PORTAL_LIST="https://tamu.maps.arcgis.com"') -and $arguments.Contains('LOCK_AUTH_SETTINGS=FALSE') -and $arguments.Contains('/norestart')) 'Bad portal/locking/restart behavior.'
    Assert-True (-not $arguments.Contains('SOFTWARE_CLASS') -and -not $arguments.Contains('ESRI_LICENSE_HOST')) 'License entitlement was guessed.'
    Assert-True ((Get-ChenArcGISArguments 'a' 'b' 'CurrentUser').Contains('ALLUSERS=2')) 'Wrong Esri per-user property.'
    Assert-Throws { Get-ChenArcGISArguments 'a"b' 'c' 'AllUsers' }
}
Test-Case 'System tools selection respects both and individual choices' {
    Assert-True (@(Get-ChenSystemToolPackages 'Both').Count -eq 2) 'Missing tools.'
    Assert-True ((Get-ChenSystemToolPackages 'ParkControl') -ceq 'BitSum.ParkControl') 'Wrong power tool.'
    Assert-True ((Get-ChenSystemToolPackages 'HWiNFO') -ceq 'REALiX.HWiNFO') 'Wrong monitor.'
    Assert-Throws { Get-ChenSystemToolPackages 'FanControl' }
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('chen-desktop-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp)
$savedOS = $env:OS
try {
    $path = Join-Path $temp 'ArcGISPro.msi'
    Set-Content $path 'unsigned fixture, not executable'
    Test-Case 'Only extracted ArcGISPro.msi is accepted; signature rejection stops metadata reads' {
        Assert-Throws { Get-ChenArcGISPackage (Join-Path $temp 'ArcGISPro.exe') } '*Select the extracted*'
        With-Mocks @{
            'Assert-ChenEsriSignature' = { param($Path) throw 'Invalid signature.' }
            'Get-ChenMsiProperty' = { throw 'Metadata must not be read after signature failure.' }
        } { Assert-Throws { Get-ChenArcGISPackage $path } '*Invalid signature*' }
    }
    Test-Case 'Validated metadata determines runtime and captures a source hash' {
        With-Mocks @{
            'Assert-ChenEsriSignature' = { param($Path) }
            'Get-ChenMsiProperty' = { param($Path,$Property) if ($Property -eq 'ProductName') { return 'ArcGIS Pro' }; return '3.7.0' }
        } {
            $package = Get-ChenArcGISPackage $path
            Assert-True ($package.Runtime -eq 'Microsoft.DotNet.DesktopRuntime.10' -and $package.SHA256.Length -eq 64) 'Incorrect package metadata.'
        }
    }
    $env:OS = 'Windows_NT'
    Test-Case 'ArcGIS preview does not acquire prerequisites or execute an MSI' {
        With-Mocks @{
            'Get-ChenNativeArchitecture' = { 'x64' }
            'Get-ChenArcGISPackage' = { param($Path) [pscustomobject]@{ Path=$Path; Version='3.7.0'; Runtime='Microsoft.DotNet.DesktopRuntime.10' } }
            'Get-ChenWinget' = { throw 'Preview must not use WinGet.' }
            'New-ChenLogDirectory' = { throw 'Preview must not create logs.' }
        } { Assert-True ((Invoke-ChenArcGISInstaller $path 'AllUsers' $false $true $true) -eq 0) 'Preview mutated or failed.' }
    }
    Test-Case 'Unaccepted Esri EULA stops a headless installation before prerequisites' {
        With-Mocks @{
            'Get-ChenNativeArchitecture' = { 'x64' }
            'Get-ChenArcGISPackage' = { param($Path) [pscustomobject]@{ Path=$Path; Version='3.7.0'; Runtime='Microsoft.DotNet.DesktopRuntime.10' } }
            'Get-ChenWinget' = { throw 'Unaccepted EULA reached WinGet.' }
        } { Assert-True ((Invoke-ChenArcGISInstaller $path 'AllUsers' $false $true $false) -eq 1) 'EULA was silently accepted.' }
    }
    Test-Case 'Individual tool failure is logged and remaining tools can install' {
        $script:calls = @()
        With-Mocks @{
            'Get-ChenNativeArchitecture' = { 'x64' }
            'Get-ChenWinget' = { 'fixture-winget' }
            'New-ChenLogDirectory' = { param($Name) $temp }
            'Invoke-ChenWingetPackage' = {
                param($Id,$LogDirectory,$Architecture,$Scope)
                $script:calls += $Id
                if ($Id -eq 'BitSum.ParkControl') { throw 'Fixture download failure.' }
                [pscustomobject]@{ Package=$Id; Outcome='Success'; ExitCode=0 }
            }
        } {
            Assert-True ((Invoke-ChenSystemTools 'Both' $true) -eq 1) 'Partial failure was hidden.'
            Assert-True ($script:calls.Count -eq 2) 'Remaining tool was not attempted.'
            $results = Get-Content (Join-Path $temp 'results.json') -Raw | ConvertFrom-Json
            Assert-True ($results[0].Outcome -eq 'Failed' -and $results[1].Outcome -eq 'Success') 'Lost per-tool outcomes.'
        }
    }
    Test-Case 'Unsupported native architecture stops system tools before package acquisition' {
        With-Mocks @{
            'Get-ChenNativeArchitecture' = { 'arm64' }
            'Get-ChenWinget' = { throw 'Unsupported machine reached WinGet.' }
        } { Assert-True ((Invoke-ChenSystemTools 'Both' $true) -eq 1) 'Unsupported system accepted.' }
    }
    if ($savedOS -eq 'Windows_NT') {
        Test-Case 'Windows MSI property reader reads an actual database; unsigned payload is rejected' {
            Remove-Item -LiteralPath $path
            $installer = New-Object -ComObject WindowsInstaller.Installer
            $database = $null
            try {
                $database = $installer.OpenDatabase([string]$path, [int]3)
                foreach ($query in @(
                    'CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` CHAR(0) LOCALIZABLE PRIMARY KEY `Property`)',
                    "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('ProductName', 'ArcGIS Pro')",
                    "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('ProductVersion', '3.7.0')"
                )) {
                    $view = $database.OpenView([string]$query)
                    try { [void]$view.Execute() }
                    finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view) }
                }
                [void]$database.Commit()
            }
            finally {
                if ($database) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($database) }
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
            }
            Assert-True ((Get-ChenMsiProperty $path 'ProductName') -eq 'ArcGIS Pro') 'Wrong product name.'
            Assert-True ((Get-ChenMsiProperty $path 'ProductVersion') -eq '3.7.0') 'Wrong product version.'
            Assert-Throws { Assert-ChenEsriSignature $path } '*valid Esri Authenticode*'
        }
        foreach ($kind in @('SystemTools','ArcGIS')) {
            Test-Case "$kind dialog returns actual checkbox and scope selections" {
                Add-Type -AssemblyName System.Windows.Forms
                $script:uiError = $null
                $timer = New-Object System.Windows.Forms.Timer
                $timer.Interval = 300
                $timer.Add_Tick({
                    $dialog = $null
                    try {
                        $dialog = [System.Windows.Forms.Application]::OpenForms[0]
                        if (-not $dialog) { return }
                        $timer.Stop()
                        foreach ($control in $dialog.Controls) {
                            if ($control -is [System.Windows.Forms.CheckBox]) {
                                $control.Checked = $true
                                if ($control.Text -like 'ParkControl*') { $control.Checked = $false }
                            }
                        }
                        $button = @($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -like 'Install*' })[0]
                        $button.PerformClick()
                    }
                    catch { $script:uiError = $_.Exception.Message; if ($dialog) { $dialog.Close() } }
                })
                $timer.Start()
                try {
                    if ($kind -eq 'SystemTools') {
                        $choice = Show-ChenSystemToolSelector 'Both'
                        Assert-True ($choice -eq 'HWiNFO') 'Checkbox changes were lost.'
                    }
                    else {
                        $choice = Show-ChenArcGISSelector $path 'CurrentUser'
                        Assert-True ($choice.Path -eq $path -and $choice.Scope -eq 'CurrentUser') 'Scope/path selection was lost.'
                    }
                    if ($script:uiError) { throw $script:uiError }
                }
                finally { $timer.Stop(); $timer.Dispose() }
            }
        }
    }
}
finally { $env:OS = $savedOS; Remove-Item -LiteralPath $temp -Recurse -Force }

Write-Host "$script:passed desktop installer tests passed. No software was installed."

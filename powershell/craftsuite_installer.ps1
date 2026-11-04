<#
.SYNOPSIS
Select and install the Craft apps listed on CraftSuite, with an optional ArtCraft Launcher.
.DESCRIPTION
Windows PowerShell 5.1+. Self-contained: the existing CHEN GUI downloads only this script.
Downloads come from official storytold GitHub releases, never from third-party mirrors.
Dot-source to load functions without opening the selector or installing anything.
#>
[CmdletBinding()]
param(
    [string]$Apps = '',
    [ValidateSet('Prompt', 'Include', 'Omit')][string]$Launcher = 'Prompt',
    [ValidateSet('Auto', 'x64', 'arm64', 'x86')][string]$Architecture = 'Auto',
    [ValidateSet('CurrentUser', 'AllUsers')][string]$InstallScope = 'CurrentUser',
    [switch]$NoUI,
    [switch]$PlanOnly,
    [switch]$ListApps
)

function Get-CraftCatalog {
    @(
        [pscustomobject]@{ Id='photocraft'; Name='PhotoCraft'; Purpose='Photo editing'; Prefix='photocraft'; Kind='Craft' }
        [pscustomobject]@{ Id='vectorcraft'; Name='VectorCraft'; Purpose='Vector illustration'; Prefix='vectorcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='filmcraft'; Name='FilmCraft'; Purpose='Video editing'; Prefix='filmcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='lightcraft'; Name='LightCraft'; Purpose='RAW photos and photo library'; Prefix='lightcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='pdfcraft'; Name='PdfCraft'; Purpose='PDF tools'; Prefix='pdfcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='effectcraft'; Name='EffectCraft'; Purpose='Motion graphics and effects'; Prefix='effectcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='designcraft'; Name='DesignCraft'; Purpose='Page layout and publishing'; Prefix='designcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='wordcraft'; Name='WordCraft'; Purpose='Documents'; Prefix='wordcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='gridcraft'; Name='GridCraft'; Purpose='Spreadsheets'; Prefix='gridcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='deckcraft'; Name='DeckCraft'; Purpose='Presentations'; Prefix='deckcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='cadcraft'; Name='CADCraft'; Purpose='2D drafting'; Prefix='cadcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='soundcraft'; Name='SoundCraft'; Purpose='Audio recording and mixing'; Prefix='soundcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='figcraft'; Name='FigCraft'; Purpose='Interface design'; Prefix='figcraft'; Kind='Craft' }
        [pscustomobject]@{ Id='artcraft'; Name='ArtCraft AI Studio'; Purpose='Separate AI studio (x64; online services may cost money)'; Prefix='ArtCraft'; Kind='Studio' }
        [pscustomobject]@{ Id='craft-launcher'; Name='ArtCraft Launcher'; Purpose='Central place to open, install and update Craft apps'; Prefix='artcraft-launcher'; Kind='Launcher' }
    )
}

function Resolve-CraftSelection {
    param([string]$AppIds, [string]$LauncherChoice)
    if ($LauncherChoice -notin @('Include', 'Omit')) { throw 'Choose whether to include the launcher.' }
    $catalog = @(Get-CraftCatalog)
    $ids = @($AppIds.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    foreach ($id in $ids) {
        if ($id -eq 'craft-launcher') { throw 'Use -Launcher Include to select the launcher.' }
        if ($id -notin $catalog.Id) { throw "Unknown app '$id'. Use -ListApps for valid IDs." }
    }
    $selected = @($catalog | Where-Object { $_.Id -in $ids })
    if ($LauncherChoice -eq 'Include') { $selected += $catalog | Where-Object { $_.Kind -eq 'Launcher' } }
    if ($selected.Count -eq 0) { throw 'Select at least one app or the launcher.' }
    return $selected
}

function Get-CraftArchitecture {
    # Native OS architecture, including a 32-bit PowerShell process on 64-bit Windows.
    $native = $env:PROCESSOR_ARCHITEW6432
    if (-not $native) { $native = $env:PROCESSOR_ARCHITECTURE }
    switch ($native) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        'x86' { return 'x86' }
        default { throw 'Cannot detect Windows architecture. Use -Architecture for a download plan.' }
    }
}

function Write-CraftProgress {
    param([int]$Percent, [string]$Message)
    [Console]::Out.WriteLine("CHEN_PROGRESS|$([Math]::Max(0, [Math]::Min(100, $Percent)))|$Message")
    [Console]::Out.Flush()
}

function Assert-CraftReleaseUrl {
    param([string]$Url, [string]$Repo)
    $uri = [uri]$Url
    $prefix = "/storytold/$Repo/releases/download/"
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or
        -not $uri.IsDefaultPort -or $uri.UserInfo -or
        -not $uri.AbsolutePath.StartsWith($prefix, [StringComparison]::Ordinal) -or $uri.Query -or $uri.Fragment) {
        throw "Unexpected release URL for storytold/${Repo}: $Url"
    }
}

function Get-CraftRelease {
    param([string]$Repo)
    if ($Repo -notin @(Get-CraftCatalog).Id) { throw "Unknown repository '$Repo'." }
    try {
        # No tokens needed. A run of the complete catalog uses fewer than GitHub's 60 anonymous requests/hour.
        Invoke-RestMethod -Uri "https://api.github.com/repos/storytold/$Repo/releases/latest" -Headers @{
            'User-Agent'='CHEN-CraftSuite-Installer'; 'Accept'='application/vnd.github+json'
        } -UseBasicParsing -TimeoutSec 60
    }
    catch { throw "Cannot read storytold/$Repo releases. Check internet access or GitHub API rate limits. $($_.Exception.Message)" }
}

function Select-CraftAsset {
    param($App, $Release, [string]$Arch)
    if ($Release.draft -or $Release.prerelease) { throw "No stable release available for $($App.Name)." }
    $version = [string]$Release.tag_name
    if ($App.Kind -eq 'Studio') {
        if ($Arch -ne 'x64') { throw 'ArtCraft AI Studio currently publishes a Windows x64 MSI only. Deselect it for this architecture.' }
        $version = $version -replace '^artcraft-v', ''
        $pattern = '^ArtCraft_' + [regex]::Escape($version) + '_x64_en-US\.msi$'
    }
    else {
        $version = $version -replace '^v', ''
        $pattern = '^' + [regex]::Escape($App.Prefix + '-' + $version + '-windows-' + $Arch) + '\.msi$'
    }
    $candidates = @($Release.assets | Where-Object { $_.name -cmatch $pattern })
    if ($candidates.Count -ne 1) { throw "Expected one $Arch MSI for $($App.Name) $version; found $($candidates.Count)." }
    Assert-CraftReleaseUrl -Url $candidates[0].browser_download_url -Repo $App.Id
    return $candidates[0]
}

function Get-CraftChecksumFromText {
    param([string]$Text, [string]$FileName)
    $pattern = '(?im)^([a-f0-9]{64})[ \t]+\*?' + [regex]::Escape($FileName) + '[ \t]*\r?$'
    $entries = [regex]::Matches($Text, $pattern)
    if ($entries.Count -ne 1) { throw "Expected one SHA-256 checksum for $FileName; found $($entries.Count)." }
    return $entries[0].Groups[1].Value.ToLowerInvariant()
}

function Get-CraftExpectedHash {
    param($App, $Release, $Asset)
    $digestProperty = $Asset.PSObject.Properties['digest']
    if ($digestProperty -and [string]$digestProperty.Value -match '^sha256:([a-fA-F0-9]{64})$') {
        return $Matches[1].ToLowerInvariant()
    }
    $sums = @($Release.assets | Where-Object { $_.name -ceq 'SHA256SUMS.txt' })
    if ($sums.Count -ne 1) { throw "No published SHA-256 available for $($Asset.name). Installation stopped." }
    Assert-CraftReleaseUrl -Url $sums[0].browser_download_url -Repo $App.Id
    $response = Invoke-WebRequest -Uri $sums[0].browser_download_url -UseBasicParsing -TimeoutSec 60
    return Get-CraftChecksumFromText -Text ([string]$response.Content) -FileName $Asset.name
}

function New-CraftPlan {
    param([object[]]$Selection, [string]$Arch, [string]$Scope)
    foreach ($app in $Selection) {
        $release = Get-CraftRelease -Repo $app.Id
        $asset = Select-CraftAsset -App $app -Release $release -Arch $Arch
        $hash = Get-CraftExpectedHash -App $app -Release $release -Asset $asset
        $effectiveScope = $Scope
        if ($app.Kind -eq 'Launcher') { $effectiveScope = 'CurrentUser' }
        if ($app.Kind -eq 'Studio') { $effectiveScope = 'PackageDefault' }
        [pscustomobject]@{
            Id=$app.Id; Name=$app.Name; Version=$release.tag_name; Architecture=$Arch
            Scope=$effectiveScope; FileName=$asset.name; Url=$asset.browser_download_url
            SHA256=$hash; Bytes=$asset.size
        }
    }
}

function Save-CraftDownload {
    param([string]$Url, [string]$Destination)
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try { Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 1800 }
    finally { $ProgressPreference = $oldProgress }
}

function Assert-CraftFileHash {
    param([string]$Path, [string]$Expected)
    if ($Expected -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid expected SHA-256.' }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) { throw "SHA-256 mismatch for $(Split-Path $Path -Leaf). Installation stopped." }
}

function Get-CraftMsiArguments {
    param([string]$Path, [string]$LogPath, [string]$Scope)
    if ($Path.Contains('"') -or $LogPath.Contains('"')) { throw 'Invalid quote in MSI path.' }
    $arguments = "/i `"$Path`" /passive /norestart /L*v `"$LogPath`""
    if ($Scope -eq 'AllUsers') { $arguments += ' ALLUSERS=1 MSIINSTALLPERUSER=""' }
    elseif ($Scope -eq 'CurrentUser') { $arguments += ' ALLUSERS="" MSIINSTALLPERUSER=1' }
    return $arguments
}

function Invoke-CraftMsi {
    param([string]$Path, [string]$LogPath, [string]$Scope)
    $arguments = Get-CraftMsiArguments -Path $Path -LogPath $LogPath -Scope $Scope
    $msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
    $process = Start-Process -FilePath $msiexec -ArgumentList $arguments -PassThru -Wait
    return $process.ExitCode
}

function Invoke-CraftInstallPlan {
    param([object[]]$Plan, [string]$WorkDirectory, [string]$LogDirectory)
    $results = @()
    foreach ($item in $Plan) {
        $index = $results.Count
        $path = Join-Path $WorkDirectory $item.FileName
        $msiLog = Join-Path $LogDirectory ($item.Id + '-msi.log')
        $code = $null
        try {
            Write-CraftProgress -Percent ([int](100 * $index / $Plan.Count)) -Message "Downloading $($item.Name) $($item.Version)..."
            Assert-CraftReleaseUrl -Url $item.Url -Repo $item.Id
            Save-CraftDownload -Url $item.Url -Destination $path
            Assert-CraftFileHash -Path $path -Expected $item.SHA256
            Write-CraftProgress -Percent ([int](100 * ($index + 0.5) / $Plan.Count)) -Message "Installing $($item.Name)..."
            $code = Invoke-CraftMsi -Path $path -LogPath $msiLog -Scope $item.Scope
            if ($code -notin @(0, 3010, 1641)) { throw "Windows Installer returned $code. See $msiLog. Existing copies must use the same install scope. Close the app before retrying." }
            $status = 'Installed'
            if ($code -in @(3010, 1641)) { $status = 'Installed; restart required' }
            $results += [pscustomobject]@{ App=$item.Name; Status=$status; ExitCode=$code; Detail=$msiLog }
            Write-Host "$($item.Name): $status"
        }
        catch {
            $results += [pscustomobject]@{ App=$item.Name; Status='Failed'; ExitCode=$code; Detail=$_.Exception.Message }
            Write-Host "ERROR: $($item.Name): $($_.Exception.Message)"
        }
        finally {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }
        # Respect cancellation in the native MSI; do not start the next selected app.
        if ($code -in @(1602, 1641)) {
            $remaining = @($Plan | Select-Object -Skip ($index + 1))
            foreach ($pending in $remaining) {
                $results += [pscustomobject]@{ App=$pending.Name; Status='Not attempted'; ExitCode=$null; Detail='Installation cancelled or a restart was initiated.' }
            }
            break
        }
    }
    return $results
}

function Get-CraftResultCode {
    param([object[]]$Results)
    if (@($Results | Where-Object { $_.Status -eq 'Failed' -or $_.Status -eq 'Not attempted' }).Count) { return 1 }
    # CHEN's current GUI treats every nonzero exit as failure. Report reboot needs in the log, return success.
    return 0
}

function Show-CraftSelector {
    param([string]$InitialApps, [string]$InitialLauncher, [string]$InitialScope, [string]$Arch)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'CHEN | Craft App Suite'
    $form.ClientSize = New-Object System.Drawing.Size(700, 655)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $intro = New-Object System.Windows.Forms.Label
    $intro.SetBounds(20, 16, 660, 58)
    $intro.Text = "Choose your apps ($Arch)`r`nDownloads and updates use the official ArtCraft release packages."
    $form.Controls.Add($intro)

    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.SetBounds(20, 82, 660, 310)
    $list.CheckOnClick = $true
    $list.HorizontalScrollbar = $true
    $list.IntegralHeight = $false
    $apps = @(Get-CraftCatalog | Where-Object { $_.Kind -ne 'Launcher' -and ($_.Kind -ne 'Studio' -or $Arch -eq 'x64') })
    $initial = @($InitialApps.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() })
    foreach ($app in $apps) {
        $row = $list.Items.Add("$($app.Name) - $($app.Purpose)")
        if ($app.Id -in $initial) { $list.SetItemChecked($row, $true) }
    }
    $form.Controls.Add($list)

    $all = New-Object System.Windows.Forms.Button
    $all.Text = 'Select all apps'; $all.SetBounds(20, 401, 145, 32)
    $all.Add_Click({ for ($i=0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $true) } })
    $form.Controls.Add($all)
    $none = New-Object System.Windows.Forms.Button
    $none.Text = 'Clear apps'; $none.SetBounds(175, 401, 125, 32)
    $none.Add_Click({ for ($i=0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $false) } })
    $form.Controls.Add($none)

    $wrapper = New-Object System.Windows.Forms.CheckBox
    $wrapper.Text = 'Also install ArtCraft Launcher (optional)'
    $wrapper.SetBounds(20, 446, 660, 28)
    $wrapper.Checked = $InitialLauncher -eq 'Include'
    $form.Controls.Add($wrapper)
    $hint = New-Object System.Windows.Forms.Label
    $hint.SetBounds(40, 478, 640, 44)
    $hint.Text = 'Open, install and update the Craft apps from one window. Launcher installs for this account. AI Studio opens separately.'
    $form.Controls.Add($hint)

    $scopeLabel = New-Object System.Windows.Forms.Label
    $scopeLabel.Text = 'Craft app install scope:'; $scopeLabel.SetBounds(20, 534, 210, 28)
    $form.Controls.Add($scopeLabel)
    $scopeBox = New-Object System.Windows.Forms.ComboBox
    $scopeBox.SetBounds(238, 530, 442, 30)
    $scopeBox.DropDownStyle = 'DropDownList'
    [void]$scopeBox.Items.Add('This account (use same scope for updates)')
    [void]$scopeBox.Items.Add('Everyone on this PC (administrator required)')
    $scopeBox.SelectedIndex = 0
    if ($InitialScope -eq 'AllUsers') { $scopeBox.SelectedIndex = 1 }
    $form.Controls.Add($scopeBox)

    $install = New-Object System.Windows.Forms.Button
    $install.Text = 'Install selected'; $install.SetBounds(382, 598, 155, 36)
    $install.Add_Click({
        if ($list.CheckedIndices.Count -eq 0 -and -not $wrapper.Checked) {
            [void][System.Windows.Forms.MessageBox]::Show($form, 'Select at least one app or the launcher.', 'Choose apps')
            return
        }
        $selectedIds = @($list.CheckedIndices | ForEach-Object { $apps[[int]$_].Id })
        $choice = 'Omit'; if ($wrapper.Checked) { $choice = 'Include' }
        $scope = 'CurrentUser'; if ($scopeBox.SelectedIndex -eq 1) { $scope = 'AllUsers' }
        $form.Tag = [pscustomobject]@{ Apps=($selectedIds -join ','); Launcher=$choice; Scope=$scope }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($install)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.SetBounds(547, 598, 133, 36)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.AcceptButton = $install; $form.CancelButton = $cancel
    try {
        if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $form.Tag }
        return $null
    }
    finally { $form.Dispose() }
}

function Invoke-CraftMain {
    param([string]$AppIds, [string]$LauncherChoice, [string]$Arch, [string]$Scope, [bool]$Headless, [bool]$Preview)
    $ErrorActionPreference = 'Stop'
    $work = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        if ($Arch -eq 'Auto') { $Arch = Get-CraftArchitecture }
        if (-not $Preview -and $env:OS -ne 'Windows_NT') { throw 'Installation requires Windows 10 or 11.' }
        if (-not $Headless) {
            if ($env:OS -ne 'Windows_NT') { throw 'The selector requires Windows. Use -NoUI -PlanOnly to preview elsewhere.' }
            $choice = Show-CraftSelector -InitialApps $AppIds -InitialLauncher $LauncherChoice -InitialScope $Scope -Arch $Arch
            if ($null -eq $choice) { Write-Host 'Selection cancelled; nothing installed.'; return 0 }
            $AppIds = $choice.Apps; $LauncherChoice = $choice.Launcher; $Scope = $choice.Scope
        }
        $selection = @(Resolve-CraftSelection -AppIds $AppIds -LauncherChoice $LauncherChoice)
        if (-not $Preview) {
            $nativeArch = Get-CraftArchitecture
            if ($Arch -ne $nativeArch) { throw "Use native architecture $nativeArch for installation. Other architectures are available in -PlanOnly mode." }
            if ($Scope -eq 'AllUsers' -and @($selection | Where-Object { $_.Kind -eq 'Craft' }).Count) {
                $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                    throw 'Run CHEN or PowerShell as Administrator for an Everyone install, or choose This account.'
                }
            }
        }
        Write-Host "Resolving $($selection.Count) package(s) from official storytold releases..."
        # Resolve the complete selection before downloading/installing anything. Missing assets/hashes stop the run.
        $plan = @(New-CraftPlan -Selection $selection -Arch $Arch -Scope $Scope)
        if ($Preview) { $plan | ConvertTo-Json -Depth 4 | Write-Host; return 0 }

        $runId = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N')
        $logRoot = $env:CHEN_LOG_ROOT
        if (-not $logRoot) { $logRoot = Join-Path $env:LOCALAPPDATA 'CHENInstaller\Logs' }
        $logs = Join-Path $logRoot "CraftSuite_$runId"
        $work = Join-Path ([IO.Path]::GetTempPath()) "CHEN_CraftSuite_$runId"
        [void](New-Item -ItemType Directory -Path $logs -Force)
        [void](New-Item -ItemType Directory -Path $work)
        $plan | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $logs 'plan.json') -Encoding UTF8
        Write-Host "Logs: $logs"
        $results = @(Invoke-CraftInstallPlan -Plan $plan -WorkDirectory $work -LogDirectory $logs)
        $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $logs 'results.json') -Encoding UTF8
        $results | Format-Table App, Status, ExitCode -AutoSize | Out-String | Write-Host
        $resultCode = Get-CraftResultCode -Results $results
        $message = 'Craft App Suite installation finished.'
        if ($resultCode) { $message = 'Some selections were not installed. Review the per-app results and logs.' }
        Write-CraftProgress -Percent 100 -Message $message
        if (@($results | Where-Object { $_.ExitCode -in @(3010, 1641) }).Count) { Write-Host 'Windows reports a restart is required.' }
        if (@($results | Where-Object { $_.App -eq 'ArtCraft Launcher' -and $_.Status -like 'Installed*' }).Count) {
            Write-Host 'Open ArtCraft Launcher from the Start menu in your normal desktop session to launch the Craft apps.'
        }
        return $resultCode
    }
    catch { Write-Host "ERROR: $($_.Exception.Message)"; return 1 }
    finally { if ($work -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($ListApps) { Get-CraftCatalog | Format-Table Id, Name, Purpose -AutoSize; exit 0 }
    $result = Invoke-CraftMain -AppIds $Apps -LauncherChoice $Launcher -Arch $Architecture -Scope $InstallScope -Headless $NoUI.IsPresent -Preview $PlanOnly.IsPresent
    exit $result
}

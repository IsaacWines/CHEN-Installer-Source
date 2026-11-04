# Dependency-free tests. No network, GUI, MSI execution, administrator rights, or installed apps required.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '../powershell/craftsuite_installer.ps1')

$script:passed = 0
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern = '*')
    try { & $Action } catch { if ($_.Exception.Message -notlike $Pattern) { throw }; return }
    throw 'Expected an exception.'
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $script:passed++
    Write-Host "PASS $Name"
}
function With-Mocks {
    param([hashtable]$Mocks, [scriptblock]$Action)
    $saved = @{}
    foreach ($name in $Mocks.Keys) {
        $saved[$name] = (Get-Item "Function:$name").ScriptBlock
        Set-Item "Function:script:$name" $Mocks[$name]
    }
    try { & $Action }
    finally { foreach ($name in $saved.Keys) { Set-Item "Function:script:$name" $saved[$name] } }
}
function New-FixtureAsset {
    param([string]$Name, [string]$Repo='photocraft', [string]$Digest=('sha256:' + ('a' * 64)))
    [pscustomobject]@{ name=$Name; browser_download_url="https://github.com/storytold/$Repo/releases/download/v1.2.3/$Name"; digest=$Digest; size=10 }
}
function New-FixtureRelease {
    [pscustomobject]@{
        tag_name='v1.2.3'; draft=$false; prerelease=$false
        assets=@(
            New-FixtureAsset 'photocraft-1.2.3-windows-x64.msi'
            New-FixtureAsset 'photocraft-1.2.3-windows-arm64.msi'
            New-FixtureAsset 'photocraft-1.2.3-windows-x86.msi'
            New-FixtureAsset 'photocraft-1.2.3-windows-x64-portable.zip'
            New-FixtureAsset 'photocraft-1.2.3-linux-x86_64.deb'
        )
    }
}
$photo = Get-CraftCatalog | Where-Object Id -eq 'photocraft'

Test-Case 'CHEN catalog exposes exactly one enabled self-contained installer entry' {
    # Windows PowerShell 5.1 emits ConvertFrom-Json arrays as one pipeline object.
    $catalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../installers.json') -Raw | ConvertFrom-Json
    $entry = @($catalog | Where-Object scriptPath -eq 'powershell/craftsuite_installer.ps1')
    Assert-True ($entry.Count -eq 1 -and $entry[0].enabled -and $entry[0].scriptType -eq 'powershell') 'Missing CraftSuite installer entry.'
}
Test-Case 'Catalog has 13 Craft apps, the separate studio and the optional launcher' {
    $catalog = @(Get-CraftCatalog)
    Assert-True ($catalog.Count -eq 15) 'Wrong catalog count.'
    Assert-True (@($catalog | Where-Object Kind -eq 'Craft').Count -eq 13) 'Wrong Craft app count.'
    Assert-True (@($catalog.Id | Select-Object -Unique).Count -eq 15) 'Duplicate repository IDs.'
}
Test-Case 'Launcher is optional, can be installed alone, and selection deduplicates' {
    $apps = @(Resolve-CraftSelection 'PHOtocraft, wordcraft,photocraft' 'Omit')
    Assert-True ($apps.Count -eq 2 -and 'craft-launcher' -notin $apps.Id) 'Unexpected selection.'
    $apps = @(Resolve-CraftSelection 'photocraft' 'Include')
    Assert-True ($apps.Count -eq 2 -and $apps[-1].Id -eq 'craft-launcher') 'Launcher should be last.'
    $apps = @(Resolve-CraftSelection '' 'Include')
    Assert-True ($apps.Count -eq 1 -and $apps[0].Id -eq 'craft-launcher') 'Launcher-only failed.'
    Assert-Throws { Resolve-CraftSelection '' 'Omit' }
    Assert-Throws { Resolve-CraftSelection 'typo' 'Omit' } '*Unknown app*'
    Assert-Throws { Resolve-CraftSelection 'craft-launcher' 'Omit' }
    Assert-Throws { Resolve-CraftSelection 'photocraft' 'Prompt' }
}
Test-Case 'Native OS architecture wins over the PowerShell process architecture' {
    $savedArch = $env:PROCESSOR_ARCHITECTURE; $savedNative = $env:PROCESSOR_ARCHITEW6432
    try {
        $env:PROCESSOR_ARCHITECTURE = 'x86'; $env:PROCESSOR_ARCHITEW6432 = 'ARM64'
        Assert-True ((Get-CraftArchitecture) -eq 'arm64') 'ARM64 detection failed.'
        $env:PROCESSOR_ARCHITEW6432 = 'AMD64'
        Assert-True ((Get-CraftArchitecture) -eq 'x64') 'x64 detection failed.'
        $env:PROCESSOR_ARCHITEW6432 = ''; $env:PROCESSOR_ARCHITECTURE = 'x86'
        Assert-True ((Get-CraftArchitecture) -eq 'x86') 'x86 detection failed.'
    }
    finally { $env:PROCESSOR_ARCHITECTURE = $savedArch; $env:PROCESSOR_ARCHITEW6432 = $savedNative }
}
Test-Case 'Exactly the correct MSI is chosen for each architecture' {
    foreach ($arch in @('x64', 'arm64', 'x86')) {
        $asset = Select-CraftAsset $photo (New-FixtureRelease) $arch
        Assert-True ($asset.name -ceq "photocraft-1.2.3-windows-$arch.msi") 'Wrong asset.'
    }
    $release = New-FixtureRelease; $release.assets = @()
    Assert-Throws { Select-CraftAsset $photo $release 'x64' } '*found 0*'
    $release = New-FixtureRelease; $release.assets += $release.assets[0]
    Assert-Throws { Select-CraftAsset $photo $release 'x64' } '*found 2*'
    $release = New-FixtureRelease; $release.prerelease = $true
    Assert-Throws { Select-CraftAsset $photo $release 'x64' } '*stable release*'
}
Test-Case 'AI Studio naming is handled separately and never falls back to an incompatible MSI' {
    $studio = Get-CraftCatalog | Where-Object Id -eq 'artcraft'
    $release = [pscustomobject]@{ tag_name='artcraft-v1.2.3'; draft=$false; prerelease=$false; assets=@(New-FixtureAsset 'ArtCraft_1.2.3_x64_en-US.msi' 'artcraft') }
    Assert-True ((Select-CraftAsset $studio $release 'x64').name -ceq 'ArtCraft_1.2.3_x64_en-US.msi') 'Studio asset failed.'
    Assert-Throws { Select-CraftAsset $studio $release 'arm64' } '*x64 MSI only*'
}
Test-Case 'Release downloads must belong to the selected official repository' {
    Assert-CraftReleaseUrl 'https://github.com/storytold/photocraft/releases/download/v1/a.msi' 'photocraft'
    foreach ($url in @(
        'http://github.com/storytold/photocraft/releases/download/v1/a.msi',
        'https://github.com/other/photocraft/releases/download/v1/a.msi',
        'https://github.com/storytold/wordcraft/releases/download/v1/a.msi',
        'https://github.com.evil.example/storytold/photocraft/releases/download/v1/a.msi',
        'https://github.com/storytold/photocraft/releases/download/v1/a.msi?redirect=elsewhere'
    )) { Assert-Throws { Assert-CraftReleaseUrl $url 'photocraft' } '*Unexpected release URL*' }
}
Test-Case 'API SHA-256 digest is used and checksum files require one exact filename match' {
    $release = New-FixtureRelease
    Assert-True ((Get-CraftExpectedHash $photo $release $release.assets[0]) -eq ('a' * 64)) 'API digest failed.'
    $hash = 'b' * 64
    $text = "$hash  unrelated.msi`r`n$hash *photocraft.msi`r`n"
    Assert-True ((Get-CraftChecksumFromText $text 'photocraft.msi') -eq $hash) 'Checksum parsing failed.'
    Assert-Throws { Get-CraftChecksumFromText $text 'photo.msi' }
    Assert-Throws { Get-CraftChecksumFromText ($text + $text) 'photocraft.msi' }
    $release.assets[0].digest = $null
    Assert-Throws { Get-CraftExpectedHash $photo $release $release.assets[0] } '*No published SHA-256*'
}
Test-Case 'Checksum-file fallback is used when the API has no digest' {
    $release = New-FixtureRelease; $release.assets[0].digest = $null
    $release.assets += New-FixtureAsset 'SHA256SUMS.txt'
    # Only intercept the network call; exercise the real fallback and exact checksum parser.
    function Invoke-WebRequest { param($Uri, [switch]$UseBasicParsing, $TimeoutSec) [pscustomobject]@{ Content=(('c' * 64) + '  photocraft-1.2.3-windows-x64.msi') } }
    Assert-True ((Get-CraftExpectedHash $photo $release $release.assets[0]) -eq ('c' * 64)) 'Checksum fallback failed.'
}
Test-Case 'MSI command quotes paths, suppresses restart and distinguishes install scopes' {
    $args = Get-CraftMsiArguments 'C:\a folder\app.msi' 'C:\logs folder\app.log' 'AllUsers'
    Assert-True ($args.Contains('/i "C:\a folder\app.msi"') -and $args.Contains('/norestart') -and $args.Contains('ALLUSERS=1')) 'Unsafe MSI arguments.'
    Assert-True ((Get-CraftMsiArguments 'a' 'b' 'CurrentUser').Contains('MSIINSTALLPERUSER=1')) 'Missing user scope.'
    Assert-True (-not (Get-CraftMsiArguments 'a' 'b' 'PackageDefault').Contains('ALLUSERS')) 'Studio scope should be native.'
    Assert-Throws { Get-CraftMsiArguments 'a"b' 'c' 'CurrentUser' }
}
Test-Case 'Download planning preserves user choice and does not execute an installer' {
    With-Mocks @{
        'Get-CraftRelease' = { param($Repo) New-FixtureRelease }
        'Invoke-CraftMsi' = { throw 'Plan must never install.' }
    } {
        $plan = @(New-CraftPlan @(Resolve-CraftSelection 'photocraft' 'Omit') 'x64' 'AllUsers')
        Assert-True ($plan.Count -eq 1 -and $plan[0].Scope -eq 'AllUsers') 'Wrong plan.'
        Assert-True ($plan[0].SHA256 -eq ('a' * 64)) 'Missing verification.'
    }
}
Test-Case 'Everyone app scope never becomes a machine-wide launcher install' {
    With-Mocks @{
        'Get-CraftRelease' = {
            param($Repo)
            $prefix = $Repo; if ($Repo -eq 'craft-launcher') { $prefix = 'artcraft-launcher' }
            [pscustomobject]@{ tag_name='v1.2.3'; draft=$false; prerelease=$false; assets=@(New-FixtureAsset "$prefix-1.2.3-windows-x64.msi" $Repo) }
        }
    } {
        $plan = @(New-CraftPlan @(Resolve-CraftSelection 'photocraft' 'Include') 'x64' 'AllUsers')
        Assert-True ($plan.Count -eq 2 -and $plan[0].Scope -eq 'AllUsers' -and $plan[1].Scope -eq 'CurrentUser') 'Launcher scope was changed.'
    }
}
Test-Case 'Main preview returns success without downloading or installing; unresolved choices fail' {
    With-Mocks @{
        'Get-CraftRelease' = { param($Repo) New-FixtureRelease }
        'Save-CraftDownload' = { throw 'Preview must not download.' }
        'Invoke-CraftMsi' = { throw 'Preview must not install.' }
    } {
        $code = Invoke-CraftMain 'photocraft' 'Omit' 'x64' 'CurrentUser' $true $true
        Assert-True ($code -eq 0) 'Preview failed.'
        $code = Invoke-CraftMain 'photocraft' 'Prompt' 'x64' 'CurrentUser' $true $true
        Assert-True ($code -eq 1) 'Headless mode silently chose a launcher preference.'
    }
}
Test-Case 'Failure while resolving a later app stops the run before the first app installs' {
    With-Mocks @{
        'Get-CraftRelease' = { param($Repo) if ($Repo -eq 'wordcraft') { throw 'Release unavailable.' }; New-FixtureRelease }
        'Save-CraftDownload' = { throw 'Incomplete plan must not download.' }
        'Invoke-CraftMsi' = { throw 'Incomplete plan must not install.' }
    } {
        $code = Invoke-CraftMain 'photocraft,wordcraft' 'Omit' 'x64' 'CurrentUser' $true $true
        Assert-True ($code -eq 1) 'Incomplete plan was accepted.'
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('chen-craft-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
try {
    $path = Join-Path $testRoot 'sample.msi'
    Set-Content -LiteralPath $path -Value 'fixture bytes'
    $goodHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Test-Case 'Hash mismatch blocks installation and a matching hash passes' {
        Assert-CraftFileHash $path $goodHash
        Assert-Throws { Assert-CraftFileHash $path ('0' * 64) } '*SHA-256 mismatch*'
        Assert-Throws { Assert-CraftFileHash $path 'invalid' }
    }
    $plan = @(
        [pscustomobject]@{ Id='photocraft'; Name='PhotoCraft'; Version='v1'; Scope='CurrentUser'; FileName='photo.msi'; Url='https://github.com/storytold/photocraft/releases/download/v1/photo.msi'; SHA256=$goodHash }
        [pscustomobject]@{ Id='wordcraft'; Name='WordCraft'; Version='v1'; Scope='CurrentUser'; FileName='word.msi'; Url='https://github.com/storytold/wordcraft/releases/download/v1/word.msi'; SHA256=$goodHash }
    )
    $downloadMock = { param($Url, $Destination) Set-Content -LiteralPath $Destination -Value 'fixture bytes' }
    Test-Case 'A corrupt download never reaches msiexec; later selected apps can still install' {
        $script:msiCalls = 0
        $corrupt = @($plan | ForEach-Object { $_ | Select-Object * }); $corrupt[0].SHA256 = '0' * 64
        With-Mocks @{
            'Save-CraftDownload' = $downloadMock
            'Invoke-CraftMsi' = { param($Path, $LogPath, $Scope) $script:msiCalls++; return 0 }
        } {
            $results = @(Invoke-CraftInstallPlan $corrupt $testRoot $testRoot)
            Assert-True ($script:msiCalls -eq 1 -and $results[0].Status -eq 'Failed' -and $results[1].Status -eq 'Installed') 'Corrupt package reached MSI or remaining selection was lost.'
            Assert-True ((Get-CraftResultCode $results) -eq 1) 'Partial failure must fail the parent task.'
            Assert-True (-not (Test-Path (Join-Path $testRoot 'photo.msi'))) 'Download was not cleaned up.'
        }
    }
    Test-Case 'MSI error and restart-required codes produce accurate results' {
        With-Mocks @{
            'Save-CraftDownload' = $downloadMock
            'Invoke-CraftMsi' = { param($Path, $LogPath, $Scope) if ($Path -like '*photo.msi') { return 1603 }; return 3010 }
        } {
            $results = @(Invoke-CraftInstallPlan $plan $testRoot $testRoot)
            Assert-True ($results[0].ExitCode -eq 1603 -and $results[0].Status -eq 'Failed') 'MSI failure lost.'
            Assert-True ($results[1].ExitCode -eq 3010 -and $results[1].Status -like 'Installed*') 'Reboot handling failed.'
            Assert-True ((Get-CraftResultCode @($results[1])) -eq 0) 'Reboot is success in existing CHEN GUI.'
        }
    }
    Test-Case 'Native cancellation and reboot initiation stop the remaining queue' {
        foreach ($exitCode in @(1602, 1641)) {
            $script:fixtureExit = $exitCode; $script:msiCalls = 0
            With-Mocks @{
                'Save-CraftDownload' = $downloadMock
                'Invoke-CraftMsi' = { param($Path, $LogPath, $Scope) $script:msiCalls++; return $script:fixtureExit }
            } {
                $results = @(Invoke-CraftInstallPlan $plan $testRoot $testRoot)
                Assert-True ($script:msiCalls -eq 1 -and $results[1].Status -eq 'Not attempted') 'Queue continued after cancellation/reboot.'
                Assert-True ((Get-CraftResultCode $results) -eq 1) 'Incomplete queue should not claim full success.'
            }
        }
    }
}
finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }

Write-Host "$script:passed tests passed. No apps were installed."

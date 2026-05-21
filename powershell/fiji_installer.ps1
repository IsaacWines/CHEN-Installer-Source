
# Initialize Common GUI Helper and Script Functions
. "$PSScriptRoot\common.ps1"

# Set URL and download location for FIJI
Send-GuiProgress 5 "Selecting download folder"

$url = "https://downloads.imagej.net/fiji/latest/fiji-latest-win64-jdk.zip"

$downloadFolder = "C:\Users\Public\Public Documents"
$fileName = Split-Path ([Uri]$url).AbsolutePath -Leaf

$outputPath = Join-Path $downloadFolder $fileName
$unzipPath = $downloadFolder
$fijiPath = "C:\Users\Public\Public Documents\Fiji"
$fijiExe = "C:\Users\Public\Public Documents\Fiji\fiji-windows-x64.exe"

$publicDesktopShortcut = "C:\Users\Public\Desktop\FIJI.lnk"
$startMenuShortcut = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\FIJI.lnk"

Write-Output "Download path: $outputPath"
Write-Output "Unzip path: $unzipPath"

# Make sure the folder exists
Send-GuiProgress 10 "Creating download folder"
New-Item -ItemType Directory -Force -Path $downloadFolder | Out-Null

# Remove old zip if it exists
if (Test-Path $outputPath) {
    Send-GuiProgress 15 "Removing old FIJI ZIP"
    Remove-Item $outputPath -Force
}

# Remove old unzip if it exists
if (Test-Path $fijiPath) {
    Send-GuiProgress 15 "Removing old FIJI Install"
    Remove-Item $fijiPath -Force -recurse
}

# Remove old shortcuts if it exists
if (Test-Path $publicDesktopShortcut) {
    Send-GuiProgress 15 "Removing old FIJI Desktop Shortcut"
    Remove-Item $publicDesktopShortcut -Force
}

if (Test-Path $startMenuShortcut) {
    Send-GuiProgress 15 "Removing old FIJI Start Menu Shortcut"
    Remove-Item $startMenuShortcut -Force
}



# Download the file
Send-GuiProgress 20 "Downloading FIJI"

$oldProgressPreference = $ProgressPreference
$ProgressPreference = "SilentlyContinue"

try {
    Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
}
finally {
    $ProgressPreference = $oldProgressPreference
}

# Make sure download actually completed
if (-not (Test-Path $outputPath)) {
    Write-Error "FIJI download failed. File was not created."
    exit 1
}

Send-GuiProgress 60 "FIJI download complete"

# Unzip the download
Send-GuiProgress 70 "Unzipping FIJI download"

New-Item -ItemType Directory -Force -Path $unzipPath | Out-Null
Expand-Archive -Path $outputPath -DestinationPath $unzipPath -Force

# Delete ZIP
Send-GuiProgress 75 "FIJI ZIP Cleanup"
Remove-Item -Path $outputPath -Force

Send-GuiProgress 90 "Creating FIJI shortcuts"

New-Shortcut `
    -TargetPath $fijiExe `
    -ShortcutPath $publicDesktopShortcut `
    -Description "FIJI ImageJ"

New-Shortcut `
    -TargetPath $fijiExe `
    -ShortcutPath $startMenuShortcut `
    -Description "FIJI ImageJ"

Send-GuiProgress 100 "FIJI install complete"

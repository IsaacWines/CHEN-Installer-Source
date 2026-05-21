
# Initialize Common GUI Helper and Script Functions
. "$PSScriptRoot\common.ps1"

# Path vars
$url = "https://downloads.imagej.net/fiji/latest/fiji-latest-win64-jdk.zip"

$downloadFolder = "C:\Users\Public\Public Documents"
$fileName = Split-Path ([Uri]$url).AbsolutePath -Leaf

$outputPath = Join-Path $downloadFolder $fileName
$unzipPath = $downloadFolder
$fijiPath = "C:\Users\Public\Public Documents\Fiji"
$fijiExe = "C:\Users\Public\Public Documents\Fiji\fiji-windows-x64.exe"

$publicDesktopShortcut = "C:\Users\Public\Desktop\FIJI.lnk"
$startMenuShortcut = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\FIJI.lnk"

# Check for any FIJI related files
Send-GuiProgress 20 "Checking for all FIJI files..."

if ((Test-Path $outputPath) -or (Test-Path $fijiPath) -or (Test-Path $publicDesktopShortcut) -or (Test-Path $startMenuShortcut)) {
  # Remove old zip if it exists
  if (Test-Path $outputPath) {
      Send-GuiProgress 30 "Found old FIJI ZIP"
      Send-GuiProgress 35 "Removing $outputPath"
      Remove-Item $outputPath -Force
  }
  
  # Remove old unzip if it exists
  if (Test-Path $fijiPath) {
      Send-GuiProgress 50 "Found old FIJI Install"
      Send-GuiProgress 55 "Removing $fijiPath"
      Remove-Item $fijiPath -Force -recurse
  }
  
  # Remove old shortcuts if it exists
  if (Test-Path $publicDesktopShortcut) {
      Send-GuiProgress 70 "Found old FIJI Desktop Shortcut"
      Send-GuiProgress 75 "Removing $publicDesktopShortcut"
      Remove-Item $publicDesktopShortcut -Force
  }
  
  if (Test-Path $startMenuShortcut) {
      Send-GuiProgress 90 "Found old FIJI Start Menu Shortcut"
      Send-GuiProgress 95 "Removing $startMenuShortcut"
      Remove-Item $startMenuShortcut -Force
  }

}
else {
    Send-GuiProgress 90 "No FIJI files found"
}


Send-GuiProgress 100 "FIJI uninstall complete"

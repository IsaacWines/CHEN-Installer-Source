# ~/powershell/COMSOL64/COMSOL64_installer.ps1
#
# ===========================================
# Installer Powershell Script for COMSOL 6.4
# ===========================================
# ---
# Utilizes a dynamically generated setupconfig.ini
# ---

param(

  # GUI Network Root 
  [string]$NetworkRoot = "",

  # Optional Manual Override
  [string]$InstallerPath = "",

  # setupconfig.ini File From Repo
  [string]$SetupConfigUrl = "",

  # Initialize Common GUI Helper and Script Functions
  [string]$CommonPath = "$PSScriptRoot\common.ps1",

  # COMSOL Install Path
  [string]$InstallDirectory = "C:\Program Files\COMSOL\COMSOL64\Multiphysics",

  # Values From GUI Prompts 
  [string]$InstallMode = "install",
  [string]$LicensePort = "",
  [string]$LicenseServer = "",
  [string]$ComsolUserName = "",
  [string]$CompanyName = "",

  # Optional Script Behaviors
  [switch]$NoComsolGui,
  [switch]$NoConfirm
)

$ErrorActionPreference = "Stop"

$script:COMSOL64NetworkRelativePath = "Support\Software\Comsol Multiphysics\Software\Comsol 6.4\378\setup.exe"

$script:TempDir = "C:\Temp"
$script:DownloadedConfigPath = Join-Path $script:TempDir "setupconfig.comsol64.downloaded.ini"
$script:FinalConfigPath = Join-Path $script:TempDir "setupconfig.ini"
$script:WrapperLogPath = Join-Path $script:TempDir "comsol64_install_wrapper.log"
$script:InstallerOutputLogPath = Join-Path $script:TempDir "comsol64_installer_output.log"

# ==========================
# Load common.ps1
# ==========================

if (Test-Path -Path $CommonPath -PathType Leaf) {
    . $CommonPath
}
else {
    [Console]::Out.WriteLine("WARNING: common.ps1 not found at: $CommonPath")
}

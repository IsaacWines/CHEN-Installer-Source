# CHEN Installer Source

Public script/config source for the CHEN Installer Tool.

This repository contains installer configuration files and PowerShell scripts used by the CHEN Installer GUI. The GUI reads installer metadata, downloads or runs the appropriate script, and reports progress back through a simple progress-output format.

## Repository Structure

```text
CHEN-Installer-Source/
├── installers.json
├── powershell/
│   ├── common.ps1
│   ├── fiji_installer.ps1
│   ├── fiji_uninstaller.ps1
│   └── matlab_installer.ps1
└── batch/
```

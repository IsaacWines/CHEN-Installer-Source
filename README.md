# CHEN Installer Source

Public script/config source for the CHEN Installer Tool.

This repository contains installer configuration files and PowerShell scripts used by the CHEN Installer GUI. The GUI reads installer metadata, downloads or runs the appropriate script, and reports progress through a simple progress-output format.

## Repository Structure

```text
CHEN-Installer-Source/
├── installers.json
├── powershell/
│   ├── common.ps1
│   ├── fiji_installer.ps1
│   ├── fiji_uninstaller.ps1
│   ├── matlab_installer.ps1
│   ├── python_manager.ps1
│   └── COMSOL/
│       └── COMSOL_installer.ps1
└── batch/
```

## Installer Metadata

The root `installers.json` file controls which installers appear in the CHEN Installer GUI. Each entry contains:

| Field | Purpose |
|---|---|
| `name` | Display name shown in the CHEN Installer GUI. |
| `scriptType` | Script runtime. Current PowerShell installers use `powershell`. |
| `scriptPath` | Path to the installer script relative to the repository root. |
| `arguments` | Optional command-line arguments passed to the script. |
| `enabled` | Whether the installer should appear in the GUI. |

Current installer entries include:

```json
[
  {
    "name": "MATLAB Installer",
    "scriptType": "powershell",
    "scriptPath": "powershell/matlab_installer.ps1",
    "arguments": "",
    "enabled": true
  },
  {
    "name": "FIJI Installer",
    "scriptType": "powershell",
    "scriptPath": "powershell/fiji_installer.ps1",
    "arguments": "",
    "enabled": true
  },
  {
    "name": "FIJI Uninstaller",
    "scriptType": "powershell",
    "scriptPath": "powershell/fiji_uninstaller.ps1",
    "arguments": "",
    "enabled": true
  },
  {
    "name": "COMSOL Un/Installer",
    "scriptType": "powershell",
    "scriptPath": "powershell/COMSOL/COMSOL_installer.ps1",
    "arguments": "",
    "enabled": true
  },
  {
    "name": "Python Version Manager",
    "scriptType": "powershell",
    "scriptPath": "powershell/python_manager.ps1",
    "arguments": "",
    "enabled": true
  }
]
```

## Shared PowerShell Helpers

Shared helper functions are stored in:

```text
powershell/common.ps1
```

Installer scripts should dot-source `common.ps1` when they need shared behavior such as:

- sending progress back to the parent GUI with `Send-GuiProgress`
- checking for administrator rights with `Test-IsAdmin`
- creating shortcuts with `New-Shortcut`
- downloading files with `Invoke-FileDownload`
- extracting zip archives with `Expand-ZipToFolder`
- prompting for network roots with `Get-GuiNetworkRoot`

Example:

```powershell
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $ScriptDirectory "common.ps1")
```

## Python Version Manager

`powershell/python_manager.ps1` opens a WinForms GUI for installing, uninstalling, and managing multiple system Python versions through Chocolatey.

### Requirements

- Windows
- PowerShell 5.1 or newer
- Administrator rights
- Chocolatey installed and available as `choco.exe`
- `powershell/common.ps1` in the same folder as `python_manager.ps1`

The script self-elevates when it is not already running as Administrator. Administrator rights are required because the script installs system software and edits the machine-level `Path` environment variable.

### Supported Python Versions

| GUI Label | Chocolatey Package | Install Folder | Group |
|---|---|---|---|
| Python 3.14 | `python314` | `C:\Python314` | Recommended |
| Python 3.13 | `python313` | `C:\Python313` | Recommended |
| Python 3.12 | `python312` | `C:\Python312` | Recommended |
| Python 3.11 | `python311` | `C:\Python311` | Older Compatibility |
| Python 3.10 | `python310` | `C:\Python310` | Older Compatibility |

### GUI Actions

| Button | Behavior |
|---|---|
| Install / Update + Make Default | Installs or upgrades the selected Python version with Chocolatey, then makes that version the managed default on the system `Path`. |
| Uninstall + Remove PATH | Uninstalls the selected Chocolatey Python package and removes that version's managed `Path` entries. |
| Make Selected Default PATH | Removes other managed Python entries from the system `Path`, then adds the selected version's install folder and `Scripts` folder. |
| Remove Selected From PATH | Removes only the selected Python version from the system `Path`. This does not uninstall Python. |
| Refresh Status | Rechecks whether each managed Python version is installed and whether it is currently on the system `Path`. |
| Remove ALL Managed Python PATH Entries | Removes all managed `C:\Python310` through `C:\Python314` entries from the system `Path`. This does not uninstall Python. |
| Open System Environment Variables | Opens the Windows advanced system settings panel. |

### PATH Management Behavior

The Python manager intentionally avoids putting every installed Python version on the system `Path` at the same time. Only one managed Python version should be the default `python`/`pip` target.

When a version is made default, the script removes these managed entries first:

```text
C:\Python310
C:\Python310\Scripts
C:\Python311
C:\Python311\Scripts
C:\Python312
C:\Python312\Scripts
C:\Python313
C:\Python313\Scripts
C:\Python314
C:\Python314\Scripts
```

Then it adds only the selected version's entries. For example, setting Python 3.14 as default adds:

```text
C:\Python314
C:\Python314\Scripts
```

This prevents PATH ordering conflicts where the wrong `python.exe` or `pip.exe` is found first.

### Chocolatey Commands Used

The Python manager wraps Chocolatey with enhanced exit-code handling.

Install or upgrade pattern:

```powershell
choco upgrade <package> -y --no-progress --params "/InstallDir:<install-folder>" --use-package-exit-codes
```

Uninstall pattern:

```powershell
choco uninstall <package> -y --no-progress --use-package-exit-codes
```

Valid Chocolatey success or soft-success exit codes handled by the script:

```text
0, 1605, 1614, 1641, 3010
```

### Optional Arguments

The script supports an optional custom Chocolatey source:

```powershell
.\powershell\python_manager.ps1 -ChocolateySource "https://your-choco-source.example/api/v2/"
```

For troubleshooting elevation behavior, the script also supports:

```powershell
.\powershell\python_manager.ps1 -NoSelfElevate
```

## Progress Output Format

Installer scripts should report progress using the shared `Send-GuiProgress` function when possible. This keeps the CHEN Installer GUI informed about the current step and completion percentage.

Example:

```powershell
Send-GuiProgress -Percent 50 -Message "Installing Python 3.14..."
```

## Development Notes

- Keep installer scripts idempotent when possible.
- Prefer predictable install folders for software that must be managed later.
- Avoid silently changing system-wide settings unless the GUI label clearly says what will happen.
- When editing the machine-level `Path`, preserve unrelated existing entries.
- If an installer requires Administrator rights, check early and fail clearly or self-elevate.
- Keep `installers.json` paths relative to the repository root.

## Basic Local Test Flow

From the repository root on a Windows machine:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\powershell\python_manager.ps1
```

Recommended checks after opening the Python manager:

1. Click `Refresh Status`.
2. Select a Python version.
3. Click `Install / Update + Make Default`.
4. Open a new terminal and run:

```powershell
python --version
pip --version
where python
where pip
```

5. Use `Remove Selected From PATH` or `Remove ALL Managed Python PATH Entries` if the default needs to be reset.

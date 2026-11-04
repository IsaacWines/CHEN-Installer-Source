# CHEN Installer Source

Public script/config source for the CHEN Installer Tool.

This repository contains installer configuration files and PowerShell scripts used by the CHEN Installer GUI. The GUI reads installer metadata, downloads or runs the appropriate script, and reports progress through a simple progress-output format.

## Quick Start

1. Open the [CHEN Installer Tool](https://github.com/IsaacWines/CHEN-Installers) on Windows and click **Refresh**.
2. Select the installer you want, then click **Install**.
3. For **Craft App Suite + Optional Launcher**, choose individual apps and check **Also install ArtCraft Launcher (optional)** if you want the central app hub.
4. Choose the Craft app install scope and click **Install selected**. Follow progress in the CHEN log.
5. Open installed apps or **ArtCraft Launcher** from the Start menu in your normal desktop session.

The GUI reads [installers.json](installers.json) from this repository's `main` branch and downloads the selected script. The Craft installer is available through Refresh without rebuilding the GUI. Requirements vary by installer; see the sections below.

## Repository Structure

| Path | Contents |
| --- | --- |
| [installers.json](installers.json) | Installer names, script paths, arguments and availability in the GUI. |
| [powershell/](powershell/) | Installer scripts and shared helpers, including the self-contained Craft installer. |
| [powershell/COMSOL/](powershell/COMSOL/) | COMSOL installer and setup configuration. |
| [powershell/COMSOL64/](powershell/COMSOL64/) | Additional COMSOL installer and setup configuration. |
| [docs/craftsuite-installer.md](docs/craftsuite-installer.md) | Detailed Craft app setup, scopes, logging and Windows acceptance checks. |
| [tests/craftsuite.tests.ps1](tests/craftsuite.tests.ps1) | Dependency-free Craft installer tests; no apps are installed. |
| [.github/workflows/craftsuite-tests.yml](.github/workflows/craftsuite-tests.yml) | Windows PowerShell 5.1 and PowerShell 7 CI checks. |

## Installer Metadata

The root `installers.json` file controls which installers appear in the CHEN Installer GUI. Each entry contains:

| Field | Purpose |
|---|---|
| `name` | Display name shown in the CHEN Installer GUI. |
| `scriptType` | Script runtime. Current PowerShell installers use `powershell`. |
| `scriptPath` | Path to the installer script relative to the repository root. |
| `arguments` | Optional command-line arguments passed to the script. |
| `enabled` | Whether the installer should appear in the GUI. |

Current enabled installer entries:

| Installer | Script |
| --- | --- |
| MATLAB Installer | [powershell/matlab_installer.ps1](powershell/matlab_installer.ps1) |
| FIJI Installer | [powershell/fiji_installer.ps1](powershell/fiji_installer.ps1) |
| FIJI Uninstaller | [powershell/fiji_uninstaller.ps1](powershell/fiji_uninstaller.ps1) |
| COMSOL Un/Installer | [powershell/COMSOL/COMSOL_installer.ps1](powershell/COMSOL/COMSOL_installer.ps1) |
| Python Version Manager | [powershell/python_manager.ps1](powershell/python_manager.ps1) |
| Git Installer | [powershell/git_installer.ps1](powershell/git_installer.ps1) |
| Office 2024 PTB Installer | [powershell/office2024_ptb_installer.ps1](powershell/office2024_ptb_installer.ps1) |
| PDFgear Installer | [powershell/pdfgear_installer.ps1](powershell/pdfgear_installer.ps1) |
| Craft App Suite + Optional Launcher | [powershell/craftsuite_installer.ps1](powershell/craftsuite_installer.ps1) |

Example metadata entry:

```json
{
  "name": "Craft App Suite + Optional Launcher",
  "scriptType": "powershell",
  "scriptPath": "powershell/craftsuite_installer.ps1",
  "arguments": "",
  "enabled": true
}
```

## Craft App Suite and Optional Launcher

[powershell/craftsuite_installer.ps1](powershell/craftsuite_installer.ps1) opens a checklist for the apps listed on [CraftSuite](https://craftsuite.net/). The **Also install ArtCraft Launcher (optional)** checkbox is separate from the app checklist and starts unchecked. Select all/Clear apps affect only the app checklist.

| Selection | Result |
| --- | --- |
| Apps selected, launcher unchecked | Installs only the selected apps. |
| Apps selected, launcher checked | Installs the selected apps and ArtCraft Launcher in the same run. |
| No apps selected, launcher checked | Installs only ArtCraft Launcher. |

The [official ArtCraft Launcher](https://github.com/storytold/craft-launcher) provides the central interface for discovering, opening, installing and updating Craft apps. After installation, open it from the Start menu to access your installed Craft apps.

### Supported Apps

| Category | Apps |
| --- | --- |
| Photo, video and publishing | PhotoCraft, VectorCraft, FilmCraft, LightCraft, PdfCraft, EffectCraft, DesignCraft |
| Documents, spreadsheets and slides | WordCraft, GridCraft, DeckCraft |
| Drafting, audio and interface design | CADCraft, SoundCraft, FigCraft |
| Separate AI studio | ArtCraft AI Studio (Windows x64 only; opens separately; online AI services may require an account or payment) |
| Optional central app hub | ArtCraft Launcher |

### Requirements and Install Scope

- Windows 10/11 with Windows PowerShell 5.1 or newer and access to GitHub release downloads. Chocolatey is not required for this installer.
- Native x64, ARM64 and x86 MSI selection for the Craft apps and launcher. AI Studio is offered only on x64.
- **This account** is the default Craft app scope. **Everyone on this PC** requires running CHEN or PowerShell as Administrator. Updates must use the same scope as the existing installation.
- **ArtCraft Launcher remains per-user**, even if the Craft apps are installed for everyone. It installs for the account running the tool. If you use a different administrator's credentials to elevate CHEN, install the launcher separately from the intended user's session.
- ArtCraft AI Studio retains its own MSI's default installation scope.

### Standalone and Command-Line Use

From the repository root, open the selection dialog:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\powershell\craftsuite_installer.ps1
```

Install selected apps with the launcher, without the selection dialog:

```powershell
.\powershell\craftsuite_installer.ps1 -NoUI -Apps 'photocraft,wordcraft,pdfcraft' -Launcher Include
```

Use `-Launcher Omit` for apps only. For the launcher alone:

```powershell
.\powershell\craftsuite_installer.ps1 -NoUI -Launcher Include
```

Preview current versions, packages, download URLs, checksums and scopes without downloading MSIs or installing anything:

```powershell
.\powershell\craftsuite_installer.ps1 -NoUI -Apps 'photocraft,wordcraft' -Launcher Include -PlanOnly
```

`-NoUI` requires an explicit `-Launcher Include` or `-Launcher Omit`. Use `-ListApps` for valid app IDs, or `-InstallScope AllUsers` for an Everyone install from an elevated session.

### Verification and Logs

All packages come directly from the official `storytold` GitHub releases. The script resolves the complete selection before installation and verifies every downloaded MSI against a published SHA-256 digest. Packages install sequentially with Windows Installer progress and per-app results.

CHEN receives `CHEN_PROGRESS` updates. Per-run logs are saved under `CHEN_LOG_ROOT` when supplied by the GUI, or `%LOCALAPPDATA%\CHENInstaller\Logs` for standalone use. Each `CraftSuite_<run-id>` folder contains `plan.json`, `results.json` and per-app MSI logs. Failed packages are reported individually; cancelling a native MSI stops the remaining queue. Restart requirements are reported in the log.

### Validation

Run the dependency-free tests without installing apps:

```powershell
powershell.exe -NoProfile -File .\tests\craftsuite.tests.ps1
pwsh -NoProfile -File .\tests\craftsuite.tests.ps1
```

CI checks both Windows PowerShell 5.1 and PowerShell 7. The tests use fixtures for network and MSI operations; a real Windows installation and launcher discovery still require a manual smoke test.

See [CraftSuite installer instructions](docs/craftsuite-installer.md) for the complete app ID list, architecture options, error handling and Windows acceptance steps.

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

## Progress Output Format

Installer scripts should report progress using the shared `Send-GuiProgress` function when possible. This keeps the CHEN Installer GUI informed about the current step and completion percentage.

Example:

```powershell
Send-GuiProgress -Percent 50 -Message "Installing Python 3.14..."
```

`Send-GuiProgress` writes progress messages in this format:

```text
CHEN_PROGRESS|<percent>|<message>
```

Normal `Write-Host`, Chocolatey output, and script output should still appear in the main GUI terminal.

## Git Installer

`powershell/git_installer.ps1` installs or upgrades Git for Windows using Chocolatey. It does not open its own GUI, so output stays visible in the main CHEN Installer GUI terminal.

### Requirements

- Windows
- PowerShell 5.1 or newer
- Administrator rights
- Chocolatey installed and available as `choco.exe`
- `powershell/common.ps1` in the same folder as `git_installer.ps1`

The main CHEN Installer GUI should be launched as Administrator before running this installer. The script intentionally does not self-elevate because spawning a separate elevated process can break terminal output capture in the parent GUI.

### Behavior

The Git installer:

- loads `powershell/common.ps1`
- checks for Administrator rights
- checks that Chocolatey is available
- installs Git with Chocolatey if it is missing
- upgrades Git with Chocolatey if it is already installed
- adds `C:\Program Files\Git\cmd` to the machine-level `Path` if needed
- verifies the install by running `git --version`
- sends progress updates to the CHEN GUI progress bar
- writes normal status and Chocolatey output to the CHEN GUI terminal

### Chocolatey Command Used

Install or upgrade pattern:

```powershell
choco install git -y --no-progress --execution-timeout=2700
choco upgrade git -y --no-progress --execution-timeout=2700
```

If a custom Chocolatey source is needed, the script supports:

```powershell
.\powershell\git_installer.ps1 -ChocolateySource "https://your-choco-source.example/api/v2/"
```

### Manual Test

From the repository root on a Windows machine running as Administrator:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\powershell\git_installer.ps1
```

After install, open a new terminal and check:

```powershell
git --version
where git
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

### Manual Test

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

## Development Notes

- Keep installer scripts idempotent when possible.
- Prefer predictable install folders for software that must be managed later.
- Avoid silently changing system-wide settings unless the GUI label clearly says what will happen.
- When editing the machine-level `Path`, preserve unrelated existing entries.
- If an installer requires Administrator rights, check early and fail clearly or self-elevate only when parent GUI output capture will not be affected.
- Keep `installers.json` paths relative to the repository root.

## Recommended Line Ending Rules

This repo is edited from Windows, so adding a `.gitattributes` file is recommended to avoid Git line-ending warnings.

```gitattributes
* text=auto

*.ps1 text eol=crlf
*.bat text eol=crlf
*.cmd text eol=crlf
*.json text eol=lf
*.md text eol=lf
*.yml text eol=lf
*.yaml text eol=lf

*.zip binary
*.png binary
*.jpg binary
*.jpeg binary
*.ico binary
*.exe binary
*.dll binary
```

After adding or editing `.gitattributes`, run:

```powershell
git add .gitattributes
git add --renormalize .
git status
```

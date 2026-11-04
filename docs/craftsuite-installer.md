# Craft App Suite installer

## Use from CHEN

1. Open CHEN Installer Tool and click **Refresh**.
2. Select **Craft App Suite + Optional Launcher**, then click Install.
3. Check the desired apps. Nothing is selected automatically.
4. Check **Also install ArtCraft Launcher (optional)** if you want the central launcher.
5. Choose **This account** or **Everyone on this PC** for the Craft apps, then click **Install selected**.
6. Watch progress and results in CHEN's log. Open the installed apps or **ArtCraft Launcher** from the Start menu afterward.

The launcher is an independent selection: apps-only, launcher-only and apps plus
launcher all work. Select all/Clear apps affect the app checklist, leaving the
launcher checkbox independent. Cancelling the selection installs nothing.

## Apps

| ID | App | Purpose |
| --- | --- | --- |
| `photocraft` | PhotoCraft | Photo editing |
| `vectorcraft` | VectorCraft | Vector illustration |
| `filmcraft` | FilmCraft | Video editing |
| `lightcraft` | LightCraft | RAW photos and library |
| `pdfcraft` | PdfCraft | PDF tools |
| `effectcraft` | EffectCraft | Motion graphics and effects |
| `designcraft` | DesignCraft | Page layout |
| `wordcraft` | WordCraft | Documents |
| `gridcraft` | GridCraft | Spreadsheets |
| `deckcraft` | DeckCraft | Presentations |
| `cadcraft` | CADCraft | 2D drafting |
| `soundcraft` | SoundCraft | Audio recording and mixing |
| `figcraft` | FigCraft | Interface design |
| `artcraft` | ArtCraft AI Studio | Separate AI studio; Windows x64 only |
| `craft-launcher` | ArtCraft Launcher | Central Craft app launch/install/update interface |

The first 13 apps are the Craft App Suite. ArtCraft AI Studio is a separate
product: it opens separately, and online AI services may require an account or
payment. It is hidden from the ARM64/x86 checklist because its official Windows
release currently offers only an x64 MSI. A headless request for an unsupported
architecture fails before installation. Additional apps introduced upstream in
the future are outside this fixed catalog until explicitly added.

## Requirements and install scope

- Windows 10/11 and Windows PowerShell 5.1 or newer. No Chocolatey dependency.
- Internet access to the GitHub API and official GitHub release downloads.
- **This account** is the default scope. **Everyone** requires launching CHEN or PowerShell as Administrator.
- The Craft apps use the chosen scope; an existing installation must be updated
  using its existing scope. A conflicting scope is reported as an MSI failure;
  the script does not uninstall or move existing copies. Custom install folders
  are left to the official MSI's maintenance behavior.
- ArtCraft Launcher is **per-user only**, even when the Craft apps are installed
  for everyone. It is installed for the account running the tool. If CHEN is
  elevated with a different administrator's credentials, install the launcher
  separately from the intended user's session. A machine-wide launcher is not
  offered by the upstream MSI.
- AI Studio retains its own MSI's default scope and installation behavior.
- Launch installed apps afterward from your normal desktop session; the installer
  does not automatically start creative apps with its elevated privileges.

The selector runs as a dialog in the PowerShell child process. After it closes,
the existing CHEN GUI remains responsive and receives `CHEN_PROGRESS` messages.
Standalone use prints installation progress to the PowerShell terminal. Each
native MSI displays its own passive progress window. There is no background
CHEN service or extra auto-start component.

## Command-line use

From a checkout, open the selector:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\powershell\craftsuite_installer.ps1
```

Install selected apps and the launcher without the selection dialog:

```powershell
.\powershell\craftsuite_installer.ps1 -NoUI -Apps 'photocraft,wordcraft,pdfcraft' -Launcher Include
```

Apps only, for everyone (run as Administrator):

```powershell
.\powershell\craftsuite_installer.ps1 -NoUI -Apps 'photocraft,vectorcraft' -Launcher Omit -InstallScope AllUsers
```

Launcher only, for the current account:

```powershell
.\powershell\craftsuite_installer.ps1 -NoUI -Launcher Include
```

Preview current official release versions, exact packages, URLs, SHA-256 digests,
download sizes and install scopes. This reads metadata only; it does not download
MSIs, create log/cache directories or install anything:

```powershell
.\powershell\craftsuite_installer.ps1 -NoUI -Apps 'photocraft,wordcraft' -Launcher Include -PlanOnly
```

`-Architecture Auto` detects the native OS, even from a 32-bit PowerShell process.
Other architectures can be inspected with `-Architecture x64`, `arm64` or `x86`
in preview mode; actual installs require the native architecture. For a preview
from a non-Windows PowerShell 7 host, specify both `-Architecture` and `-NoUI`.
`-ListApps` lists the catalog without a network request. `-NoUI` requires an
explicit `-Launcher Include` or `-Launcher Omit`; it never guesses that choice.

## Downloads, verification and results

The installer resolves each selected app's latest non-prerelease GitHub release
from its exact repository under `storytold`. It chooses only that release's
Windows MSI for the native architecture. Launcher assets use the
`artcraft-launcher` filename prefix from the `craft-launcher` repository. AI Studio
uses its separate release and asset naming format.

The complete selection is resolved before downloading/installing any package.
Missing/ambiguous assets, unsupported architectures, missing checksums and API
errors stop that stage. SHA-256 comes from GitHub's release asset digest, with an
exact-filename `SHA256SUMS.txt` fallback. Every downloaded MSI is hashed before
execution. There is no skip-verification switch or third-party download mirror.

Packages install sequentially through Windows Installer with `/passive /norestart`
and verbose logging. A failed download, hash or MSI is recorded; later selected
apps can still install. Cancelling a native MSI (1602) or a reported reboot
initiation (1641) stops the remaining queue and records it as not attempted.
Restart-required (3010) is a successful installation and is reported explicitly.

Per-run records are saved below `CHEN_LOG_ROOT\CraftSuite_<run-id>` when CHEN
supplies that environment variable, otherwise below
`%LOCALAPPDATA%\CHENInstaller\Logs\CraftSuite_<run-id>`:

- `plan.json`: resolved versions, architecture, scope, URLs and checksums.
- `<app-id>-msi.log`: Windows Installer's verbose log for each attempted MSI.
- `results.json`: success, failure, native exit codes and error details.

Temporary downloads are cleaned up after each app and at normal process exit.
Forced termination can leave the uniquely named `CHEN_CraftSuite_<run-id>` temp
folder behind. The script returns 0 only when all requested packages succeeded;
partial failures and skipped selections return 1. Cancelling the initial selector
returns 0 with an explicit no-install message. Restart requirements remain in the
logs because the existing CHEN GUI treats every nonzero exit code as a failure.

## Validation

Run the dependency-free tests without installing apps:

```powershell
powershell.exe -NoProfile -File .\tests\craftsuite.tests.ps1
pwsh -NoProfile -File .\tests\craftsuite.tests.ps1
```

CI runs both Windows PowerShell 5.1 and PowerShell 7. The tests cover optional
launcher selection, native architecture, exact MSI selection, checksum fallback
and rejection, verification before execution, failure continuation, cancellation,
restart codes, scopes and cleanup. Tests replace network/MSI calls with fixtures;
they do not establish that a real MSI installs or that the launcher discovers it.

Before deployment, verify on a Windows test account:

1. Open the dialog from the current CHEN GUI. Cancel, empty-selection validation,
   Select all/Clear apps and the independent launcher checkbox should work.
2. Install PhotoCraft + WordCraft without the launcher; confirm their Start menu
   entries and that no launcher was added.
3. Install only the launcher. Open it from the user's Start menu and confirm it
   discovers and launches those installed apps.
4. Install apps + launcher together in a fresh account and repeat the launch check.
5. Rerun in the same scope, then test an Everyone install from an elevated session.
   Confirm app discovery, upgrade and normal Windows Apps uninstall behavior.
6. Cancel a native MSI and check the remaining queue is not attempted. Review
   `results.json`, CHEN output and restart-required reporting.

## Source references

- [CraftSuite directory](https://craftsuite.net/) (independent guide).
- [Official ArtCraft Launcher](https://github.com/storytold/craft-launcher).
- [Official launcher Windows installation policy](https://github.com/storytold/craft-launcher/blob/main/packaging/windows/INSTALLATION.md).
- [Official Craft app installation policy](https://github.com/storytold/photocraft/blob/main/packaging/windows/INSTALLATION.md).
- [Official ArtCraft AI Studio releases](https://github.com/storytold/artcraft/releases).

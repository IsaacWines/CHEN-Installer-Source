# ArcGIS Pro, Steam and Spectre system tools

These catalog entries work with the existing CHEN GUI: Refresh the list, check
the desired installer, and click Install. Each script uses the `common.ps1` helper
that CHEN already downloads beside PowerShell scripts. No GUI rebuild is needed.

## Requirements

Windows PowerShell 5.1+ and Microsoft App Installer/WinGet must be available for
the account running CHEN. These scripts do not bootstrap Chocolatey, require
Microsoft Store sign-in, or support running as SYSTEM. In environments where
App Installer or its community source is blocked by policy, use the publisher's
approved installer through your IT deployment process instead.

WinGet requests exact package IDs from the `winget` source, uses silent installers,
and accepts the selected package/source terms. Hash verification stays enabled.
There are no `--force`, `--ignore-security-hash`, `--uninstall-previous`,
`--allow-reboot` or source-reset operations. Installation scope follows the
supported publisher package, except where ArcGIS prerequisites explicitly need
machine scope. An existing latest/newer package is a successful no-op.

## ArcGIS Pro for Texas A&M

1. Select **ArcGIS Pro Installer (TAMU)** in CHEN.
2. Use **TAMU Software** for the personal-device distribution, or sign into
   **TAMU ArcGIS portal**. In ArcGIS Online, use My settings > Licenses > Download
   ArcGIS Pro if that download is enabled for your account. University-managed
   computers should use the authorized departmental distribution instead.
3. Run the authorized downloaded EXE to extract the setup files. Uncheck
   **Launch the setup program** on the extraction screen.
4. Browse to the extracted **ArcGISPro.msi** in CHEN's selector. Keep the complete
   extracted folder tree and companion files available through installation.
5. Choose the same scope as any existing ArcGIS Pro installation and accept the
   Esri license terms supplied with your download. Everyone installs require an
   elevated CHEN session.
6. The script checks the Esri Authenticode signature, product name/version and
   source hash, then installs prerequisites and runs the MSI with TAMU licensing
   properties. It rechecks the source hash before launching Windows Installer.
7. After installation, launch ArcGIS Pro from your normal account. Select
   **Your organization**, enter `tamu.maps.arcgis.com`, and use **Texas A&M NetID
   Login**. Your licensed account determines the available level/extensions.

This is an installer for authorized packages, not an anonymous ArcGIS downloader.
No Esri binaries, account credentials or license keys are stored in this public
repository. The script does not grant a license, select a Concurrent Use server,
force Advanced/ArcInfo, or silently remove an existing installation. If a download
or license is missing, contact TAMU's GIS Helpdesk at `gis-help@tamu.edu`.

| ArcGIS Pro release | Prerequisite |
| --- | --- |
| 3.3–3.6 | Microsoft .NET 8 Desktop Runtime, x64 |
| 3.7 | Microsoft .NET 10 Desktop Runtime, x64 |
| Other versions | Stop and verify Esri requirements before extending the mapping |

WebView2 Evergreen is installed/updated at machine scope. A prerequisite that
requires restarting Windows stops the run before the ArcGIS MSI; restart and
rerun. Esri's MSI handles additional setup requirements and existing-product
compatibility. Check the system requirements for the exact release your course
or department uses; this wrapper does not substitute a different ArcGIS version.

```powershell
# Open the selector.
.\powershell\arcgispro_tamu_installer.ps1

# Validate and inspect the plan; no prerequisites or MSI are installed.
.\powershell\arcgispro_tamu_installer.ps1 -NoUI -InstallerPath 'D:\ArcGISPro\ArcGISPro.msi' -PlanOnly

# Install for everyone from an elevated shell after reviewing the Esri terms.
.\powershell\arcgispro_tamu_installer.ps1 -NoUI -InstallerPath 'D:\ArcGISPro\ArcGISPro.msi' -InstallScope AllUsers -AcceptEula
```

For user scope, pass `-InstallScope CurrentUser`. Prerequisites may still require
administrator permission. License settings are not locked against later changes.

## Steam

**Steam Installer** uses `Valve.Steam`. It installs/updates the client without
uninstalling the existing copy or intentionally touching game libraries. It does
not sign in, purchase games, or download games. Existing client/library locations
are handled by Valve's installer; no custom location is forced.

```powershell
.\powershell\steam_installer.ps1
```

## System control for the Spectre 15-eb0xxx

**System Control Tools (ParkControl + HWiNFO)** opens a two-tool checklist. Choose
both or either individually. This entry targets native Intel/AMD x64 Windows,
including the user's Spectre; no compatible ARM64 ParkControl package is offered
by this catalog.

- **ParkControl** (`BitSum.ParkControl`) provides Windows power-plan and CPU power
  controls. Free features and optional paid Pro features remain the publisher's
  responsibility; the installer does not purchase or activate Pro.
- **HWiNFO** (`REALiX.HWiNFO`) provides sensor monitoring. Use Sensors-only to view
  CPU/GPU temperatures, clocks, power and throttling information. Free is for
  non-commercial use; use an appropriate license for organizational use or
  deselect it.

```powershell
.\powershell\system_control_installer.ps1
.\powershell\system_control_installer.ps1 -NoUI -Tools Both
.\powershell\system_control_installer.ps1 -NoUI -Tools ParkControl
.\powershell\system_control_installer.ps1 -NoUI -Tools HWiNFO
```

The installer does not apply power presets, disable CPU parking/turbo, undervolt,
write embedded-controller registers, remove HP components, or add CHEN startup
tasks. Publisher installation defaults remain publisher-controlled. Open the
tools afterward and choose settings that suit the machine.

This setup covers Windows power controls and monitoring. A full replacement for
the Spectre 15-eb0xxx's HP Command Center thermal profiles has not been verified.
Fan Control's official FAQ says most laptops do not expose compatible fans;
OmenMon targets supported HP Omen firmware. Neither establishes support for this
Spectre model. HP-specific thermal/fan profile switching still needs a verified
compatible controller such as HP Command Center. Firmware cooling remains active.

## Logs and exit codes

Logs are written to a unique per-run folder under `CHEN_LOG_ROOT` when the GUI
sets it, otherwise `%LOCALAPPDATA%\CHENInstaller\Logs`:

| Installer | Records |
| --- | --- |
| Steam | WinGet log and successful `results.json` |
| System tools | Per-package WinGet logs and `results.json`, including failures/skipped selections |
| ArcGIS Pro | `plan.json`, prerequisite WinGet logs and `prerequisites.json`, `ArcGISPro-msi.log`, final MSI `results.json` |

Errors include the log location where available. A failed system-tool package
does not prevent attempting the other selection. A reported reboot initiation
stops its remaining queue. Scripts return 1 on failure/incomplete selection and
0 on successful completion or an initial dialog cancellation. Restart needs are
logged rather than returned as a nonzero soft-success code, matching CHEN's
current success/failure handling. ArcGIS failure before its MSI may have only a
plan and prerequisite records; no final MSI result is claimed.

## Validation and acceptance

```powershell
powershell.exe -NoProfile -File .\tests\desktop-installers.tests.ps1
pwsh -NoProfile -File .\tests\desktop-installers.tests.ps1
```

Tests use fixtures for package acquisition and MSI execution. On Windows, they
also create a non-executable MSI database to exercise property reads and signature
rejection, and use timers to click actual selector controls. They never install
ArcGIS, Steam or hardware utilities. CI runs both Windows PowerShell versions.

Before deploying on a real Windows machine, test the authorized ArcGIS package
with its companion payload, prerequisites, existing scope, restart behavior and
actual TAMU license sign-in. Confirm Steam client installation/update preserves
its libraries. Confirm each system tool opens from Start; installation itself
does not prove firmware controls or performance gains.

## Primary references

- [TAMU Software](https://software.tamu.edu/public/AvailableSoftware.aspx) (personal-device catalog).
- [TAMU ArcGIS sign-in instructions](https://www.tamug.edu/it/services/computing-printing-software/Computer_Labs_and_VDI.html#ArcGIS).
- [Esri downloads](https://doc.esri.com/en/arcgis-pro/latest/get-started/download-arcgis-pro.html), [silent install parameters](https://doc.esri.com/en/arcgis-pro/latest/get-started/arcgis-pro-installation-administration.html), and [current system requirements](https://doc.esri.com/en/arcgis-pro/latest/get-started/arcgis-pro-system-requirements.html).
- [Valve Steam download](https://store.steampowered.com/about/).
- [Bitsum ParkControl](https://bitsum.com/parkcontrol/).
- [HWiNFO downloads and license terms](https://www.hwinfo.com/download/).
- [HP Command Center thermal profiles](https://support.hp.com/us-en/document/ish_9869095-9869168-16).
- [Fan Control laptop FAQ](https://github.com/Rem0o/FanControl.Releases#faq) and [OmenMon scope](https://github.com/OmenMon/OmenMon).
- [Microsoft WinGet commands](https://learn.microsoft.com/windows/package-manager/winget/install) and [exit codes](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md).

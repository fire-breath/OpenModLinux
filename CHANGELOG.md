# Changelog

## 0.2.0

### Added

- Dynamic installation of the latest stable official Vortex release.
- Unified Documents and Downloads integration for Wine and Proton prefixes.
- Vortex download mapping to the Linux Downloads directory.
- Per-game Vortex staging mapping to `C:\\Vortex Mods\\{GAME}`.
- Automatic integration of existing and newly created prefixes through a user systemd timer.

### Fixed

- Correct Vortex executable path: `C:\\Program Files\\Vortex\\Vortex.exe`.
- Correct Vortex working directory.
- Classic Wine and UMU/Proton prefix compatibility.
- Hardlink deployment failures caused by staging paths outside the Wine `C:` drive.

## 0.1.0 - 2026-07-19

- Added a standalone local Lutris installer for Vortex 2.2.0 stable.
- Added an immutable-tag script for submission to the Lutris catalog.
- Added native and Flatpak Steam library discovery.
- Added a synthetic Steam tree inside the Vortex Wine prefix.
- Added repeatable Steam resynchronization.
- Added an `nxm://` desktop handler that uses the Lutris-selected Wine binary.
- Added diagnostics, integration removal, smoke tests and GitHub Actions CI.

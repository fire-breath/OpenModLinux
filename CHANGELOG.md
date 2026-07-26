# Changelog

## 0.1.2

### Added

- Native Steam mapping at `C:\SteamLibrary` and same-device Vortex userdata.
- Hybrid-GPU-safe Vortex GLX/Electron launch configuration.
- Steam SKSE launch-option generator.
- Safe Engine Fixes preloader installation.
- Direct Microsoft Visual C++ runtime installation for Steam Proton prefixes.
- Generic SKSE plugin diagnostics and an Isekai Hero diagnostic shortcut.
- Skyrim/Linux documentation and smoke tests.

### Fixed

- Vortex hardlink deployment failures caused by cross-device or symlinked staging.
- Vortex GLX startup failures caused by forced NVIDIA PRIME variables.
- Incomplete Visual C++ runtime combinations in Proton prefixes.

## 0.2.0

### Added

- Dynamic installation of the latest stable official Vortex release.
- Unified Documents and Downloads integration for Wine and Proton prefixes.
- Vortex download mapping to the Linux Downloads directory.
- Vortex staging remains a real directory at `%APPDATA%\\Vortex\\{GAME}\\mods`.
- Automatic integration of existing and newly created prefixes through a user systemd timer.

### Fixed

- Correct Vortex executable path: `C:\\Program Files\\Vortex\\Vortex.exe`.
- Correct Vortex working directory.
- Classic Wine and UMU/Proton prefix compatibility.
- Hardlink deployment failures caused by external or symlinked staging paths.

## 0.1.0 - 2026-07-19

- Added a standalone local Lutris installer for Vortex 2.2.0 stable.
- Added an immutable-tag script for submission to the Lutris catalog.
- Added native and Flatpak Steam library discovery.
- Added a synthetic Steam tree inside the Vortex Wine prefix.
- Added repeatable Steam resynchronization.
- Added an `nxm://` desktop handler that uses the Lutris-selected Wine binary.
- Added diagnostics, integration removal, smoke tests and GitHub Actions CI.

# OpenModLinux — Universal Vortex installer for Lutris

OpenModLinux is a maintainable Lutris installer and Linux integration layer for
[Nexus Mods Vortex](https://github.com/Nexus-Mods/Vortex). It does **not** replace
Vortex. It installs the Windows Vortex application into a dedicated Lutris Wine
prefix and connects that prefix to native Steam libraries and `nxm://` links.

> Status: **0.1.0 alpha**. The installer is ready for local testing. It should be
> tested on several distributions before submission to the Lutris catalog.

## What the installer does

- creates a 64-bit Wine prefix through Lutris;
- installs `dotnet48` and `corefonts` through the Lutris Winetricks task;
- installs the official Vortex Windows build;
- detects native Steam installations, including normal and Flatpak Steam;
- creates a synthetic Steam tree inside the Vortex prefix using symbolic links;
- writes the Steam registry keys expected by Windows applications;
- registers a Linux `nxm://` URL handler without editing Lutris' SQLite database;
- installs a repeatable updater script for newly installed Steam games;
- keeps logs under `<Vortex prefix>/openmodlinux/logs`.

## Local test

Requirements: Lutris, a Wine runner installed in Lutris, Bash, Python 3,
`xdg-mime`, and an internet connection.

```bash
lutris -i ./lutris/vortex.yml
```

The installer currently pins the official Vortex **2.2.0 stable** installer.
The version and URL are kept in one place near the top of `lutris/vortex.yml`.

After installation, update Steam links at any time:

```bash
/path/to/vortex-prefix/openmodlinux/update.sh
```

Run diagnostics:

```bash
/path/to/vortex-prefix/openmodlinux/diagnose.sh /path/to/vortex-prefix
```

## Important limitation

For Vortex hardlink deployment, the Vortex staging directory and the target game
must be on the same filesystem. If a game is stored on another disk or mount,
configure that game's staging directory in Vortex on the same filesystem as the
game. Symlinked game directories alone cannot bypass the cross-filesystem
hardlink restriction.

## Repository layout

```text
lutris/vortex.yml          Standalone local Lutris installer
lutris/script-only.yml     Script section for submission on lutris.net
scripts/post-install.sh    Installs Linux integration into the prefix
scripts/sync-steam.sh      Rebuilds the synthetic Steam tree
scripts/steam-libraries.py Discovers Steam libraries and installed apps
scripts/install-nxm-handler.sh
scripts/nxm-handler.sh
tests/test_smoke.sh
```

## Testing

```bash
make test
make lint
```

`make lint` uses ShellCheck when installed and always validates Python syntax and
YAML syntax when PyYAML is available.

## Lutris submission

1. Test `lutris/vortex.yml` on supported distributions.
2. Create a tagged GitHub release, for example `v0.1.0`.
3. Replace `main` raw URLs in `lutris/script-only.yml` with the immutable tag.
4. Submit only the contents of the `script:` section to the Vortex installer page
   on Lutris.

The full standalone YAML contains the root metadata needed by
`lutris -i ./lutris/vortex.yml`; Lutris' website expects the inner script only.

## License

MIT. Vortex itself is developed and distributed by Nexus Mods under its own
license. This repository does not redistribute Vortex binaries.

<!-- BEGIN OPENMODLINUX SKYRIM LINUX -->
## Skyrim SE and SKSE on Linux

OpenModLinux includes native Steam/Vortex hardlink mapping, hybrid-GPU-safe
Vortex launch settings, SKSE launch-option helpers, Engine Fixes preloader
installation, Microsoft Visual C++ prefix setup and SKSE plugin diagnostics.

See [docs/skyrim-skse-linux.md](docs/skyrim-skse-linux.md).
<!-- END OPENMODLINUX SKYRIM LINUX -->

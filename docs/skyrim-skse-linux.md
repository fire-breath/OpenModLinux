# Skyrim SE, SKSE and Vortex on Linux

OpenModLinux keeps Vortex, native Steam libraries and Proton prefixes aligned so
that mod deployment does not depend on fragile cross-filesystem links.

## Vortex storage layout

The Vortex prefix maps the native Steam installation as:

```text
C:\SteamLibrary -> ~/.local/share/Steam
```

Vortex userdata is stored at:

```text
C:\SteamLibrary\steamapps\vortex-userdata
```

Keep the Vortex staging template unchanged:

```text
{USERDATA}\{GAME}\mods
```

For Skyrim SE this resolves to:

```text
C:\SteamLibrary\steamapps\vortex-userdata\skyrimse\mods
```

Because staging and `Skyrim Special Edition/Data` are on the same Linux device,
Vortex Hardlink Deployment can create hardlinks without `EXDEV`.

Run the mapping tool after moving Steam or creating a new prefix:

```bash
scripts/configure-vortex-native-steam.sh "$HOME/Games/vortex-mod-manager"
```

## Vortex GLX startup

On hybrid Intel/NVIDIA systems, do not force NVIDIA PRIME for the Electron
interface. The Lutris template launches Vortex with software-rendered Electron
UI options and disables GameMode for this application:

```text
--disable-gpu
--disable-gpu-compositing
--disable-gpu-sandbox
--no-sandbox
--force-device-scale-factor=1
```

The maintenance tool also removes forced GPU variables from existing Lutris
Vortex entries:

```bash
scripts/fix-vortex-glx.sh
```

## Launch Skyrim through SKSE

Print the recommended Steam launch option:

```bash
scripts/skyrim-skse-launch-options.sh normal
```

Print a temporary diagnostic variant with `PROTON_LOG=1`:

```bash
scripts/skyrim-skse-launch-options.sh debug
```

The command replaces either `SkyrimSELauncher.exe` or `SkyrimSE.exe` with
`skse64_loader.exe` and keeps native overrides required by Engine Fixes and
modern Visual C++ SKSE plugins.

## Engine Fixes preloader

Download the matching Engine Fixes Preloader archive, then run:

```bash
scripts/install-engine-fixes-preloader.sh /path/to/archive.7z
```

The installer extracts `d3dx9_42.dll`, backs up an existing copy and places the
new DLL in the Skyrim game root.

## Microsoft Visual C++ runtime

Some new SKSE plugins require a complete native Microsoft Visual C++ 2015-2022
runtime. Distribution-packaged Protontricks can fail with new Steam Runtime and
WoW64 layouts, so OpenModLinux includes a direct installer:

```bash
scripts/install-steam-vcrun.sh 489830
```

It downloads Microsoft's x64 redistributable, runs it through Proton
Experimental, backs up the prefix registry and runtime DLLs, and configures
`native,builtin` overrides for `msvcp140` and `vcruntime140`.

Do not run this tool with `sudo`.

## SKSE plugin diagnostics

Generic diagnostic:

```bash
scripts/diagnose-skse-plugin.sh PluginBaseName
```

Isekai Hero shortcut:

```bash
scripts/diagnose-isekai-hero.sh
```

The report includes game/SKSE files, imports, Address Library files, plugin
activation lists, SKSE logs, Proton exceptions and recent coredumps. It creates
a compressed report in the user's home directory.

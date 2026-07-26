# OpenModLinux 0.1.2 overlay

This overlay adds the Linux fixes developed during Vortex and Skyrim SE
troubleshooting:

- native Steam mapping and same-device Vortex userdata/staging;
- Vortex GLX/hybrid-GPU-safe launch options;
- SKSE Steam launch-option generator;
- safe Engine Fixes preloader installation;
- direct Microsoft Visual C++ runtime installation through Proton Experimental;
- generic SKSE plugin diagnostics and an Isekai Hero shortcut;
- documentation and smoke tests.

Use `apply_openmodlinux_v0.1.2_all_fixes.sh` to patch the existing repository.
The patcher creates a backup and a local Git commit. It does not push or tag.

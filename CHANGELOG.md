# Changelog

## 1.0 — 2026-09-05
First release.
- Profile script v8: moves the first-person rig and equipped weapon/tool meshes out of Starbreeze's TopPass (`SetRenderInTopPass(false)`), so arms, weapons, tools and reload/interaction animations render under UEVR.
- Installer downloads UEVR nightly-01143 (4ee5c6b) from praydog's official GitHub release, SHA-256 verified, and installs the profile with backup of any existing one.
- Launcher starts PAYDAY 3 through Steam and injects UEVR automatically.
- Tested on PAYDAY 3 3.8 (build 24964769), Oculus Rift S, Meta OpenXR runtime, full heists.

# Architecture

ThemePark2Native is one native Win64 executable built by one Visual Studio
project. It statically links the DOS compatibility engine; no emulator process,
runtime DLL, batch file, WSL environment, or secondary project is launched.

## Runtime flow

1. The Windows application validates or imports the player's CD data.
2. Native loading art covers all guest text modes.
3. The embedded engine starts `INTRO.EXE` and then `MAIN.EXE` directly.
4. Theme Park remains authoritative for simulation, rendering, scripts, saves,
   sound generation, and mouse interpretation.
5. The host presents completed frames with D3D11/CRT, submits audio through
   XAudio2, and maps Win32/XInput events into the original input interfaces.
6. When `MAIN.EXE` genuinely returns to DOS, the native window closes.

## Source and installation boundary

The repository contains host code, redistributable importer tools, shaders, and
the exact GPL corresponding source for its embedded engine. Original Theme Park
files appear only in a user's local `data` directory, which Git ignores.

`build-release.ps1` is the only supported assembly path. It builds with MSVC
and invokes `tools/Stage-Release.ps1`, which copies and hash-checks the complete
runtime. The first-run importer then reproduces all game-data changes from the
user's CD; the staged test directory is never an authoritative source.

## Branch boundary

Stable `main` preserves the original 4:3 framebuffer. The isolated
`widescreen-test` branch contains unfinished engine-level widening research.

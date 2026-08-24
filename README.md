# Theme Park Native

Theme Park Native is an unofficial Windows 11 modernization layer for the 1994
PC CD release of **Theme Park** by Bullfrog Productions. It starts the original
game directly in a native window while keeping its private DOS compatibility
layer, setup process, and emulator menu invisible.

No playable original game executable or asset library is included. On first
launch, select an ISO or BIN/CUE image made from a legally owned Theme Park CD.

## Current features

- One native x64 Windows executable built with Visual Studio and Direct3D 11.
- Direct first-run CD import; the obsolete DOS installer is never shown.
- Automatic SB16 sound-effects and AdLib music configuration at unity gain.
- Fixed period-correct CPU pacing; it never falls through to an unbounded
  modern CPU clock.
- Correct VGA pixel aspect plus support for Theme Park's 640x480 VESA mode.
- Edge-aware scaling, restrained sharpening, and a configurable CRT shader.
- Immediate absolute mouse tracking plus a verified compatibility patch for
  Theme Park's original VGA/VESA cursor-freeze bug.
- V-synchronized flip-model presentation and optional save states.

## Install

1. Extract the complete release to a writable directory.
2. Run `ThemePark2Native.exe`.
3. Select the `.iso` or `.cue` file belonging to your Theme Park PC CD.
4. Wait for validation and extraction; the game then starts directly.

Unlike mixed-mode CD games, this edition keeps music and effects in its own
`MUSIC*.DAT` and `SNDS*.DAT` files. A normal ISO therefore contains the complete
audio and no separate CD-track conversion is required.

## Controls

- Mouse: point and click exactly as in the original game.
- `Alt+Enter`: toggle fullscreen.
- `Ctrl+F10`: release captured mouse.
- `Ctrl+F5` / `Ctrl+F9`: save/load the quick state.
- Xbox right stick: pointer; `A` or right trigger: left click; `B` or left
  trigger: right click; D-pad: menu arrows; `X`: fireworks; `Y`: open park;
  Menu: pause; View: Escape.

## Build

Install Visual Studio 2022 with **Desktop development with C++**, then build
`ThemePark2Native.sln` as `Release | x64` or run:

```powershell
.\build-release.ps1
```

The project uses MSVC and the Windows SDK only—no WSL or MinGW. Authored code,
scripts, and shader modules remain below 300 lines per file.

## License

This project is licensed under [GPL-2.0-only](LICENSE) because its monolithic
executable embeds DOSBox Pure. Theme Park and all original game content belong
to their respective owners. This is an unofficial interoperability project.

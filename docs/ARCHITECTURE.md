# Architecture

## Goal and boundary

This is a hybrid native host. The original `H2PC.EXE` gameplay engine runs in an
embedded GPLv2 DOSBox Pure core; Windows owns the window, D3D11 presentation,
CRT post-processing, XAudio2 output, input policy, saves and installation.
Original files are runtime inputs and never enter the public source tree.

## Runtime flow

1. `main.cpp` creates `App`.
2. `App` creates the Win32 window and `Renderer`.
3. `game_install.cpp` checks for imported files.
4. If needed, the first-run wizard imports the owner's disc.
5. Validation checks representative headers, room count, and music files.
6. `EmulationCore` initializes the statically linked core and original executable.
7. Libretro callbacks deliver frames, audio and input across a narrow C ABI.
8. `engine_frame.cpp` validates gameplay state and reads a wider scene from the
   original engine's own backing surface; other video modes pass through 4:3.
9. A native clock advances `retro_run()` at the core-reported interval while
   D3D11 presents the latest completed image at the monitor refresh rate.
10. CRT processing runs on each swap-chain presentation.

## Module ownership

`App` owns application lifetime, raw mouse capture and Windows events.
`cursor_visibility.cpp` supplies an invisible client cursor without altering
Windows' display counter, then restores the arrow outside the game area.
`InputMapper` translates WASD and XInput without modifying the original EXE.

`Renderer` owns Direct3D COM objects. `renderer_device.cpp` handles the GPU and
window; `renderer_content.cpp` handles pixels entering the GPU. It retains the
previous/current completed textures for optional presentation interpolation.
`presentation_shader.h` documents the embedded edge-aware reconstruction and
contrast-limited sharpening pass that runs before external CRT processing.

`engine_frame.cpp` is the game-specific camera-presentation boundary. It reads
the symbol-verified 464x320 indexed backing surface and live VGA palette,
selects a 426-pixel horizontal window, and overlays the untouched 320-pixel HUD.
`engine_probe.cpp` is read-only diagnostics. The tiny bridge compiled into the
embedded core exposes guest memory, DOS load state, and palette; it is not a DLL.

`EmulationCore` owns DOSBox Pure's lifecycle and callback boundary. The core's
libretro entry points are linked into `ThemePark2Native.exe`; they are not loaded
from another binary. The bridge reports whether the active DOS PSP belongs to
`H2PC`; after the game has started, six consecutive non-H2PC simulation frames
mean it genuinely returned to DOS and the native host closes. Intro Escape
therefore remains a game input, while Pure's menu is never user-visible.
`AudioOutput`
queues interleaved PCM to XAudio2. Neither class knows Win32 window policy.

`game_install` owns paths, first-run import initiation, and shallow validation.
Detailed disc/RNC/FLAC work stays in the importer so startup remains small.

## Data flow

```text
Windows input -> InputMapper -> libretro -> original engine
                                      |          |
                              XAudio2 <- PCM   indexed backing surface
                                                     | + VGA palette
                                      4:3 fallback <-+-> 426x200 -> D3D11 -> CRT
                                      |
                         virtual CD <- CUE <- lossless FLAC
```

Future overhaul hooks may replace individual services, but original behavior
remains the compatibility baseline. The original engine is authoritative for
gameplay and simulation timing; the Windows host may become authoritative for
camera presentation and visual refresh frequency only. Interpolation data is
presentation-only, audio/CD remains simulation-timed, and save states contain
no interpolated values.

The refresh-separation baseline repeats completed frames. An opt-in whole-frame
blend uses only previous/current presentation textures and excludes the HUD; it
never feeds values back into DOS memory. Controller/pointer state is sampled on
every native presentation and consumed on the next core tick. A four-step
catch-up limit prevents debugger pauses or suspend from fast-forwarding play.

# Roadmap

## Stable `main`

`main` is the playable compatibility release. It provides the native Win64
window, D3D11 presentation, CRT processing, XAudio2 output, accurate mouse
capture, keyboard/XInput input, fullscreen transitions, save states, hidden DOS
startup, direct `INTRO.EXE` to `MAIN.EXE` sequencing, and first-run CD import.

The retail engine remains authoritative and renders its original 4:3 VGA or
VESA framebuffer. The importer applies only the reviewed VGA/VESA mouse-freeze
repair; it does not widen or otherwise rewrite the rendering engine.

## Stable hardening

- Complete low- and high-resolution play-through testing.
- Test audio-device loss and controller disconnect/reconnect.
- Expand automated release-boundary and clean-import checks.
- Replace remaining developer-oriented diagnostics with documented switches.

## Experimental `widescreen-test`

Genuine 16:9 requires changes inside `MAIN.EXE`: wider allocations, row
strides, clipping, culling, camera limits, UI composition, and pointer mapping.
That reverse-engineering work is preserved on `widescreen-test` and is not part
of the stable installer.

Before it may merge, both 320x200 and 640x480 modes must reveal additional map
geometry without stretching, corrupting fixed-layout screens, changing game
speed, or breaking mouse input. It also requires room-by-room compatibility
testing and a clean-CD reproduction test.

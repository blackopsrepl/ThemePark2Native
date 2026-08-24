# Porting notes

## Confirmed from the supplied PC CD-ROM release

- `H2PC.EXE` is an 843,294-byte 16-bit MS-DOS MZ executable, not a PE/Win32
  binary. There is no Windows renderer API to hook.
- The game renders a 320x200-era image. The supplied 640x400 screenshot is an
  exact 2x presentation; display correction to 4:3 therefore requires a 1.2
  vertical pixel-aspect correction.
- The disc is mixed mode: track 1 is MODE1/2352 data and tracks 2 through 9 are
  CD audio.
- The first-run importer preserves the original numeric CD routing and encodes
  BIN/CUE CD-DA sectors as 44.1 kHz, signed 16-bit stereo FLAC. This retail BIN
  stores samples little-endian; using big-endian produces valid but noisy,
  effectively incompressible audio.
- Major content classes are loose, per-room files. Custom file signatures are
  visible in `SPC`, `WPC`, and `APC` resources.
- `ALPLAY.ASM`, `SNDStartSFX`, and embedded SFX symbols identify the effects
  engine. An audible test plus an OPL2 key-on trace verifies the selected AdLib
  path. The exact 26-byte `SETUP.INF` layout is documented by the importer.
- The MZ image ends at byte 589,648. A Borland TDINFO v3 block follows it and
  retains 14,444 symbol records and source-level video names.
- `VidCurrWidth` and `VidCurrLen` report a 464x320 backing surface. The original
  `VidUpdateScreen` copies a 320-byte window from 512-byte-stride rows to VGA,
  using `VidCurrTLX/TLY`; the extra horizontal pixels are real engine output.

## Hybrid port sequence

1. **Original engine host** — embedded DOSBox Pure, direct `H2PC.EXE` boot and
   generated `SETUP.INF`. Implemented.
2. **Native services** — D3D11/CRT, XAudio2, raw mouse, keyboard/XInput policy,
   save states and lossless virtual CD. Implemented.
3. **Engine view hook** — symbol parser, guest-memory bridge, 426x200 scene and
   separate native HUD composition. Implemented; room audit remains.
4. **Compatibility hardening** — complete-game tests and override catalogue.
5. **Resource laboratory** — typed parsers and corpus tests for selective hooks.
6. **Enhancements** — object interpolation, accessibility,
   optional HD assets and documented fixes while retaining engine fallback.

The wider compositor does not change authoritative clipping, traversal, entity
activation, scripts, or collision. It reveals pixels already drawn into the
engine's larger surface. The room audit must still identify content that was
never intended to be visible and assign a 4:3 override where needed.

`SETUP.INF` stores the sound selection and music selection separately. The
verified host choices are pure AdLib effects and CD. The host mounts imported
data as `C:\`, so startup normalizes only the obsolete installation-path field
while retaining every retail hardware and control byte.

## Music routing

The compatibility boundary is the original CD track number. The untouched DOS
engine calls MSCDEX; the generated CUE maps tracks 2-9 to
`data/music/trackNN.flac`. No physical drive or retained disc image is needed.
## Widescreen policy

Gameplay uses a 426x200 window into the existing 464x320 engine surface. Menus,
cinematics, invalid modes, and future room overrides use aspect-correct 4:3.
Stretch remains diagnostic only. The HUD is copied at native width over the
wider scene, so neither UI nor game art is stretched.

## Ownership boundary

The project should consume user-supplied original data at runtime. It should
not contain original artwork, music, text, or reconstructed proprietary source.
Format findings are documented as behavioral facts. The host is GPLv2 because
it embeds DOSBox Pure; proprietary game assets remain user-supplied runtime data.

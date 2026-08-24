# Roadmap

## Completed foundation

Native Win64/D3D11 presentation, CRT integration, retail CD import, exact RNC
extraction, direct original-engine boot, XAudio2, verified SFX and lossless CD
audio, corrected mouse/fullscreen handling, modern keyboard/Xbox input, save
states, and one-project static MSVC integration.

## Compatibility hardening

Complete-game play-through testing, game-specific save-state UX, controller
tuning, audio-device recovery and automated captures.

## Engine hooks and resource laboratory

Document and test `BDP`, `SPC`, `WPC`, `TPC`, `APC`, `HPC`, `MPC`, and `PPC`.
Create palette, sprite, animation, room, text, and world inspectors. Scan the
entire corpus and reject malformed sizes or offsets safely.

## Selective scene reconstruction

Rebuild isometric composition, palette behavior, depth sorting, animation,
camera, and room transitions. Match reference scenes before wider cameras.

## True expanded 16:9 view — implementation complete, audit active

The retail TDINFO symbols revealed a 464x320 indexed backing surface and the
`VidUpdateScreen` 320-byte copy window. The native host now reads a centred
426x200 view directly from that surface and live VGA palette. It applies DOS
pixel aspect, translates pointer coordinates, and uses automatic 4:3 fallback
outside validated gameplay modes.

The control bar is an unstretched 320-pixel compositor layer. The remaining
milestone is an all-room audit for voids, hidden triggers, spoilers, scene
assumptions, and uninitialized tiles, followed by explicit per-room fallbacks.

## Higher presentation rates at original simulation speed

Native presents are now decoupled from `retro_run()` at the core-reported frame
interval: faster displays repeat the latest completed image, input is sampled
at presentation rate, and gameplay/audio/CD/save evolution occurs only on core
steps. The next reverse-engineering task is to measure Theme Park's internal
authoritative game tick rather than equating it with the 60 Hz VGA/core output.

An opt-in experimental whole-frame interpolator now blends completed scene
textures and excludes the HUD. The preferred deeper path still exposes
previous/current camera, actor, projectile, enemy, and object positions and
renders only interpolated visual positions. Interpolation state never enters
authoritative engine state or save states.

## Later overhaul

Add accessibility, optional HD packs, and documented bug/localization fixes
without altering the compatibility baseline. The original engine remains
authoritative for gameplay; the Windows host owns camera presentation and
visual refresh frequency.

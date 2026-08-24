# Development guide

## Rules

- Explain reasons, invariants, and original behavior—not obvious punctuation.
- Keep every code or script file below 300 lines.
- Split by responsibility before a module becomes difficult to scan.
- Treat warnings as errors.
- Never add game files, screenshots, music, or generated imports.
- Preserve original behavior behind compatibility interfaces; enhancements are
  optional policy layers.

## C++ orientation

Headers describe what a module offers; `.cpp` files explain how. `ComPtr<T>`
automatically releases Windows graphics objects. `std::filesystem::path` safely
represents paths. Windows calls returning `HRESULT` are checked with `FAILED`.

The window procedure is a callback invoked by Windows. It forwards events to
the renderer, emulation boundary and `InputMapper`; the rest of the application
uses ordinary C++ classes. Raw mouse input is relative and must be snapshotted
in `inputPoll`, because libretro may query one axis several times per frame.

## Verification checklist

1. Build `ThemePark2Native.sln` as Release x64 with Visual Studio 2022/MSVC;
   require zero warnings. This is the sole supported toolchain.
2. Every code/script file below 300 lines.
3. BIN/CUE import completes.
4. All 355 data hashes match the known corpus.
5. FLAC verifies tracks 2-9.
6. CRT shader compiles.
7. Test scale modes, resize and repeated fullscreen/window transitions.
8. Test mouse capture/release in both modes and disconnect an active controller.
9. Verify audible AdLib effects and CD tracks 2-9 independently. With
   `THEMEPARK_LOG`, a known effect must also produce an OPL2 key-on trace.
10. Search the public tree for assets and machine-specific paths.
11. Use `dumpbin /DEPENDENTS` to confirm the EXE has only Windows system DLLs;
    DOSBox Pure and the MSVC runtime are linked into the executable.

## Widescreen and refresh tests

The 426x200 compositor requires a room-by-room matrix covering exposed voids,
uninitialized tiles, hidden triggers, premature enemy activation, scripted
scenes, camera bounds, mouse hit-testing, and each 4:3 compatibility override.

High-refresh work must compare gameplay speed, script timing, combat, audio/CD
timing, and serialized states against the measured baseline. Test 60, 90, 120,
and 144 Hz presentation while simulation remains unchanged. Interpolation tests
must verify HUD exclusion and prove that saving/loading is frame-rate invariant.
Interpolation and waitable one-frame DXGI pacing are the sole presentation
path. Set `THEMEPARK_ENGINE_LOG` to an absolute file to record symbol-backed
camera state.

Run `tools/Inspect-HeimdallSymbols.ps1 -Executable <H2PC.EXE> -OutputCsv <file>`
to reproduce symbol addresses from a legally imported executable. Generated
CSV belongs in a work directory and must not be committed.

Third-party helper licenses live in `tools/licenses/` beside distributed tools.
The CRT shader is also code: its entry file assembles balanced, ordered modules,
each below the same limit. Do not join those modules into one monolithic effect.

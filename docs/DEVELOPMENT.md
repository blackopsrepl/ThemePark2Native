# Development guide

## Rules

- Build only with Visual Studio 2022/MSVC on Windows.
- Keep every authored code or script file below 300 lines.
- Comment reasons, original behavior, and safety checks in novice-readable text.
- Never commit imported game data, saves, logs, or generated build output.
- Make release changes in source/importer/staging code, never only in a test
  installation.
- Require a clean-CD import to reproduce the final staged runtime.

## Verification

1. Run `tools/Check-Repository.ps1`.
2. Build `ThemePark2Native.sln` as Release x64 with zero warnings.
3. Stage through `build-release.ps1 -RuntimeDirectory <path>`.
4. Import a clean supported CD image using the staged importer.
5. Verify low and high resolution, mouse capture, fullscreen round trips, SFX,
   music, keyboard, controller, save states, Escape, and game-exit shutdown.
6. Confirm the loading art hides all text-mode DOS/DOSBox/DOS4GW frames.
7. Confirm source/runtime hashes and that only Windows system DLLs are external.

## Branch policy

`main` retains the working 4:3 engine framebuffer. Experimental true widescreen
development belongs on `widescreen-test` until both engine modes and a complete
gameplay audit pass. Do not test an experimental binary against stable imported
data without re-importing, because the experimental importer changes MAIN.EXE.

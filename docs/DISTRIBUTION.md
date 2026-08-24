# Distribution layout

The source repository and installed game are deliberately different trees.
This avoids publishing copyrighted game data while keeping installation simple.

The repository is authoritative. `D:\Games\Theme Park` is only a disposable
verification install: no release fix may be made there by hand. Every binary,
configuration, shader, helper, executable patch, and imported-file transform
must come from this repository and be reproduced by a clean first-run import.

## Public repository

The Git repository contains source, documentation, build files, the first-run
importer, redistributable dependencies, and a few documentation screenshots.
It must not contain `data/`, `music/`, `music-manifest.json`, build output,
symbols, logs, or game files usable by the executable.
`tools/Check-Repository.ps1` checks these boundaries.

## Installed game

The release directory is the self-contained player installation. It contains the
native executable, player README/controls, two documentation screenshots, CRT
runtime, widescreen policy, importer and helpers, plus the owner's locally
imported `data/` (including `data/music/`) and `music-manifest.json`. It contains
no C++ source, contributor documentation, solution/project files, or build
objects.

The importer writes relative to the native executable. Moving the installed
directory therefore keeps it working; no command file, registry value, mounted
disc, DOSBox configuration, or machine-specific source path is required.

## Release checklist

1. Build `Release | x64` and run `tools/Check-Repository.ps1`.
2. Run `tools/Stage-Release.ps1 -Destination <empty folder>`, or use
   `build-release.ps1 -RuntimeDirectory <folder>` to build and stage together.
3. Verify the staged folder contains the importer helpers, licenses, shaders,
   and exact corresponding DOSBox Pure source archive, but no `data/`.
4. Test first run from an empty install using a user-selected BIN/CUE image.
5. Confirm validation reports at least 100 rooms and 8/8 music tracks.
6. Confirm ReShade reports a successfully compiled CRT technique.

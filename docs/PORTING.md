# Porting notes

Theme Park's PC CD release contains DOS programs, not a native Windows
renderer. `INTRO.EXE` and the DOS/4GW `MAIN.EXE` therefore run inside the
statically linked compatibility engine while the application supplies native
Windows presentation, audio, input, window management, and storage.

The compatibility engine and host are one Visual Studio C++ executable. There
is no separately launched DOSBox program, batch file, Linux layer, WSL tool, or
MinGW dependency.

## User-owned data

The repository contains no game files. On first launch, the importer extracts
the supported PC CD image into `data`, creates the verified sound configuration,
and applies the narrowly reviewed VGA/VESA mouse-transition repair to the copied
`MAIN.EXE`. The selected image is never modified.

This release stores its music and effects in game data files rather than Red
Book tracks, so an ISO is sufficient. BIN/CUE and the supplied archival ZIP
layout remain accepted by the importer.

## Ownership boundary

The project is GPLv2 because it embeds DOSBox Pure. Corresponding source ships
beside the runtime. Original artwork, code, text, and audio remain supplied by
the player and are never committed to the public repository.

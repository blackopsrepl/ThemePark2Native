# Importing the original game

The public package contains no Theme Park game assets. On first launch, select
the supported 1994 PC CD image. ISO, BIN/CUE, and the supported archival ZIP
layout are accepted.

The wizard extracts into a temporary directory, verifies `MAIN.EXE`,
`INTRO.EXE`, representative graphics, music, and sound-effect data, and only
then copies the `GAME` directory into the installation's `data` directory. A
failed verification leaves the existing installation untouched.

The obsolete DOS installer is never run. The wizard writes `SNDSETUP.INF` for
the embedded SB16/AdLib-compatible hardware and applies one reviewed branch
correction to the copied `MAIN.EXE` that prevents the mouse freezing during
VGA/VESA transitions. It never changes the selected CD image.

Stable `main` performs no widescreen binary patch. Its import manifest records
that the original 4:3 framebuffer is retained. Switching from
`widescreen-test` back to `main` requires a fresh import because the test branch
uses a differently patched executable.

# CD import internals

The user runs only the main EXE. The first-run wizard asks for an original PC CD
image and never requires the DOS installer.

## Inputs

BIN/CUE is complete: CUE supplies track boundaries and BIN contains raw
2352-byte data and audio sectors. ISO is data-only: its 2048-byte filesystem
sectors cannot include Red Book audio.

## Data pipeline

For BIN/CUE, the importer removes each MODE1 sector's 16-byte header and
288-byte error-correction tail, retaining the 2048-byte ISO payload.

The data track contains `HEIM2.001`, a sequence of RNC ProPack method-1 blocks.
The first decompressed block is a table of little-endian sizes and null-terminated
DOS names. Remaining blocks form one continuous byte stream, which the importer
splits using that table into `data/`.

The obsolete installer is not run. The wizard writes the small `SETUP.INF`
configuration directly for the core's virtual `C:\` mount.

The retail corpus produces 355 files. Automated import testing compares every
hash with a known installed copy; the current result is zero mismatches.

## Audio pipeline

Each CUE audio track is sliced at exact sector boundaries. CD-DA is signed,
stereo, 16-bit PCM at 44.1 kHz; this BIN stores it little-endian. Tracks are
encoded with Xiph FLAC level 8 and verified by decoding. No resampling,
normalization, dithering, or lossy transform occurs. Eight tracks occupy about
108 MB instead of roughly 250 MB raw.

Music is stored below `data/music/`. The importer also writes
`data/THEMEPARK.CUE`, including a silent track 1, so original MSCDEX requests
for tracks 2-9 resolve without retaining or mounting the user's ISO/BIN.

## Failure behavior

Temporary files live below unique `import-work/<GUID>` directories. Explicit
errors cover missing BIN, missing audio, wrong disc, missing archive, corrupt RNC,
short data stream, encoder failure, and FLAC verification failure.

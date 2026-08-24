# Audio and music

This Theme Park PC release stores its music and sound effects in game data
files. It does not require Red Book CD tracks, retained disc mounting, or a
physical CD drive after import.

The importer writes `SNDSETUP.INF` for the sound hardware emulated inside the
monolithic runtime:

- Sound effects: Sound Blaster 16 at port 220, IRQ 5, DMA 1.
- Music: AdLib-compatible FM synthesis at port 388.

The original engine generates the authoritative audio stream. The Windows host
submits it through XAudio2 without changing gameplay timing or applying an
arbitrary volume multiplier. The CD image is needed only during first import.

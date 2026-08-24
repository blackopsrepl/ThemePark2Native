# Music routing

Track 1 of the mixed-mode CD is data; tracks 2-9 are Red Book audio. The DOS
engine requested numeric tracks through MSCDEX.

The importer preserves those numbers in a generated compatibility CUE:

```text
MSCDEX request -> virtual CD track 2..9 -> data/music/trackNN.flac -> XAudio2
```

`music-manifest.json` documents the mapping. `data/THEMEPARK.CUE` is the active
bridge used by the embedded core. A tiny silent track 1 preserves numbering;
tracks 2-9 remain exact lossless CD-DA extractions.

The original engine still issues start/stop/loop commands. DOSBox Pure decodes
the selected FLAC and mixes it with the emulated Sound Blaster, AdLib and PC
speaker paths; the host submits the combined stereo PCM stream asynchronously
to XAudio2. Both CD playback and OPL2 effects are audibly verified. The importer
selects the game's pure AdLib effects entry because its combined SB/AdLib setup
entry did not initialize effects reliably in this embedded environment. Every
mixer path remains at unity gain; silence is never hidden by artificial boost.

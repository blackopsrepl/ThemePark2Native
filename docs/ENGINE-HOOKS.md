# Engine hooks and expanded view

## Why this is not screen stretching

The retail executable keeps Borland Turbo Debugger information after its DOS
MZ image. `tools/Inspect-HeimdallSymbols.ps1` reads this table from the owner's
imported `H2PC.EXE`; no game binary or generated symbol CSV is distributed.

The useful globals include `VidCurrWidth`, `VidCurrLen`, `VidSegsPerBDLine`,
`VidCurrTLX/TLY`, camera maxima, HUD height, and extra-line clipping. Functions
include `VidUpdateScreen`, `VidScrollSet`, `VidSetTLXY`, and named sprite clip
branches. The observed gameplay layout is:

```text
indexed engine surface: 464 x 320 (512-byte row stride)
                            |
                  camera top-left X/Y
                            |
original VGA copy:       320 x 200
native scene copy:       426 x 200
```

`VidUpdateScreen` copies 320 indexed bytes per visible row from the larger
surface to VGA. The native host reads 426 bytes from the same rows and converts
them with the live VGA DAC palette. It does not stretch the completed VGA image.

## Runtime address model

DOS loads the MZ image 16 paragraphs after its Program Segment Prefix. TDINFO
segment-zero globals are offsets from that load segment. Relocated code symbols
confirm the relationship: the symbol segment for video code plus the load
segment equals the live CS observed inside that routine.

`heimdall_bridge.cpp` is compiled into the embedded DOSBox Pure sources. Four
small read-only functions expose guest RAM, PSP/segment state, and the current
VGA palette to authored host modules. This bridge is internal to the monolithic
EXE and introduces no DLL or end-user dependency.

## Validation and fallback

`engine_frame.cpp` refuses expansion unless all invariants agree:

- incoming mode is exactly 320x200 XRGB;
- backing surface is at least 426 pixels wide and 200 lines tall;
- row stride is the symbol-confirmed 32 paragraphs, or 512 bytes;
- original and expanded camera windows remain within backing bounds;
- HUD and extra-line values are plausible gameplay values;
- the current room is allowed by compatibility policy.

Failure returns the untouched original frame. Menus and cinematics therefore
stay aspect-correct 4:3 without image recognition or timing guesses.

## HUD and pointer

The wider scene is drawn for all rows first. The original 320-pixel control bar
is then overlaid at X=53. Normal gameplay uses its 32-line top bar; modes with a
positive `VidIBarHeight` preserve that many bottom lines instead. The UI remains
pixel-identical and newly visible room pixels continue at both sides.

For scene clicks, the host adds the difference between expanded and original
camera origins before normalizing to DOS pointer coordinates. For HUD clicks it
subtracts the 53-pixel compositor offset. The original input/script system
therefore remains authoritative.

## Room compatibility policy

`ThemePark-Widescreen.ini` has a global switch and a comma-separated list of
`ThisRoomFlagPtr` tokens. Setting `enabled=0` restores 4:3 everywhere. During
the audit, a problematic room's stable token is added to `fallbackRoomTokens`.
The policy records only addresses from the retail program layout, never room
art or proprietary data.

The remaining audit covers exposed voids, hidden triggers, premature enemy
visibility, scripted camera assumptions, and uninitialized tiles. Expansion
does not alter collision, triggers, culling, scripts, or simulation state.

## Presentation refresh

Windows samples input and presents at monitor refresh while the core advances
at its reported interval. `THEMEPARK_INTERPOLATION=1` enables an experimental
previous/current frame blend. Its alpha comes from measured completed-frame
arrival time; the HUD always selects the current texture. The textures, timer,
and alpha are renderer-only values and are excluded from save states.

Object-level interpolation remains the preferred later improvement. It must
read previous/current camera and entity positions, draw visual positions only,
and never write interpolated values into authoritative guest memory.

# Third-party components

These components are infrastructure, not Theme Park game assets.

| Component | Purpose | License information |
|---|---|---|
| ReShade runtime | Runs the CRT post-processing chain | `tools/licenses/ReShade-BSD-3-Clause.txt` |
| ReShade headers | Shared shader declarations | SPDX `CC0-1.0` in each file |
| CRT-Standalone | CRT effect used by the preset | Split mechanically into ordered modules |
| DOSBox Pure | Executes the original 16-bit DOS engine | GPLv2; exact source archive under `third_party/` |
| 7-Zip | Reads ISO-9660 files | `tools/licenses/7-Zip.txt` |
| FLAC | Encodes CD audio losslessly | `tools/licenses/FLAC-GPL.txt` |
| RNC ProPack tool | Decompresses the retail archive | `tools/licenses/RNC-ProPack.txt` |

`dxgi.dll` is the x64 ReShade runtime loaded beside the executable. The native
renderer remains ordinary Direct3D 11 code and works without it; only the CRT
post-processing is then unavailable.

Imported artwork, level data, original executable, text and music remain on the
owner's machine and are never part of the public repository.

## Project license

The complete Theme Park Native program is distributed under GPLv2. The root
`LICENSE` contains the controlling terms. DOSBox Pure is shipped as an embedded
libretro runtime; its pinned corresponding source and binary hashes are recorded
in `third_party/dosbox-pure/README.md`.

# ReShade presentation layer

The release ships a private 64-bit ReShade build as `dxgi.dll`. It is based on
official ReShade **6.7.3**, commit
`4a50d1eddace85734871d91792ff214f13f66c01`, under the BSD 3-Clause license in
`tools/licenses/ReShade-BSD-3-Clause.txt`.

`themepark-invisible-overlay.patch` makes the injector invisible to players.
It disables ReShade's startup/reload banner and adds two MSVC intrinsic-header
includes required by the Visual Studio 2022 toolchain used for this release.
It does not change shader behavior.

The checked-in `dxgi.dll` is the exact artifact staged by
`tools/Stage-Release.ps1`. Its SHA-256 is:

`76A4D595D450E0BEB46C2A3B53C4A95D7AB1812172FE17A37373F535E27A3165`

Run `Build-ReShade.ps1` from this directory to reproduce the DLL. The script
uses native Windows Git and Visual Studio only, checks out the exact commit,
applies the reviewed patch, and verifies the resulting hash before replacing
the repository artifact. End users never run this contributor-only script.

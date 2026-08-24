# DOSBox Pure corresponding source

Theme Park Native compiles DOSBox Pure 1.0 Preview 6 directly into its single
Windows executable. It is GPLv2 software and supplies the private x86/DOS
compatibility layer used to run the owner's original `MAIN.EXE`.

Upstream repository: <https://github.com/schellingb/dosbox-pure>

Exact upstream revision:
`a4a0bab7f8931433588f2fcad9045c85b277373d` (`1.0-preview6`).

The unmodified upstream source is preserved as
`dosbox-pure-1.0-preview6-source.tar.gz`. The complete corresponding source
actually compiled into this project—including Windows static-linking changes,
hidden-menu behavior, audio integration, and the tiny program-lifetime
bridge—is `dosbox-pure-msvc-source.tar.gz`.

`build-release.ps1` expands the corresponding-source archive into ignored build
storage before invoking the Visual Studio solution. No separate solution,
compiler, compatibility-core DLL, WSL environment, or MinGW toolchain is used.

Run `Get-FileHash` on either archive when auditing a release. The full GPLv2
text is available in the repository root and in `tools/licenses`.

# Engine hooks

## Stable boundary

The stable branch does not patch Theme Park's framebuffer, camera, clipping, or
world traversal. Its small embedded bridge exposes only what the Windows host
needs to operate cleanly:

- the internal `INTRO.EXE` to `MAIN.EXE` launch sequence;
- whether an original game program is running;
- whether the guest is in a genuine graphics mode;
- guest memory and VGA palette access retained for diagnostics.

Text-mode frames are withheld from presentation, which hides the DOS shell,
DOSBox messages, and DOS/4GW banner behind native loading artwork. The bridge
is compiled into the monolithic EXE and adds no DLL or end-user dependency.

## Widescreen research

`widescreen-test` preserves the reviewed LE-address mapping, import-time binary
patches, and experimental guest-memory bridge. It is intentionally isolated
because fixed 320x200 screens and the two page-flip buffers do not all use the
same layout.

Any future merge must validate exact original bytes before writing, fail closed
on another executable revision, retain the original simulation, and reproduce
every change from a clean user CD import.

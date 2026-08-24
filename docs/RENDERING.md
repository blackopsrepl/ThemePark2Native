# Rendering and widescreen policy

The VGA output is 320x200, but the engine draws into a 464x320 indexed backing
surface with 512-byte-stride rows. Its screen-update routine selects a 320-pixel
window using `VidCurrTLX/TLY`. The native compositor instead selects 426 pixels
from those same rows during validated gameplay. This is additional original
room output, not resampling of the VGA frame.

There is one scaling policy. Original modes preserve 4:3 at the full available
height. Expanded gameplay fills an exact 16:9 client area using every available
vertical pixel—1080, 1440, 2160, or the current resized-window height. Integer
and stretch modes do not exist, so no mode can silently select a smaller image.

## Reconstruction and sharpening

The D3D11 presentation shader reconstructs the low-resolution engine image at
the swap-chain resolution before CRT processing. Sharp-bilinear coordinates
keep source-pixel transitions one physical output pixel wide at any fractional
scale. A five-sample luminance test applies that reconstruction strongly at
real palette edges while retaining ordinary interpolation in smooth regions.

A restrained four-neighbour unsharp term then restores local definition. Its
result is clamped to the neighbourhood's existing colour range, preventing
ringing, white outlines, and crushed dark edges. The separate CRT sharpen knob
is zero because sharpening twice would create halos. The CRT stage remains
responsible for beam shape, scanlines, mask, phosphor, glow, and halation.

The 426x200 result becomes approximately 16:9 after the same 1.2 vertical pixel
aspect that makes 320x200 into 4:3. The compositor centres the original
320-pixel HUD over the wider room. Its side regions continue showing the room;
the UI itself is neither widened nor filtered.

The host validates backing dimensions, stride, camera bounds, HUD height, and
source mode each frame. If any invariant fails, it presents the original 4:3
frame. Pointer X is corrected by the difference between expanded and original
camera origins; HUD X is corrected by its 53-pixel centring offset.

The host intentionally does not widen authoritative collision or script bounds.
That prevents additional visible pixels from activating enemies or triggers.
A complete room audit is still required because authored data outside the old
viewport can contain voids or scene spoilers. Such rooms must receive an
explicit compatibility fallback, never fabricated geometry.

Presentation refresh is independent from simulation speed. The core keeps its
reported cadence while Windows presents at display cadence. D3D11 blends
previous/current completed scene textures using measured arrival time. Pixels
in the HUD region always come from the current frame. This state lives only in
Renderer and cannot enter a save state.

The flip-model swap chain exposes a Windows frame-latency waitable object and
permits only one queued frame. Each draw waits for that signal and presents at
sync interval one. This prevents queued bursts, reduces input latency, and keeps
60 Hz engine updates evenly paced on 90/120/144 Hz monitors without tearing.

Whole-frame blending is an experimental fallback because independently moving
objects can ghost. The deeper target remains symbol-backed previous/current
camera, actor, enemy, projectile, and object positions with visual-only
interpolation at original authoritative simulation speed.

The renderer first produces a clean frame. The CRT pass then models
reconstruction, mask, scanlines, beams, halation, glow, phosphor, sharpening and
grain. Game logic never depends on post-process pixels.

# Rendering

## Stable framebuffer policy

Theme Park can switch between its original low- and high-resolution modes. The
embedded engine reports each completed frame and its real dimensions to the
Windows host. `main` preserves that framebuffer unchanged and presents it at
the largest aspect-correct 4:3 size that fits the client area.

Black side bars on a widescreen monitor are intentional. They prevent the map,
icons, text, and mouse coordinate system from being stretched. Resizing and
fullscreen use the complete available height whenever the 4:3 image still fits.

## Native presentation

The D3D11 renderer reconstructs the low-resolution image at swap-chain
resolution, applies restrained sharpening, then runs the CRT shader. These are
presentation operations only: game logic, saves, collision, timing, and input
never depend on post-process pixels.

The flip-model swap chain uses synchronized presentation and a one-frame queue
to avoid tearing and excessive latency. Windows may refresh more frequently
than the engine, but the original simulation and audio cadence remain
authoritative.

## Experimental wider view

True 16:9 cannot be created by scaling the 4:3 callback. It requires the engine
to render additional columns. That unfinished binary-patch work lives only on
`widescreen-test`; stable `main` contains no engine-framebuffer interception.

#include "ReShade.fxh"

/*
    CRT-Standalone.fx
    Self-contained CRT shader. Features:
    - Pre-blur (H+V) before mask/scanlines, matching Guest Advanced SIZEH/SIZEV
    - Aperture grille mask (resolution-aware, anti-aliased)
    - Megatron cubic Bezier per-channel beam
    - Beam spot size modulation
    - Gamma-correct scanlines
    - Megatron Bezier brightness/contrast/saturation (Yxy space)
    - Brightboost (dark/bright split)
    - Phosphor glow (luminance-weighted, post-scanline)
    - Film grain (Marty METEOR digital sensor noise)

    Preprocessor toggles (zero runtime cost when disabled):
      ENABLE_GAMMA_CORRECT   1/0  (default 1)
      ENABLE_BEAM_MODULATION 1/0  (default 1)
      ENABLE_MASK            1/0  (default 1)
*/

// ============================================================
// Preprocessor toggles
// Signal chain order: Pre-Blur -> Mask -> Scanlines -> Gamma ->
// Brightness -> Halation -> Convergence -> Vignette -> Edge Blur ->
// Film Grain -> Anti Burn-In
// ============================================================

// Pre-Blur
#ifndef ENABLE_PREBLUR
    #define ENABLE_PREBLUR 1
#endif

// Mask
#ifndef ENABLE_MASK
    #define ENABLE_MASK 1
#endif

// Scanlines
#ifndef ENABLE_GAMMA_CORRECT
    #define ENABLE_GAMMA_CORRECT 1
#endif
#ifndef ENABLE_BEAM_MODULATION
    #define ENABLE_BEAM_MODULATION 1
#endif

// Glow loop caps -- compiler unrolls fixed-count loops, ~20-30% faster than dynamic
// Set to match your maximum UI slider values
#ifndef GLOW_H_MAX_RADIUS
    #define GLOW_H_MAX_RADIUS 16
#endif
#ifndef GLOW_V_MAX_RADIUS
    #define GLOW_V_MAX_RADIUS 8
#endif

// Halation
#ifndef ENABLE_HALATION
    #define ENABLE_HALATION 1
#endif
// Halation resolution: 4=quarter res (cheapest), 2=half res, 1=full res
#ifndef HALATION_RESOLUTION
    #define HALATION_RESOLUTION 4
#endif

// Pre-blur resolution divisor.
// 1 = full resolution (default). Some games benefit from keeping this at 1
// as the preblur acts as a mild AA pass when run at native resolution.
// 2 = half resolution (cheaper but visible quality loss on fine detail).
#ifndef PREBLUR_RESOLUTION
    #define PREBLUR_RESOLUTION 1
#endif

// Glow blur resolution divisor. Glow is a wide soft effect -- running at
// reduced resolution is perceptually indistinguishable and saves significantly.
// 1 = full resolution. 2 = half (recommended). 4 = quarter.
//
// NOTE: Some games (e.g. Cuphead) may show a ghost double-image or mini-screen
// artefact when GLOW_RESOLUTION > 1. This is a game-specific interaction with
// how the glow texture is composited. If you see this, set GLOW_RESOLUTION=1.
#ifndef GLOW_RESOLUTION
    #define GLOW_RESOLUTION 2
#endif

// Edge Feedback: cross-frame CRT edge and peripheral enhancement.
// Samples previous frame backbuffer as neighbour reference, amplifying
// differences caused by CRT processing (mask, scanlines, vignette, geometry).
// Most effective with ENABLE_GEOMETRY=1. 1 = enabled, 0 = disabled (default)
#ifndef ENABLE_EDGE_FEEDBACK
    #define ENABLE_EDGE_FEEDBACK 0
#endif

// Noise floor: faint fixed-pattern thermal noise on dark areas.
// Simulates CRT electronics thermal noise, distinct from signal-dependent grain.
// 1 = enabled, 0 = disabled (default)
#ifndef ENABLE_NOISE_FLOOR
    #define ENABLE_NOISE_FLOOR 0
#endif

// Tube diffuse: ambient glow from screen phosphors scattering through the glass.
// 1 = enabled, 0 = disabled (default)
#ifndef ENABLE_TUBE_DIFFUSE
    #define ENABLE_TUBE_DIFFUSE 0
#endif

// Composite video simulation: Y/C separation with independent luma/chroma bandwidth.
// 1 = enabled, 0 = disabled (default)
#ifndef ENABLE_COMPOSITE
    #define ENABLE_COMPOSITE 0
#endif

// Screen reflection: faint blurred self-reflection at screen edges.
// Simulates light bouncing between the thick CRT glass and the tube.
// 1 = enabled, 0 = disabled (default)
#ifndef ENABLE_SCREEN_REFLECT
    #define ENABLE_SCREEN_REFLECT 0
#endif

// Tube diffuse: ambient phosphor scatter glow through the CRT glass.
// 1 = enabled, 0 = disabled (default)
// Interference: wiggle, rolling scanlines, hum bars, ghosting, accumulation.
// All are signal-level effects applied as a post-process on the final image.
// Simulates RF/magnetic interference on a CRT signal.
// 1 = enabled, 0 = disabled (default)
#ifndef ENABLE_INTERFERENCE
    #define ENABLE_INTERFERENCE 0
#endif

// Scanline reference height for resolution-independent scanline width.
// When set, crt_scanline_width is automatically scaled so scanlines look
// identical regardless of the game's render resolution.
//
// Set this to your display's native vertical resolution:
//   4K display:  SCANLINE_REFERENCE_HEIGHT = 2160
//   5K display:  SCANLINE_REFERENCE_HEIGHT = 2880
//   1440p:       SCANLINE_REFERENCE_HEIGHT = 1440
//   1080p:       SCANLINE_REFERENCE_HEIGHT = 1080
//
// 0 = disabled (default). Existing behaviour -- scanline width is in raw
//     pixels at render resolution. Existing presets are unaffected.
#ifndef SCANLINE_REFERENCE_HEIGHT
    #define SCANLINE_REFERENCE_HEIGHT 0
#endif

// Lightweight barrel/pincushion warp pass.
// A cheap post-process UV distortion applied to the final image.
// Only active when ENABLE_GEOMETRY=0 -- use full geometry for accurate warp.
// 1 = enabled, 0 = disabled (default).
#ifndef ENABLE_LIGHT_WARP
    #define ENABLE_LIGHT_WARP 0
#endif

// Interlaced scanline phase pass.
// Offsets the scanline grid by half a line every other frame, simulating
// real CRT interlaced mode. Most visible at high framerates with BFI.
// 1 = enabled, 0 = disabled (default).
#ifndef ENABLE_INTERLACE
    #define ENABLE_INTERLACE 0
#endif

// Corner rounding / bezel pass.
// Applies a rounded screen mask with optional edge darkening.
// 1 = enabled, 0 = disabled (default).
#ifndef ENABLE_CORNER_ROUND
    #define ENABLE_CORNER_ROUND 0
#endif


// Edge Blur
#ifndef ENABLE_EDGE_BLUR
    #define ENABLE_EDGE_BLUR 1
#endif

// Chromatic aberration (radial colour fringing)
#ifndef ENABLE_CA
    #define ENABLE_CA 1
#endif

// Convergence error simulation (per-channel vertical offset)
#ifndef ENABLE_CONVERGENCE
    #define ENABLE_CONVERGENCE 1
#endif

// Vignette (edge darkening)
#ifndef ENABLE_VIGNETTE
    #define ENABLE_VIGNETTE 1
#endif

// Film grain
#ifndef ENABLE_GRAIN
    #define ENABLE_GRAIN 1
#endif
// Post-scanline vertical softening (fixes scanline-edge aliasing on curved geometry)
#ifndef ENABLE_SCANLINE_SOFTEN
    #define ENABLE_SCANLINE_SOFTEN 1
#endif
// Contrast-adaptive sharpening (restores detail softened by pre-blur/scanlines)
#ifndef ENABLE_SHARPEN
    #define ENABLE_SHARPEN 1
#endif

// Motion-adaptive sharpening: uses frame difference between current and previous
// frame to modulate CAS sharpening strength -- stronger in moving regions,
// lighter in static areas. Complements BFI by counteracting sample-and-hold
// blurring on moving objects. Off by default; enable only alongside ENABLE_DECAY.
#ifndef ENABLE_MOTION_SHARPEN
    #define ENABLE_MOTION_SHARPEN 0
#endif

// Reconstruction filter for Pre-Blur passes and geometry warp sampling.
// Used when sampling the backbuffer at non-integer (warped) positions.
// Has no effect on halation/glow blur kernels -- those stay Gaussian.
//
// PREBLUR_FILTER:
//   0 = Lanczos2  (4x4=16 taps, default). Good sharpness, minimal ringing.
//   1 = Lanczos3  (6x6=36 taps). Sharper, ~2x cost. Best for geometry warp.
//   2 = Catmull-Rom (4x4=16 taps). Bicubic spline. Slightly crisper than
//       Lanczos2 on high-contrast edges (scanlines, mask), less overshoot.
//       Same cost as Lanczos2. Good alternative for geometry.
#ifndef PREBLUR_FILTER
    #define PREBLUR_FILTER 0
#endif

// Kept for backwards compatibility -- PREBLUR_FILTER=1 is equivalent
#ifndef PREBLUR_LANCZOS_TAPS
    #define PREBLUR_LANCZOS_TAPS 2
#endif
// Phosphor persistence simulation (within-frame asymmetric vertical blur)
#ifndef ENABLE_PERSISTENCE
    #define ENABLE_PERSISTENCE 1
#endif

// Fibonacci-weighted exponential phosphor decay (BFI-style motion clarity)
// Based on CRT Dusha by Maxim Lapounov (MIT)
// Requires high framerate (120fps+) for best results -- visible flicker at 60fps
// 0 = disabled (default), 1 = enabled
#ifndef ENABLE_DECAY
    #define ENABLE_DECAY 0
#endif

// Blur Busters spatial overlap-integral mode (Variable MPRT with Tube Position
// simulation, 240Hz+ only). Requires two extra full-resolution history textures
// (raw + prev2) written every frame -- significant bandwidth. Disabled by
// default: standard BFI, Fibonacci decay, dark blend, and motion sharpen all
// work without it. Enable only if you use Decay Method = Variable MPRT with
// Tube Position on.
#ifndef DECAY_BB_INTEGRAL
    #define DECAY_BB_INTEGRAL 0
#endif

// Anti Burn-In
#ifndef ENABLE_BURNIN_PHASE
    #define ENABLE_BURNIN_PHASE 1
#endif
#ifndef ENABLE_BURNIN_ORBIT
    #define ENABLE_BURNIN_ORBIT 1
#endif

// Pipeline selection -- controls Soop sandwich integration
// 0 = No Soop (default): signal passes through unmodified at boundaries
// 1 = Soop scRGB: Reinhard compression at start, InvReinhard at end
// 2 = Soop HDR10: PQ decode + Reinhard at start, InvReinhard + PQ encode at end
#ifndef PIPELINE
    #define PIPELINE 0
#endif

// Frame generation phase offset.
// With DLSS FG, FRAMECOUNT increments for both real and generated frames.
// With 2-frame BFI the cycle already alternates correctly -- real frames land
// on one parity, generated frames on the other. If real frames land on the
// dark phase instead of the lit phase, set this to 1 to flip.
// 0 = default, 1 = flip phase by one frame.
// LSFG / Nvidia Smooth Motion: leave at 0, they run outside ReShade.
#ifndef FRAMEGEN_PHASE_OFFSET
    #define FRAMEGEN_PHASE_OFFSET 0
#endif

// Expected frame period in milliseconds for spike detection.
// Set to match your target refresh rate: 8.33=120Hz, 6.94=144Hz, 6.06=165Hz
#ifndef CRT_FRAMETIME_EXPECTED
    #define CRT_FRAMETIME_EXPECTED 8.33
#endif

// Linear HDR input: controls BCS path, independent of PIPELINE setting
// 0 = XYZ/Yxy path (perceptually correct, works for Soop sandwich and SDR)
// 1 = linear RGB path (for raw scRGB without any Soop compression)
#ifndef LINEAR_HDR_INPUT
    #define LINEAR_HDR_INPUT 0
#endif


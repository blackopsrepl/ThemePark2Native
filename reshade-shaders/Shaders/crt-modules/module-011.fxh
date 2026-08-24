// BCS gamut handling for XYZ/Yxy path (LINEAR_HDR_INPUT=0):
// 0 = soft gamut compression (default)
// 1 = hard clamp to [0,1]
#ifndef BCS_GAMUT_CLAMP
    #define BCS_GAMUT_CLAMP 0
#endif

// Gamut expansion: expands Rec.709 chrominance toward Rec.2020 within the
// existing HDR container. Luminance is already correct HDR -- only the colour
// primaries are constrained to Rec.709. Runs after SoopAfter.
// Pipeline 0: sRGB 0-1 Rec.709 -- expand, stays 0-1
// Pipeline 1: scRGB linear Rec.709 -- expand directly in linear, HDR preserved
// Pipeline 2: PQ Rec.2020 container -- decode PQ, expand, re-encode PQ
#ifndef ENABLE_GAMUT_EXPAND
    #define ENABLE_GAMUT_EXPAND 0
#endif

// Scanline rotated-grid supersampling (RGSS 4x): anti-aliases the diagonal
// staircase caused by content-modulated beam width interacting with discrete
// scanline rows. Evaluates the beam envelope at 4 rotated-grid subpixel
// positions and averages. Cost: 4 extra source taps + 4x beam evaluation
// (cheap on the default erf path, heavier with beam shape != 2).
#ifndef ENABLE_SCANLINE_SS
    #define ENABLE_SCANLINE_SS 0
#endif

// Horizontal beam reconstruction -- analytic generalized-Gaussian integral of
// the electron spot along the horizontal axis, the complement to the vertical
// scanline beam. Unlike Beam Horizontal Bloom (a luma-gated cosmetic smear),
// this reconstructs the true horizontal beam profile for ALL content, so thin
// bright vertical lines get a physically correct footprint instead of a hard
// bilinear edge. Cost: HBEAM_TAPS source fetches per pixel.
#ifndef ENABLE_BEAM_H
    #define ENABLE_BEAM_H 0
#endif
// Horizontal beam tap count (each side). 2 = 5-tap, 3 = 7-tap. 2 is plenty
// for typical spot sizes; raise only for very wide horizontal sigma.
#ifndef HBEAM_TAPS
    #define HBEAM_TAPS 2
#endif



// Phosphor colour profile correction
// 0 = disabled (passthrough, default)
// 1 = enabled (apply CRT profile + display gamut matrices)
#ifndef ENABLE_PHOSPHOR
    #define ENABLE_PHOSPHOR 1
#endif

// Screen geometry (barrel distortion) -- final pass UV warp
// 0 = disabled (flat, default)
// 1 = enabled
#ifndef ENABLE_GEOMETRY
    #define ENABLE_GEOMETRY 0
#endif

// Peak brightness of your display in nits, used when LINEAR_HDR_INPUT=1.
// Only affects BCS operations -- passthrough is unaffected when BCS is at zero.
// Sony A95L 77" = 1400 nits. Set to your display's actual peak.
// Internally converted to scRGB units (nits / 80).
#ifndef LINEAR_HDR_PEAK_NITS
    #define LINEAR_HDR_PEAK_NITS 1400
#endif

// System uniforms -- always present regardless of feature flags
uniform uint  FRAMECOUNT    < source = "framecount"; >;
uniform float CRT_TIMER     < source = "timer"; >;       // milliseconds since start
uniform float CRT_FRAMETIME < source = "frametime"; >;   // actual ms elapsed this frame

// ============================================================
// Uniforms -- Pre-blur (equivalent to Guest SIZEH/SIZEV/SIGMA)
// ============================================================

#if ENABLE_PREBLUR
uniform float crt_preblur_h_sigma <
    ui_type = "drag"; ui_label = "Pre-Blur Horizontal Sigma";
    ui_category = "Pre-Blur";
    ui_tooltip = "Gaussian sigma for horizontal pre-blur applied before mask and scanlines.\nEquivalent to Guest Advanced SIGMA_H. Blends pixels horizontally before CRT processing.\n0.0 = disabled at runtime. Set ENABLE_PREBLUR=0 in preprocessor to remove passes entirely.";
    ui_min = 0.0; ui_max = 6.0; ui_step = 0.05;
> = 0.0;

uniform float crt_preblur_h_radius <
    ui_type = "drag"; ui_label = "Pre-Blur Horizontal Radius";
    ui_category = "Pre-Blur";
    ui_tooltip = "Tap radius for horizontal pre-blur. Equivalent to Guest SIZEH.\nHigher = wider blend but more expensive.";
    ui_min = 1.0; ui_max = 32.0; ui_step = 1.0;
> = 6.0;

uniform float crt_preblur_v_sigma <
    ui_type = "drag"; ui_label = "Pre-Blur Vertical Sigma";
    ui_category = "Pre-Blur";
    ui_tooltip = "Gaussian sigma for vertical pre-blur. Equivalent to Guest SIGMA_V.\n0.0 = disabled.";
    ui_min = 0.0; ui_max = 6.0; ui_step = 0.05;
> = 0.0;

uniform float crt_preblur_v_radius <
    ui_type = "drag"; ui_label = "Pre-Blur Vertical Radius";
    ui_category = "Pre-Blur";
    ui_tooltip = "Tap radius for vertical pre-blur. Equivalent to Guest SIZEV.";
    ui_min = 1.0; ui_max = 16.0; ui_step = 1.0;
> = 6.0;

uniform bool crt_preblur_luma_only <
    ui_type     = "input"; ui_label = "Luma-Only Blur";
    ui_category = "Pre-Blur";
    ui_tooltip  = "Blur only the luma (Y) channel -- chroma passes through unblurred.\n"
                  "Reduces shimmer from fine texture aliasing against scanlines\n"
                  "without softening colours or losing colour saturation.\n"
                  "Works with both H and V sigma independently.\n"
                  "Recommended for temporal shimmer on detailed textures (gravel, fabric).\n"
                  "Default on: luma-only is strictly better than full RGB blur for preblur.";
> = true;

uniform float crt_preblur_bilateral <
    ui_type     = "drag"; ui_label = "Edge Preservation (Bilateral)";
    ui_category = "Pre-Blur";
    ui_tooltip  = "Bilateral filter strength: preserves edges while smoothing flat areas.\n"
                  "Range weight uses a fixed luma threshold (0.1) -- samples differing\n"
                  "by more than this from the centre pixel are progressively excluded.\n"
                  "This value blends between pure Gaussian (0.0) and full bilateral (1.0).\n"
                  "\n"
                  "0.0 = disabled, standard Gaussian blur (default).\n"
                  "0.3-0.5 = gentle edge preservation.\n"
                  "0.7-1.0 = strong edge preservation, only flat areas blurred.\n"
                  "\n"
                  "Combines with Luma-Only for most accurate edge detection.\n"
                  "Cost: ~2x Gaussian at same radius.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 0.0;

#endif // ENABLE_PREBLUR

// ============================================================
// Uniforms -- Composite Video
// ============================================================

#if ENABLE_COMPOSITE
uniform float crt_composite_chroma_blur <
    ui_type = "drag"; ui_label = "Chroma Blur Width";
    ui_category = "Composite Video";
    ui_tooltip = "Horizontal blur applied to colour channels independently of luma.\n"
                 "Models NTSC/PAL reduced chroma bandwidth (~1.5MHz vs 4MHz luma).\n"
                 "Gives soft-colours-sharp-edges composite look.\n"
                 "At 4K: 1.0 = ~2px blur. 3.0 = ~6px. 5.0 = ~10px colour bleed.\n"
                 "0.0 = disabled. 1.0-2.0 = authentic. 4.0+ = heavy RF degradation.";
    ui_min = 0.0; ui_max = 8.0; ui_step = 0.25;
> = 0.0;

uniform float crt_composite_chroma_phase <
    ui_type = "drag"; ui_label = "Chroma Phase Offset";
    ui_category = "Composite Video";
    ui_tooltip = "Horizontal offset of the chroma channels relative to luma.\n"
                 "On real composite video the colour signal could arrive slightly\n"
                 "delayed, causing a visible colour fringe offset from the edges.\n"
                 "0.0 = no offset (default). Positive = colour shifts right.";
    ui_min = -3.0; ui_max = 3.0; ui_step = 0.1;
> = 0.0;

uniform float crt_composite_luma_sharpen <
    ui_type = "drag"; ui_label = "Luma Sharpness Boost";
    ui_category = "Composite Video";
    ui_tooltip = "Compensates for the overall signal softness by boosting luma\n"
                 "edge contrast. Combined with chroma blur gives the authentic\n"
                 "composite look: crisp edges with colour bleed.\n"
                 "0.0 = disabled. 0.1-0.3 = subtle. 0.5+ = strong.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;
#endif // ENABLE_COMPOSITE

// ============================================================
// Uniforms -- Post-Scanline Softening
// ============================================================

#if ENABLE_SCANLINE_SOFTEN
uniform float crt_soften_strength <
    ui_type = "drag"; ui_label = "Scanline Soften Strength";
    ui_category = "Post-Scanline Softening";
    ui_tooltip = "Subtle vertical gaussian applied after scanlines to smooth\n"
                 "staircase aliasing where curved geometry crosses scanline gaps.\n"
                 "Keep low -- 0.3-0.6 is enough. Higher loses scanline definition.\n"
                 "Set ENABLE_SCANLINE_SOFTEN=0 to remove pass entirely.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.4;
#endif

// ============================================================
// Uniforms -- Sharpening
// ============================================================

#if ENABLE_SHARPEN
uniform float crt_sharpen_strength <
    ui_type = "drag"; ui_label = "Sharpen Strength";
    ui_category = "Sharpening";
    ui_tooltip = "Contrast-adaptive sharpening to restore edge detail softened\n"
                 "by pre-blur and scanlines. Sharpens edges, not noise.\n"
                 "0.3-0.5 = subtle, 0.8-1.0 = strong.\n"
                 "Set ENABLE_SHARPEN=0 to remove pass entirely.";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 0.0;

uniform float crt_sharpen_clamp <
    ui_type = "drag"; ui_label = "Sharpen Clamp";
    ui_category = "Sharpening";
    ui_tooltip = "Maximum sharpening per pixel. Prevents over-sharpening on fine detail.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.05;
#endif

#if ENABLE_MOTION_SHARPEN
uniform float crt_msharpen_strength <
    ui_type = "drag"; ui_label = "Motion Sharpen Strength";
    ui_category = "Motion Sharpening";
    ui_tooltip = "Overall strength of the motion-adaptive sharpening pass.\n"
                 "Applied on top of the standard CAS sharpening.\n"
                 "Modulated per-pixel by motion magnitude -- static areas\n"
                 "receive little or no sharpening, moving areas receive more.\n"
                 "0.0 = disabled. 0.3-0.5 = subtle. 1.0 = strong.\n"
                 "Best used with BFI enabled (ENABLE_DECAY=1).";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_msharpen_motion_threshold <
    ui_type = "drag"; ui_label = "Motion Threshold";
    ui_category = "Motion Sharpening";
    ui_tooltip = "Minimum frame-to-frame luma difference to be considered motion.\n"
                 "Below this threshold a pixel is treated as static and receives\n"
                 "no additional sharpening. Prevents noise from triggering sharpening\n"
                 "on visually stable areas.\n"
                 "0.01 = very sensitive (catches subtle motion).\n"
                 "0.05 = moderate (ignores noise, catches clear motion).\n"
                 "0.10 = only sharp on fast or high-contrast motion.";
    ui_min = 0.005; ui_max = 0.2; ui_step = 0.005;
> = 0.03;

uniform float crt_msharpen_clamp <
    ui_type = "drag"; ui_label = "Motion Sharpen Clamp";
    ui_category = "Motion Sharpening";
    ui_tooltip = "Limits maximum sharpening weight to prevent haloing on hard edges.\n"
                 "Lower = more conservative, less risk of overshoot.\n"
                 "Matches the role of Sharpen Clamp in the main CAS pass.";
    ui_min = 0.01; ui_max = 0.5; ui_step = 0.01;
> = 0.1;
#endif

// ============================================================
// Uniforms -- Phosphor Persistence
// ============================================================


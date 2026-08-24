> = 0.9;
uniform float crt_b_scanline_attack <
    ui_type = "drag"; ui_label = "Blue Scanline Attack";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_spot_size <
    ui_type = "drag"; ui_label = "Spot Size / Overbrightness";
    ui_category = "Scanlines";
    ui_tooltip = "On real CRTs, peak white caused the electron beam spot to\n"
                 "physically spread, brightening the scanline centre and making\n"
                 "bright pixels appear slightly larger than dark ones.\n"
                 "Luminance-dependent: only active above ~70% brightness.\n"
                 "0.0 = disabled (default). 0.1-0.3 = subtle organic bloom.\n"
                 "0.5+ = strong overbrightness on highlights.";
    ui_min = 0.0; ui_max = 0.5; ui_step = 0.01;
> = 0.0;

uniform float crt_beam_h_bloom <
    ui_type = "drag"; ui_label = "Beam Horizontal Bloom";
    ui_category = "Scanlines";
    ui_tooltip = "Simulates electron beam horizontal spreading on bright scanlines.\n"
                 "On real CRTs, very bright content causes space charge effects that\n"
                 "widen the beam horizontally as well as vertically -- saturated whites\n"
                 "appear slightly smeared sideways, softening hard horizontal edges.\n"
                 "\n"
                 "0.0 = disabled (default).\n"
                 "0.3-0.5 = subtle bloom on bright elements only.\n"
                 "1.0 = strong horizontal softening on anything above threshold.\n"
                 "\n"
                 "Only applies to pixels above ~80% luma -- darker areas unaffected.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 0.0;

#if ENABLE_BEAM_H
uniform float crt_beam_h_sigma <
    ui_type = "drag"; ui_label = "Horizontal Beam Width";
    ui_category = "Scanlines";
    ui_tooltip = "Width of the horizontal electron spot, as a fraction of one\n"
                 "source pixel. This reconstructs the true horizontal beam\n"
                 "profile (analytic generalized-Gaussian integral) for all\n"
                 "content -- the complement to the vertical scanline beam.\n"
                 "\n"
                 "Unlike Beam Horizontal Bloom (a bright-only cosmetic smear),\n"
                 "this shapes every pixel: thin bright vertical lines bloom\n"
                 "correctly and hard horizontal transitions gain a natural\n"
                 "spot footprint instead of a bilinear edge.\n"
                 "\n"
                 "0.3-0.4 = tight focused beam (sharp, subtle).\n"
                 "0.5-0.7 = typical consumer CRT spot.\n"
                 "0.8-1.2 = soft/defocused beam.\n"
                 "Uses the same Beam Shape exponent as the vertical scanline.";
    ui_min = 0.2; ui_max = 1.5; ui_step = 0.05;
> = 0.5;

uniform float crt_beam_h_strength <
    ui_type = "drag"; ui_label = "Horizontal Beam Amount";
    ui_category = "Scanlines";
    ui_tooltip = "Blend between the original sharp source and the horizontally\n"
                 "reconstructed beam. 1.0 = full reconstruction.\n"
                 "0.0 = off (bypass, no cost saved -- use ENABLE_BEAM_H=0 for that).";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 1.0;
#endif

uniform float crt_scanline_roll_strength <
    ui_type = "drag"; ui_label = "Scanline Row Variation";
    ui_category = "Scanlines";
    ui_tooltip = "Subtle brightness variation between individual scanline rows,\n"
                 "simulating high-voltage supply ripple and phosphor coating\n"
                 "unevenness in real CRTs.\n"
                 "\n"
                 "Adjacent rows vary together (spatially correlated) -- reads\n"
                 "as organic texture on large uniform areas like sky or fog,\n"
                 "not as noise or grain.\n"
                 "\n"
                 "0.0 = disabled (default, perfectly uniform scanlines).\n"
                 "0.01-0.03 = authentic subtle variation.\n"
                 "0.05-0.08 = clearly visible texture on uniform areas.\n"
                 "\n"
                 "Only visible on large uniform image areas. Invisible during\n"
                 "normal gameplay where image content dominates.";
    ui_min = 0.0; ui_max = 0.15; ui_step = 0.005;
> = 0.0;

uniform float crt_scanline_roll_drift <
    ui_type     = "drag"; ui_label = "Scanline Row Variation Drift";
    ui_category = "Scanlines";
    ui_tooltip  = "Slow temporal drift of the per-row brightness pattern.\n"
                  "Simulates the slight frequency component of real HV supply ripple\n"
                  "-- the pattern is stable but slowly shifts over time.\n"
                  "0.0 = static pattern (default).\n"
                  "0.1-0.3 = very slow drift, barely perceptible.\n"
                  "1.0 = noticeable slow drift over several seconds.";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 0.0;

uniform float crt_beam_min_sigma <
    ui_type = "drag"; ui_label = "Beam Sigma Dark (pixels)";
    ui_category = "Scanlines";
    ui_tooltip = "Beam width for dark pixels in pixel units (ENABLE_BEAM_MODULATION=1).\n"
                 "Lower = tighter beam, deeper dark gaps between scanlines.\n"
                 "For visible dark gaps: keep below 0.3 * scanline_width.\n"
                 "0.5 = half a pixel wide. 1.0 = one pixel wide.";
    ui_min = 0.05; ui_max = 8.0; ui_step = 0.05;
> = 0.5;
uniform float crt_beam_max_sigma <
    ui_type = "drag"; ui_label = "Beam Sigma Bright (pixels)";
    ui_category = "Scanlines";
    ui_tooltip = "Beam width for bright pixels in pixel units (ENABLE_BEAM_MODULATION=1).\n"
                 "Higher = wider beam, brighter scanline centres bleed more.\n"
                 "Should be >= Beam Sigma Dark.";
    ui_min = 0.05; ui_max = 8.0; ui_step = 0.05;
> = 1.0;

uniform float crt_beam_shape <
    ui_type = "drag"; ui_label = "Beam Shape (Generalized Gaussian)";
    ui_category = "Scanlines";
    ui_tooltip = "Controls the cross-section shape of the electron beam.\n"
                 "2.0 = standard Gaussian (default, original behaviour).\n"
                 "Higher values: flatter scanline centre, steeper falloff to gap.\n"
                 "Physically: well-focused CRT beams have a flat plateau centre\n"
                 "and sharp edges. Higher n is more accurate for focused beams.\n"
                 "3.0-4.0 = moderate flat-top. 5.0-6.0 = pronounced flat-top.\n"
                 "Uses 16-point Gauss-Legendre quadrature for n != 2.0 (accurate to < 3% at tight sigma).\n"
                 "Existing presets: leave at 2.0 for unchanged appearance.";
    ui_min = 2.0; ui_max = 8.0; ui_step = 0.1;
> = 2.0;

uniform float crt_beam_corner_spread <
    ui_type = "drag"; ui_label = "Corner Beam Spread";
    ui_category = "Scanlines";
    ui_tooltip = "Widens the beam sigma proportionally to distance from screen centre.\n"
                 "\n"
                 "Practical effect: softens diagonal edge aliasing (stairstepping)\n"
                 "in off-centre areas where diagonal lines meet scanlines, without\n"
                 "blurring the screen centre. More effective than uniform preblur\n"
                 "because it targets where the aliasing is actually worst.\n"
                 "\n"
                 "Physical basis: on a real CRT the electron beam strikes phosphor\n"
                 "at an increasing angle toward edges, making the spot elliptical.\n"
                 "Beams near corners are genuinely less sharp than at screen centre.\n"
                 "\n"
                 "0.0 = disabled, uniform beam (default).\n"
                 "0.3-0.5 = subtle softening, effective for diagonal aliasing.\n"
                 "0.7-1.0 = strong edge softening, matches real CRT geometry.\n"
                 "Works with or without ENABLE_GEOMETRY.";
    ui_min = 0.0; ui_max = 1.5; ui_step = 0.05;
> = 0.0;

uniform float crt_scanline_sigma <
    ui_type = "drag"; ui_label = "Beam Sigma (Fixed, BEAM_MODULATION=0)";
    ui_category = "Scanlines";
    ui_min = 0.1; ui_max = 2.0; ui_step = 0.05;
> = 0.4;

// ============================================================
// Uniforms -- Interlace
// ============================================================

#if ENABLE_INTERLACE
uniform float crt_interlace_strength <
    ui_type = "drag"; ui_label = "Interlace Strength";
    ui_category = "Interlace";
    ui_tooltip = "Simulates CRT interlaced mode by alternating which scanline\n"
                 "fields are bright and dark each frame.\n"
                 "Most visible at high framerates with BFI enabled.\n"
                 "0.0 = no effect. 1.0 = full field blanking alternation.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 0.0;
#endif

// ============================================================
// Uniforms -- Gamma & Contrast
// ============================================================

uniform float crt_gamma_in <
    ui_type = "drag"; ui_label = "CRT Gamma (Input)";
    ui_category = "Gamma & Contrast";
    ui_tooltip = "Set to 1.0 inside Soop sandwich (signal is already linear).";
    ui_min = 1.0; ui_max = 3.0; ui_step = 0.01;
> = 2.2;

uniform float crt_gamma_out <
    ui_type = "drag"; ui_label = "Display Gamma (Output)";
    ui_category = "Gamma & Contrast";
    ui_tooltip = "Set to 1.0 inside Soop sandwich.";
    ui_min = 1.0; ui_max = 3.0; ui_step = 0.01;
> = 2.2;

uniform float crt_brightness <
    ui_type = "drag"; ui_label = "Brightness";
    ui_category = "Gamma & Contrast";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_contrast <
    ui_type = "drag"; ui_label = "Contrast";
    ui_category = "Gamma & Contrast";
    ui_tooltip = "Bezier contrast in Yxy space. No washout.";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_saturation <
    ui_type = "drag"; ui_label = "Saturation";
    ui_category = "Gamma & Contrast";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_colour_temp <
    ui_type = "drag"; ui_label = "Colour Temperature";
    ui_category = "Gamma & Contrast";
    ui_tooltip = "White balance adjustment relative to D65 (neutral).\n"
                 "Negative = warmer (more red/orange, less blue).\n"
                 "Positive = cooler (more blue, less red).\n"
                 "0.0 = D65 neutral (no change).\n"
                 "-0.3 to -0.5 = vintage warm CRT character.\n"
                 "Applied in linear space before BCS curves.";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

// ============================================================
// Uniforms -- Gamut Expansion
// ============================================================

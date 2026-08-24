#if ENABLE_GAMUT_EXPAND
uniform float crt_gamut_expand_strength <
    ui_type = "drag"; ui_label = "Expansion Strength";
    ui_category = "Gamut Expansion";
    ui_tooltip = "How far to expand Rec.709 chrominance toward Rec.2020.\n"
                 "Luminance is unchanged -- only colour primaries are expanded.\n"
                 "\n"
                 "Use the Expansion Method dropdown to select algorithm.\n"
                 "\n"
                 "0.0 = no expansion (default). 0.15-0.25 = good starting point.\n"
                 "0.3-0.5 = vivid but may affect intentional grade decisions.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_gamut_expand_neutral <
    ui_type = "drag"; ui_label = "Neutral Protection";
    ui_category = "Gamut Expansion";
    ui_tooltip = "Protects low-saturation colours from being expanded.\n"
                 "Desaturated colours (near grey) carry deliberate artistic intent\n"
                 "and should not be pushed toward higher saturation.\n"
                 "\n"
                 "0.0 = expand all colours including near-neutrals.\n"
                 "0.1-0.2 = protect only near-greys (recommended).\n"
                 "0.4-0.6 = only expand highly saturated colours.";
    ui_min = 0.0; ui_max = 0.8; ui_step = 0.01;
> = 0.15;

uniform float crt_gamut_expand_skin <
    ui_type = "drag"; ui_label = "Skin Tone Protection";
    ui_category = "Gamut Expansion";
    ui_tooltip = "Reduces expansion in the skin tone hue range (Oklab hue ~20-50deg).\n"
                 "Skin tones are perceptually very sensitive -- even small shifts\n"
                 "look unnatural. Set to 1.0 to fully protect skin tones.\n"
                 "0.0 = no skin protection. 1.0 = full protection (recommended).";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 1.0;

uniform int crt_gamut_expand_method <
    ui_type     = "combo"; ui_label = "Expansion Method";
    ui_category = "Gamut Expansion";
    ui_tooltip  = "Algorithm used for chroma expansion.\n"
                  "\n"
                  "Oklab: simple perceptual chroma boost. Fast, no luminance\n"
                  "weighting. Good baseline.\n"
                  "\n"
                  "ICtCp (recommended): Dolby/ITU broadcast standard. Luminance-\n"
                  "weighted -- bright content expands less than midtones, which is\n"
                  "correct for HDR 709 content. Uses PQ nonlinearity.\n"
                  "\n"
                  "darktable UCS 2022: most accurate. Accounts for Helmholtz-\n"
                  "Kohlrausch effect (colourful colours appear brighter). Chroma\n"
                  "is normalised against perceptual data so equal increments look\n"
                  "equal across all hue angles.";
    ui_items    = "Oklab\0ICtCp (recommended)\0darktable UCS 2022\0";
> = 1;

uniform float crt_gamut_expand_ceiling <
    ui_type = "drag"; ui_label = "Chroma Ceiling";
    ui_category = "Gamut Expansion";
    ui_tooltip = "Limits how much expansion is applied to already-saturated colours.\n"
                 "Never reduces saturation below the original game output --\n"
                 "only prevents the expansion from going too far on vivid colours.\n"
                 "\n"
                 "0.0 = no ceiling, full expansion applied (default).\n"
                 "0.3-0.5 = moderate -- neon colours reined in, muted colours\n"
                 "          still get the full expansion benefit.\n"
                 "1.0 = maximum -- expansion only lifts colours that were\n"
                 "      already near-neutral, vivid colours unchanged.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;
#endif // ENABLE_GAMUT_EXPAND

// ============================================================
// Uniforms -- Phosphor Profile
// ============================================================

#if ENABLE_PHOSPHOR
uniform int crt_phosphor_profile <
    ui_type = "combo"; ui_label = "CRT Phosphor Profile";
    ui_category = "Phosphor Profile";
    ui_tooltip = "Remaps game colours through the chosen CRT phosphor primaries to XYZ,\n"
                 "then to your display gamut. All matrices computed from documented\n"
                 "CIE xy chromaticity coordinates.\n"
                 "\n"
                 "EBU (PAL): European CRTs from 1970s. Green slightly more yellow.\n"
                 "P22: Common US consumer CRT phosphors (1970s-90s NTSC sets).\n"
                 "SMPTE-C / BVM-D / Philips: US broadcast, Sony BVM-D reference\n"
                 "  monitor, and Philips European CRTs -- all share identical\n"
                 "  chromaticities. Most PS1/PS2/N64 era games mastered on BVM-D.\n"
                 "Trinitron: Measured Sony Trinitron phosphor chromaticities.\n"
                 "NTSC 1953: Original FCC spec. Very wide gamut, Illuminant C\n"
                 "  white (~6774K). Early 1950s US TV receiver phosphors.\n"
                 "NTSC 1953 D93: Japanese CRTs (~9300K). Very cool white point.\n"
                 "  SNES/MD/Saturn as seen in Japan on consumer CRTs.\n"
                 "\n"
                 "Set ENABLE_PHOSPHOR=0 to bypass entirely.";
    ui_items = "EBU (PAL)\0"
               "P22 (US consumer)\0"
               "SMPTE-C / Sony BVM-D / Philips\0"
               "Sony Trinitron\0"
               "NTSC 1953 (Illuminant C)\0"
               "NTSC 1953 D93 (Japanese)\0";
> = 0;

uniform int crt_display_gamut <
    ui_type = "combo"; ui_label = "Display Gamut";
    ui_category = "Phosphor Profile";
    ui_tooltip = "Output colour space of your display.\n"
                 "Converts from XYZ back to your display primaries after phosphor correction.\n"
                 "0: sRGB / Rec.709 -- standard monitors\n"
                 "1: DCI-P3 Modern -- wide gamut monitors, most OLEDs\n"
                 "2: DCI-P3 -- cinema standard\n"
                 "3: Adobe RGB\n"
                 "4: Rec. 2020 -- ultra wide gamut (QD-OLED native gamut)";
    ui_items = "sRGB / Rec.709\0DCI-P3 Modern\0DCI-P3\0Adobe RGB\0Rec. 2020\0";
> = 0;

uniform float crt_phosphor_strength <
    ui_type = "drag"; ui_label = "Phosphor Correction Strength";
    ui_category = "Phosphor Profile";
    ui_tooltip = "Blends between original colours (0.0) and fully corrected phosphor colours (1.0).\n"
                 "Allows subtle correction without full commitment to one profile.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

uniform float crt_white_point <
    ui_type = "drag"; ui_label = "White Point";
    ui_category = "Phosphor Profile";
    ui_tooltip = "Chromatic adaptation of the display white point.\n"
                 "Negative = warmer (D55 ~5500K, older consumer CRTs).\n"
                 "Zero = neutral D65 (broadcast reference, default).\n"
                 "Positive = cooler (D93 ~9300K, Japanese consumer CRTs).\n"
                 "Uses proper chromatic adaptation matrices (Guest Advanced).\n"
                 "More accurate than the Colour Temperature slider in Gamma.";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;
#endif

// ============================================================
// Uniforms -- Geometry
// ============================================================

#if ENABLE_GEOMETRY
uniform int crt_geom_mode <
    ui_type = "combo"; ui_label = "Geometry Mode";
    ui_category = "Geometry";
    ui_tooltip = "0: Flat -- no distortion (passthrough).\n"
                 "1: Spherical -- pincushion distortion on both axes.\n"
                 "   Classic consumer CRT look -- corners pull inward.\n"
                 "2: Alt Spherical -- stronger distortion at corners.\n"
                 "3: Cylindrical (Trinitron) -- horizontal curvature only.\n"
                 "   Accurate to Sony Trinitron/Mitsubishi Diamondtron tubes.\n"
                 "   Vertical edges stay straight, horizontal edges curve.";
    ui_items = "Flat\0Spherical\0Alt Spherical\0Cylindrical (Trinitron)\0";
> = 0;

uniform float crt_geom_curvature <
    ui_type = "drag"; ui_label = "Curvature Strength";
    ui_category = "Geometry";
    ui_tooltip = "How strongly the screen curves.\n"
                 "2.0 = subtle. 4.0 = moderate CRT. 6.0+ = strong vintage TV.\n"
                 "Lower values = more curvature (counterintuitively -- this is\n"
                 "the divisor in the pincushion formula, not a direct multiplier).";
    ui_min = 1.0; ui_max = 12.0; ui_step = 0.1;
> = 4.0;

uniform float crt_geom_zoom <
    ui_type = "drag"; ui_label = "Zoom";
    ui_category = "Geometry";
    ui_tooltip = "Zooms into the curved image.\n"
                 "1.0 = no zoom. Values > 1.0 zoom in (crop edges slightly).\n"
                 "Use to fill screen after curvature pulls corners in.\n"
                 "1.05-1.1 is typically enough to hide the edge clamping.";
    ui_min = 0.5; ui_max = 2.0; ui_step = 0.005;
> = 1.0;
#endif

// ============================================================
// Uniforms -- Light Warp
// ============================================================

#if ENABLE_LIGHT_WARP
uniform float crt_warp_strength <
    ui_type = "drag"; ui_label = "Warp Strength";
    ui_category = "Light Warp";
    ui_tooltip = "Lightweight barrel distortion applied to the final image.\n"
                 "Positive = barrel (CRT curve inward). Negative = pincushion.\n"
                 "0.1-0.3 = subtle CRT curve. 0.5+ = strong distortion.\n"
                 "Can be combined with ENABLE_GEOMETRY for stacked warp effects.";
    ui_min = -0.5; ui_max = 0.5; ui_step = 0.01;
> = 0.0;

uniform float3 crt_warp_border_colour <
    ui_type = "color"; ui_label = "Warp Border Colour";
    ui_category = "Light Warp";
    ui_tooltip = "Colour outside the warped screen boundary. Black = authentic CRT.";
> = float3(0.0, 0.0, 0.0);

uniform float crt_pin_phase <
    ui_type = "drag"; ui_label = "Pin Phase";
    ui_category = "Light Warp";
    ui_tooltip = "Horizontal scan linearity error -- horizontal position varies with\n"
                 "vertical scan position. Based on Sony Megatron.\n"
                 "Models CRT deflection yoke geometry where horizontal linearity\n"
                 "changes with vertical deflection angle.\n"
                 "Positive = pincushion. Negative = barrel.\n"
                 "0.0 = disabled (default). 0.02-0.05 = subtle. 0.1+ = strong.";
    ui_min = -0.2; ui_max = 0.2; ui_step = 0.005;
> = 0.0;

uniform float crt_pin_amp <
    ui_type = "drag"; ui_label = "Pin Amp";
    ui_category = "Light Warp";
    ui_tooltip = "Vertical scan linearity error -- vertical position of each column\n"
                 "varies with its horizontal position. Vertical complement to Pin Phase.\n"
                 "Combined with Pin Phase gives full pincushion/barrel raster geometry.\n"
                 "Positive = pincushion. Negative = barrel.\n"
                 "0.0 = disabled (default). 0.02-0.05 = subtle. 0.1+ = strong.";
    ui_min = -0.2; ui_max = 0.2; ui_step = 0.005;
> = 0.0;
#endif

// ============================================================
// Uniforms -- Brightness & Glow
// ============================================================

uniform float crt_bb_dark <
    ui_type = "drag"; ui_label = "Bright Boost (Dark Areas)";
    ui_category = "Brightness & Glow";
    ui_tooltip = ">1.0 lifts scanline gaps to glow. <1.0 crushes them deeper.";
    ui_min = 0.1; ui_max = 3.0; ui_step = 0.05;
> = 1.0;

uniform float crt_bb_bright <
    ui_type = "drag"; ui_label = "Bright Boost (Bright Areas)";
    ui_category = "Brightness & Glow";
    ui_tooltip = "<1.0 restrains highlights (Guest brightboost2 style).";
    ui_min = 0.1; ui_max = 3.0; ui_step = 0.05;
> = 1.0;

uniform int crt_bb_mode <
    ui_type = "combo";
    ui_label = "Bright Boost Reference";
    ui_category = "Brightness & Glow";
    ui_tooltip = "Peak Channel: colour-agnostic, correct for CRT phosphor physics.\n"
                 "Treats R, G, B equally regardless of luminance weight.\n"
                 "Best for high-saturation single-channel content (e.g. blue-heavy scenes).\n"
                 "\n"
                 "Luma (Rec.709): perceptually weighted, may under-represent blue.\n"
                 "Can cause colour shifts in blue-dominant scenes inside Soop/Luma sandwich.\n"
                 "\n"
                 "Per Channel: each channel boosted independently by its own value.\n"
                 "No peak-channel bias -- eliminates warm/cool hue shift at high boost values.\n"
                 "May slightly change saturation since channels scale differently.";
    ui_items = "Peak Channel\0Luma (Rec.709)\0Per Channel\0";
> = 0;

uniform float crt_glow_strength <
    ui_type = "drag"; ui_label = "Glow Strength";
    ui_category = "Brightness & Glow";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_glow_h_radius <
    ui_type = "drag"; ui_label = "Glow Horizontal Radius";
    ui_category = "Brightness & Glow";
    ui_min = 1.0; ui_max = 64.0; ui_step = 1.0;
> = 12.0;

uniform float crt_glow_v_radius <
    ui_type = "drag"; ui_label = "Glow Vertical Radius";
    ui_category = "Brightness & Glow";
    ui_min = 1.0; ui_max = 16.0; ui_step = 0.5;
> = 3.0;

uniform float crt_glow_sigma <
    ui_type = "drag"; ui_label = "Glow Sigma";
    ui_category = "Brightness & Glow";
    ui_min = 0.1; ui_max = 4.0; ui_step = 0.05;
> = 1.2;

uniform float crt_glow_wide_strength <
    ui_type = "drag"; ui_label = "Wide Glow Strength";
    ui_category = "Brightness & Glow";
    ui_tooltip = "Dual-scale bloom: a second, much wider glow pass that creates\n"
                 "a broad soft halo over large bright areas (sky, windows, surfaces).\n"
                 "Complements the tight glow which handles small bright elements.\n"
                 "\n"
                 "0.0 = disabled (default). 0.1-0.3 = subtle area bloom.\n"

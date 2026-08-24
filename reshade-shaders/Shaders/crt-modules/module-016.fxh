#if ENABLE_VIGNETTE
// Uniforms -- Vignette
// ============================================================

uniform int crt_vignette_shape <
    ui_type = "combo"; ui_label = "Vignette Shape";
    ui_category = "Vignette";
    ui_items = "Rectangular (CRT-authentic)\0"
               "Circular / Elliptical (original)\0";
    ui_tooltip = "Rectangular: multiplies independent H and V falloffs.\n"
                 "Corners are naturally darker than edges -- most authentic\n"
                 "to real CRT electron beam intensity falloff.\n"
                 "\n"
                 "Circular: original dot(uv,uv) radial falloff.\n"
                 "Produces an oval on 16:9 screens (touches top/bottom\n"
                 "before sides). Smooth gradient, single power control.\n"
                 "V Power has no effect in this mode.";
> = 1;

uniform float crt_vignette_strength <
    ui_type = "drag"; ui_label = "Vignette Strength";
    ui_category = "Vignette";
    ui_tooltip = "Luminance falloff toward screen edges.\n"
                 "Rectangular CRT-authentic shape: H and V falloffs multiply,\n"
                 "naturally producing darker corners than edges.\n"
                 "0.0 = disabled, 0.15 = subtle, 0.4 = strong.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_vignette_power <
    ui_type = "drag"; ui_label = "Vignette H Power";
    ui_category = "Vignette";
    ui_tooltip = "Horizontal falloff curve. Higher = faster dropoff toward left/right edges.\n"
                 "Controls how quickly brightness drops as you move toward the sides.\n"
                 "Also controls overall power in Circular mode.\n"
                 "Rectangular: keep between 1.0-2.5 to avoid a sliver effect.";
    ui_min = 0.5; ui_max = 8.0; ui_step = 0.1;
> = 1.5;

uniform float crt_vignette_v_power <
    ui_type = "drag"; ui_label = "Vignette V Power";
    ui_category = "Vignette";
    ui_tooltip = "Vertical falloff curve. Higher = faster dropoff toward top/bottom edges.\n"
                 "Typically set lower than H power on wide CRTs (less vertical curvature).\n"
                 "Setting equal to H power gives symmetric falloff.\n"
                 "No effect in Circular mode.\n"
                 "Rectangular: keep between 1.0-2.5 to avoid a sliver effect.";
    ui_min = 0.5; ui_max = 8.0; ui_step = 0.1;
> = 1.5;

uniform float crt_vignette_hdr_threshold <
    ui_type = "drag"; ui_label = "Highlight Protection Threshold";
    ui_category = "Vignette";
    ui_tooltip = "Luminance above which highlights are progressively protected.\n"
                 "Pixels brighter than this start receiving less vignette darkening.\n"
                 "0.5 = protect upper midtones and highlights.\n"
                 "0.7 = only protect bright highlights.\n"
                 "1.0 = no protection (vignette affects everything equally).";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_vignette_hdr_strength <
    ui_type = "drag"; ui_label = "Highlight Protection Strength";
    ui_category = "Vignette";
    ui_tooltip = "How strongly highlights above the threshold are protected.\n"
                 "0.0 = no protection (original behaviour).\n"
                 "0.5 = partial protection -- highlights still darkened but less so.\n"
                 "1.0 = full protection -- highlights above threshold fully isolated.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;
#endif // ENABLE_VIGNETTE

// ============================================================
// Uniforms -- Corner Rounding
// ============================================================

#if ENABLE_CORNER_ROUND
uniform float crt_corner_size <
    ui_type = "drag"; ui_label = "Corner Size";
    ui_category = "Corner Rounding";
    ui_tooltip = "Radius of the rounded screen corners.\n"
                 "0.0 = square corners. 0.05-0.10 = subtle rounding.\n"
                 "0.15-0.25 = strong rounded corners like a consumer TV.";
    ui_min = 0.0; ui_max = 0.35; ui_step = 0.01;
> = 0.0;

uniform float crt_corner_border <
    ui_type = "drag"; ui_label = "Border Size";
    ui_category = "Corner Rounding";
    ui_tooltip = "Adds a darkened shadow border around all four edges of the screen,\n"
                 "simulating the bezel shadow cast by the CRT housing.\n"
                 "0.0 = no border. 0.5-1.0 = subtle edge shadow. 2.0 = strong bezel.";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 0.0;

uniform float crt_corner_intensity <
    ui_type = "drag"; ui_label = "Border Intensity";
    ui_category = "Corner Rounding";
    ui_tooltip = "Power curve applied to the corner/border mask.\n"
                 "Higher = sharper, harder edge with more contrast.\n"
                 "Lower = softer, more gradual transition.\n"
                 "0.25 = very soft. 1.0 = linear. 2.0 = sharp (default).";
    ui_min = 0.25; ui_max = 4.0; ui_step = 0.05;
> = 2.0;

uniform float crt_corner_shadow <
    ui_type = "drag"; ui_label = "Corner Shadow";
    ui_category = "Corner Rounding";
    ui_tooltip = "Darkening at the extreme corners of the screen, simulating\n"
                 "the shadow cast by the CRT bezel pressing against the tube.\n"
                 "Independent of corner rounding -- works at any geometry setting.\n"
                 "0.0 = disabled. 0.2-0.5 = subtle darkening. 1.0 = strong shadow.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;
#endif

// ============================================================
// Uniforms -- Edge Blur
// ============================================================

#if ENABLE_EDGE_BLUR
uniform float crt_edge_blur_strength <
    ui_type = "drag"; ui_label = "Edge Blur Strength";
    ui_category = "Edge Blur";
    ui_tooltip = "Simulates CRT glass optical defocus toward screen edges.\n"
                 "Centre stays sharp, edges soften gradually.\n"
                 "Set ENABLE_EDGE_BLUR=0 in preprocessor to remove entirely.\n"
                 "0.0 = disabled at runtime.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_edge_blur_falloff <
    ui_type = "drag"; ui_label = "Edge Blur Falloff";
    ui_category = "Edge Blur";
    ui_tooltip = "How far from centre the blur begins.\n"
                 "Higher = blur starts closer to edges (tighter safe zone).\n"
                 "Lower = blur creeps toward centre.";
    ui_min = 0.5; ui_max = 4.0; ui_step = 0.1;
> = 2.0;

uniform float crt_edge_blur_radius <
    ui_type = "drag"; ui_label = "Edge Blur Max Radius (pixels)";
    ui_category = "Edge Blur";
    ui_tooltip = "Maximum disc sample radius at screen corners in pixels.\n"
                 "Keep low (2-6) for subtle optical softening.";
    ui_min = 0.5; ui_max = 16.0; ui_step = 0.25;
> = 3.0;

#endif // ENABLE_EDGE_BLUR

// ============================================================
// Uniforms -- Screen Reflection
// ============================================================

#if ENABLE_SCREEN_REFLECT
uniform float crt_reflect_strength <
    ui_type = "drag"; ui_label = "Reflection Strength";
    ui_category = "Screen Reflection";
    ui_tooltip = "Faint blurred self-reflection simulating light bouncing between\n"
                 "the thick CRT glass and the phosphor tube.\n"
                 "A blurred copy of the image composited additively at screen edges,\n"
                 "fading toward the centre. Most visible on dark backgrounds with\n"
                 "bright content near the edges. Based on Mega Bezel concept (GPLv3).\n"
                 "0.0 = disabled. 0.02-0.05 = subtle. 0.1+ = visible.";
    ui_min = 0.0; ui_max = 0.3; ui_step = 0.005;
> = 0.0;

uniform float crt_reflect_gamma <
    ui_type = "drag"; ui_label = "Reflection Gamma";
    ui_category = "Screen Reflection";
    ui_tooltip = "Gamma applied to the reflection before compositing.\n"
                 "Higher = reflection concentrated on brighter content.\n"
                 "Lower = more uniform reflection across all tones.";
    ui_min = 0.5; ui_max = 4.0; ui_step = 0.05;
> = 2.0;

uniform float crt_reflect_fade <
    ui_type = "drag"; ui_label = "Edge Fade";
    ui_category = "Screen Reflection";
    ui_tooltip = "How quickly the reflection fades toward the screen centre.\n"
                 "Higher = reflection concentrated at extreme edges.\n"
                 "Lower = reflection extends further inward.";
    ui_min = 0.5; ui_max = 8.0; ui_step = 0.1;
> = 3.0;
#endif // ENABLE_SCREEN_REFLECT

// ============================================================
// Uniforms -- Tube Diffuse
// ============================================================

#if ENABLE_TUBE_DIFFUSE
uniform float crt_tube_diffuse_strength <
    ui_type = "drag"; ui_label = "Tube Diffuse Strength";
    ui_category = "Tube Diffuse";
    ui_tooltip = "Ambient glow from phosphors scattering through the CRT glass.\n"
                 "A heavily blurred copy of the final image composited additively.\n"
                 "Creates faint warmth proportional to scene brightness.\n"
                 "Different from halation (which halos bright elements).\n"
                 "Based on Mega Bezel fullscreen glow concept (GPLv3).\n"
                 "0.0 = disabled. 0.02-0.06 = subtle ambient warmth. 0.15+ = strong.";
    ui_min = 0.0; ui_max = 0.3; ui_step = 0.005;
> = 0.0;

uniform float crt_tube_diffuse_gamma <
    ui_type = "drag"; ui_label = "Tube Diffuse Gamma";
    ui_category = "Tube Diffuse";
    ui_tooltip = "Gamma applied to the diffuse glow before compositing.\n"
                 "Higher = effect concentrated on brighter content.\n"
                 "Lower = more uniform ambient lift across all tones.";
    ui_min = 0.5; ui_max = 4.0; ui_step = 0.05;
> = 2.0;
#endif // ENABLE_TUBE_DIFFUSE

// ============================================================
// Uniforms -- Edge Feedback
// ============================================================

#if ENABLE_EDGE_FEEDBACK
uniform float crt_edge_feedback_luma <
    ui_type = "drag"; ui_label = "Edge Feedback Strength";
    ui_category = "Edge Feedback";
    ui_tooltip = "Amplifies CRT edge and peripheral effects by comparing the current\n"
                 "pixel against its neighbours from the previous rendered frame.\n"
                 "The difference captures accumulated CRT processing (mask transitions,\n"
                 "scanline gaps, vignette gradient) and feeds it back as edge enhancement.\n"
                 "Effect is strongest at screen edges and geometry-warped areas.\n"
                 "Most effective with ENABLE_GEOMETRY=1.\n"
                 "0.0 = disabled. 0.1-0.3 = subtle. 0.5+ = strong.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_edge_feedback_chroma <
    ui_type = "drag"; ui_label = "Chroma Diffusion";
    ui_category = "Edge Feedback";
    ui_tooltip = "Softens colour channels horizontally using the previous frame as\n"
                 "reference. Creates a subtle chroma diffusion on moving content.\n"
                 "Most effective with ENABLE_GEOMETRY=1.\n"
                 "0.0 = disabled. 0.3-0.6 = subtle. 1.0 = strong diffusion.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;
#endif // ENABLE_EDGE_FEEDBACK

// ============================================================

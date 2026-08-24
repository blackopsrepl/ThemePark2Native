#if ENABLE_PERSISTENCE
uniform float crt_persistence_r <
    ui_type = "drag"; ui_label = "Persistence R";
    ui_category = "Phosphor Persistence";
    ui_tooltip = "Persistence strength for the red channel.\n"
                 "Real P22 phosphors decay at different rates per colour:\n"
                 "Green persists longest, red intermediate, blue fastest.\n"
                 "Set all three equal for uniform decay (original behaviour).";
    ui_min = 0.0; ui_max = 0.99; ui_step = 0.01;
> = 0.0;

uniform float crt_persistence_g <
    ui_type = "drag"; ui_label = "Persistence G";
    ui_category = "Phosphor Persistence";
    ui_tooltip = "Persistence strength for the green channel.\n"
                 "Green phosphors have the longest decay time (~2-3ms on P22).\n"
                 "Set higher than R and B for authentic phosphor physics.";
    ui_min = 0.0; ui_max = 0.99; ui_step = 0.01;
> = 0.0;

uniform float crt_persistence_b <
    ui_type = "drag"; ui_label = "Persistence B";
    ui_category = "Phosphor Persistence";
    ui_tooltip = "Persistence strength for the blue channel.\n"
                 "Blue phosphors have the fastest decay (~0.5ms on P22).\n"
                 "Set lower than R and G for authentic phosphor physics.";
    ui_min = 0.0; ui_max = 0.99; ui_step = 0.01;
> = 0.0;

uniform float crt_persistence_strength <
    ui_type = "drag"; ui_label = "Persistence Strength";
    ui_category = "Phosphor Persistence";
    ui_tooltip = "Simulates phosphor decay within a single frame by blending a\n"
                 "downward-offset copy of the image. Mimics the CRT beam sweep\n"
                 "leaving a fading trail below each scanline.\n"
                 "Keep very low -- 0.05-0.15 for subtle CRT character.\n"
                 "Higher values look like ghosting.\n"
                 "Set ENABLE_PERSISTENCE=0 to remove pass entirely.";
    ui_min = 0.0; ui_max = 0.05; ui_step = 0.001;
> = 0.0;
uniform float crt_persistence_decay <
    ui_type = "drag"; ui_label = "Persistence Decay Distance (pixels)";
    ui_category = "Phosphor Persistence";
    ui_tooltip = "How many pixels below each point the phosphor trail extends.\n"
                 "Matches your scanline width for most natural result.";
    ui_min = 1.0; ui_max = 16.0; ui_step = 0.5;
> = 4.0;

uniform float crt_persistence_h_bleed <
    ui_type = "drag"; ui_label = "Persistence Horizontal Bleed (pixels)";
    ui_category = "Phosphor Persistence";
    ui_tooltip = "Spreads the phosphor trail sideways along the scan line.\n"
                 "The persisting glow is not a point: phosphor grain scatter and\n"
                 "diffusion through the glass spread it horizontally as well as\n"
                 "vertically. Without this the trail is a hard vertical smear.\n"
                 "\n"
                 "Symmetric by design -- the spread is spatial diffusion, not the\n"
                 "beam's left-to-right lag (a whole scan line is drawn in ~50us,\n"
                 "far too fast to be visible against a ~16ms frame).\n"
                 "\n"
                 "0.0 = disabled (pure vertical trail, original behaviour).\n"
                 "1.0-3.0 = subtle softening of the trail. 4.0+ = wide glow spread.\n"
                 "Costs two extra texture taps only when above zero.";
    ui_min = 0.0; ui_max = 8.0; ui_step = 0.25;
> = 0.0;
#endif

// ============================================================
// Uniforms -- Mask
// ============================================================

uniform float crt_triad_width <
    ui_type = "drag"; ui_label = "Triad Width (pixels at 4K ref)";
    ui_category = "Mask";
    ui_tooltip = "Width of one RGB triad in screen pixels at 4K reference resolution.\nHas no effect when ENABLE_MASK=0.";
    ui_min = 0.5; ui_max = 8.0; ui_step = 0.05;
> = 1.5;

uniform float crt_mask_strength <
    ui_type = "drag"; ui_label = "Mask Strength";
    ui_category = "Mask";
    ui_tooltip = "How dark the gaps between phosphors are.\nSet ENABLE_MASK=0 in preprocessor to fully disable.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_mask_boost <
    ui_type = "drag"; ui_label = "Mask Boost";
    ui_category = "Mask";
    ui_tooltip = "Brightness compensation for mask darkening. Set to 1.0 with mask disabled.";
    ui_min = 1.0; ui_max = 2.0; ui_step = 0.01;
> = 1.2;

uniform float crt_phosphor_sharpness <
    ui_type = "drag"; ui_label = "Phosphor Sharpness";
    ui_category = "Mask";
    ui_min = 0.5; ui_max = 8.0; ui_step = 0.1;
> = 2.0;

uniform float3 crt_phosphor_colour <
    ui_type = "color"; ui_label = "Phosphor Colour Temperature";
    ui_category = "Mask";
    ui_tooltip = "(1,1,1)=neutral, (1.02,1,0.97)=P22 warm.";
> = float3(1.0, 1.0, 1.0);

uniform float crt_phosphor_dot <
    ui_type = "drag"; ui_label = "Phosphor Dot Structure";
    ui_category = "Mask";
    ui_tooltip = "Subtle procedural luminance variation between individual phosphor\n"
                 "dots/stripes, simulating manufacturing imperfections in the\n"
                 "phosphor coating. Almost invisible individually but adds texture\n"
                 "and organic feel at high magnification.\n"
                 "0.0 = disabled (default). 0.005-0.015 = authentic subtle texture.\n"
                 "Above 0.02 becomes noticeably uneven.";
    ui_min = 0.0; ui_max = 0.05; ui_step = 0.002;
> = 0.0;

uniform int crt_mask_type <
    ui_type = "combo"; ui_label = "Mask Type";
    ui_category = "Mask";
    ui_tooltip = "0: Aperture Grille -- horizontal RGB stripes. Classic CRT look.\n"
                 "   Works best at larger triad widths (3+) on QD-OLED.\n"
                 "1: Diagonal Aperture Grille -- stripes offset per row.\n"
                 "   Better for QD-OLED triangular subpixels, less alignment-sensitive.\n"
                 "2: Slot Mask -- aperture grille + alternating dark rows.\n"
                 "   More shadow-mask look, good for retro content.\n"
                 "3: Trinitron -- wider green, narrower R/B (real Sony Trinitron proportions).\n"
                 "   Most accurate for Trinitron-era CRT emulation.\n"
                 "4: QD-OLED Delta -- 2x2 checkerboard matching A95L physical subpixel layout.\n"
                 "   Green at diagonal corners, Red/Blue at off-diagonal positions.\n"
                 "   Triad width scales: 2.0=native 1:1, 4.0=2x larger, 6.0=3x larger.\n"
                 "   Best at native display resolution (not DSR/downsampled).\n"
                 "5: QD-OLED Luminance Gate -- QD-OLED pattern applied proportionally to\n"
                 "   pixel luminance. Dark pixels get full phosphor assignment, bright pixels\n"
                 "   get less modulation. Highlights stay clean, shadows get texture.\n"
                 "   Closest to real CRT phosphor behaviour -- no global darkening.\n"
                 "   Use Luma Gate Threshold and Curve sliders to tune.";
    ui_items = "Aperture Grille\0Diagonal Aperture Grille\0Slot Mask\0Trinitron\0QD-OLED Delta\0QD-OLED Luma Gate\0";
> = 0;

uniform float crt_slot_mask_strength <
    ui_type = "drag"; ui_label = "Slot Mask Row Darkness";
    ui_category = "Mask";
    ui_tooltip = "Controls how dark the alternating slot rows are (Mask Type 2 only).\n"
                 "0.0 = no row darkening, 1.0 = fully dark alternate rows.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_luma_gate_threshold <
    ui_type = "drag"; ui_label = "Luma Gate Threshold";
    ui_category = "Mask";
    ui_tooltip = "Luminance level above which mask starts fading out (Type 6 only).\n"
                 "0.0 = gate starts from black. 0.5 = gate starts from midtone.\n"
                 "Higher = mask visible on more of the image including brighter areas.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.2;

uniform float crt_luma_gate_curve <
    ui_type = "drag"; ui_label = "Luma Gate Curve";
    ui_category = "Mask";
    ui_tooltip = "Controls how quickly the mask fades as pixels get brighter (Type 6 only).\n"
                 "0.25 = very gradual fade. 1.0 = linear. 2.0 = sharp fade near threshold.";
    ui_min = 0.1; ui_max = 3.0; ui_step = 0.05;
> = 0.5;

uniform float crt_mask_dither <
    ui_type = "drag"; ui_label = "Mask Moiré Dither";
    ui_category = "Mask";
    ui_tooltip = "Adds a small random sub-pixel phase offset to the mask pattern\n"
                 "within each 16x16 tile, breaking the strict periodicity that\n"
                 "causes moiré interference with certain image frequencies.\n"
                 "\n"
                 "0.0 = no dither (original behaviour).\n"
                 "0.5 = subtle randomisation, moiré noticeably reduced.\n"
                 "1.0 = maximum dither -- may slightly soften mask edges at\n"
                 "      non-integer triad widths.\n"
                 "\n"
                 "Based on Haeberli and Segal (1990) display simulation work on\n"
                 "breaking periodic structure in CRT shadow mask emulation.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 0.0;

uniform int crt_mask_offset_x <
    ui_type = "drag"; ui_label = "QD-OLED Mask Offset X (pixels)";
    ui_category = "Mask";
    ui_tooltip = "Horizontal pixel offset for QD-OLED Delta mask (Type 4).\n"
                 "Nudge 0 or 1 until the mask colour pattern matches your panel.\n"
                 "Test with a white screen at maximum mask strength.";
    ui_min = 0; ui_max = 1; ui_step = 1;
> = 0;

uniform int crt_mask_offset_y <
    ui_type = "drag"; ui_label = "QD-OLED Mask Offset Y (pixels)";
    ui_category = "Mask";
    ui_tooltip = "Vertical pixel offset for QD-OLED Delta mask (Type 4).\n"
                 "Nudge 0 or 1 until the mask colour pattern matches your panel.";
    ui_min = 0; ui_max = 1; ui_step = 1;
> = 0;

// ============================================================
// Uniforms -- Scanlines
// ============================================================

#if ENABLE_SCANLINE_SS
uniform float crt_scanline_ss_strength <
    ui_type = "drag"; ui_label = "Scanline AA (RGSS 4x)";
    ui_category = "Scanlines";
    ui_tooltip = "Rotated-grid supersampling of the scanline beam envelope.\n"
                 "Reduces diagonal staircase aliasing where image edges cross\n"
                 "scanline rows, by averaging the beam weight over 4 subpixel\n"
                 "positions within each pixel.\n"
                 "\n"
                 "0.0 = off (single evaluation, original behaviour).\n"
                 "1.0 = fully supersampled beam envelope (recommended when on).\n"
                 "Intermediate values blend between the two.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 1.0;

uniform float crt_scanline_ss_coherence <
    ui_type = "drag"; ui_label = "Scanline AA Edge Gating";
    ui_category = "Scanlines";
    ui_tooltip = "Restricts the supersampling to coherent diagonal edges using a\n"
                 "structure-tensor measure of local gradient alignment.\n"
                 "\n"
                 "A real edge has gradients all pointing the same way (high\n"
                 "coherence); fine texture has gradients in many directions that\n"
                 "cancel (low coherence). Gating by coherence means the AA can be\n"
                 "raised to full strength to kill diagonal stairs WITHOUT blending\n"
                 "texture detail, which is what causes the smeared look at high\n"
                 "strength when this is off.\n"
                 "\n"
                 "0.0 = no gating (supersample everything -- may blur texture).\n"
                 "1.0 = full gating (only coherent edges supersampled, recommended).";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 1.0;
#endif

uniform float crt_scanline_width <
    ui_type = "drag"; ui_label = "Scanline Width (pixels)";
    ui_category = "Scanlines";
    ui_min = 1.0; ui_max = 8.0; ui_step = 0.25;
> = 4.0;

uniform float crt_scanline_strength <
    ui_type = "drag"; ui_label = "Scanline Strength";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_r_scanline_min <
    ui_type = "drag"; ui_label = "Red Scanline Min";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;
uniform float crt_r_scanline_max <
    ui_type = "drag"; ui_label = "Red Scanline Max";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.9;
uniform float crt_r_scanline_attack <
    ui_type = "drag"; ui_label = "Red Scanline Attack";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_g_scanline_min <
    ui_type = "drag"; ui_label = "Green Scanline Min";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;
uniform float crt_g_scanline_max <
    ui_type = "drag"; ui_label = "Green Scanline Max";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.9;
uniform float crt_g_scanline_attack <
    ui_type = "drag"; ui_label = "Green Scanline Attack";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_b_scanline_min <
    ui_type = "drag"; ui_label = "Blue Scanline Min";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;
uniform float crt_b_scanline_max <
    ui_type = "drag"; ui_label = "Blue Scanline Max";
    ui_category = "Scanlines";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;

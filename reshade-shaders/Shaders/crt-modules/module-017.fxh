#if ENABLE_GRAIN
// Uniforms -- Film Grain
// ============================================================

uniform float crt_grain_intensity <
    ui_type = "drag"; ui_label = "Grain Intensity";
    ui_category = "Film Grain";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.005;
> = 0.0;

uniform bool crt_grain_colour <
    ui_label = "Colour Grain";
    ui_category = "Film Grain";
> = false;

uniform bool crt_grain_animate <
    ui_label = "Animate Grain";
    ui_category = "Film Grain";
> = true;


uniform float crt_grain_shadows <
    ui_type = "drag"; ui_label = "Shadow Grain Amount";
    ui_category = "Film Grain";
    ui_tooltip = "0.0 = no grain in blacks, prevents black lift.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform bool crt_grain_emulsion <
    ui_type     = "input"; ui_label = "Emulsion Mode";
    ui_category = "Film Grain";
    ui_tooltip  = "Switches from Gaussian noise to Voronoi emulsion simulation.\n"
                  "Creates genuine grain blobs/clusters with hard edges,\n"
                  "matching the silver halide crystal clustering in real film.\n"
                  "Per-channel grain sizes: blue coarsest (top emulsion layer),\n"
                  "green mid, red finest (deepest layer) -- physically correct.\n"
                  "Includes highlight residual floor (Dmax grain density).\n"
                  "Slightly more expensive than standard Gaussian grain.";
> = false;

uniform float crt_grain_size <
    ui_type = "drag"; ui_label = "Grain Size";
    ui_category = "Film Grain";
    ui_tooltip = "Controls grain clump size via diffusion pass (matches Marty METEOR).\n"
                 "0.0 = finest single-pixel grain.\n"
                 "1.0 = largest, most organic clumping.\n"
                 "Marty default is ~0.3.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.2;

#endif // ENABLE_GRAIN

// ============================================================
// Uniforms -- Noise Floor
// ============================================================

#if ENABLE_NOISE_FLOOR
uniform float crt_noise_floor <
    ui_type = "drag"; ui_label = "Noise Floor";
    ui_category = "Noise Floor";
    ui_tooltip = "Faint fixed-pattern thermal noise on dark areas.\n"
                 "Simulates CRT electronics thermal noise -- different from film\n"
                 "grain which is signal-dependent. Noise floor is constant,\n"
                 "additive, and most visible on near-black areas.\n"
                 "0.0 = disabled (default). 0.005-0.02 = authentic subtle noise.";
    ui_min = 0.0; ui_max = 0.5; ui_step = 0.005;
> = 0.0;

uniform float crt_noise_floor_scale <
    ui_type = "drag"; ui_label = "Noise Floor Scale";
    ui_category = "Noise Floor";
    ui_tooltip = "Spatial scale of the noise pattern. 1.0 = per-pixel noise.\n"
                 "2.0-4.0 = coarser pattern, more visible structure.";
    ui_min = 1.0; ui_max = 8.0; ui_step = 0.5;
> = 1.0;
#endif // ENABLE_NOISE_FLOOR

// ============================================================
// Uniforms -- Phosphor Decay
// Two methods selectable at runtime:
//   0 = Fibonacci (CRT Dusha-style, uniform darkening)
//   1 = Variable MPRT (Blur Busters, brightness-preserving)
// Set ENABLE_DECAY=1 to enable. Best at 120fps+.
// ============================================================

#include "module-003.fxh"

// -- Phosphor Decay - Variable MPRT only ---------------------

// ============================================================
// Uniforms -- Interference
// ============================================================

#if ENABLE_INTERFERENCE
uniform float crt_hum_intensity <
    ui_type = "drag"; ui_label = "Hum Bar Intensity";
    ui_category = "Interference";
    ui_tooltip = "AC mains interference -- slow scrolling brightness gradient.\n"
                 "Caused by 50/60Hz electrical pickup in poorly shielded CRTs.\n"
                 "Positive = dark band scrolls up. Negative = bright band scrolls up.\n"
                 "0.0 = disabled. 0.1-0.2 = subtle. 0.5+ = strong.";
    ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_hum_speed <
    ui_type = "drag"; ui_label = "Hum Bar Speed";
    ui_category = "Interference";
    ui_tooltip = "Scroll speed. 50 = typical 50Hz PAL. 60 = 60Hz NTSC.";
    ui_min = 1.0; ui_max = 200.0; ui_step = 1.0;
> = 50.0;

uniform float crt_hsync_strength <
    ui_type = "drag"; ui_label = "H-Sync Instability";
    ui_category = "Interference";
    ui_tooltip = "Occasional brief horizontal displacement of individual scanlines,\n"
                 "simulating a weak H-sync signal losing lock momentarily.\n"
                 "Unlike wiggle (continuous whole-frame oscillation), this fires\n"
                 "probabilistically on random rows -- rare, sharp, localised.\n"
                 "Slightly stronger near top of screen (authentic sync behaviour).\n"
                 "Resolution-scaled: same value = same pixel displacement at any res.\n"
                 "0.0 = disabled. 0.002-0.005 = rare subtle glitch. 0.01+ = frequent.";
    ui_min = 0.0; ui_max = 0.03; ui_step = 0.001;
> = 0.0;

uniform float crt_hsync_rate <
    ui_type = "drag"; ui_label = "H-Sync Glitch Rate";
    ui_category = "Interference";
    ui_tooltip = "How frequently H-sync glitches occur. Higher = more rows affected\n"
                 "per frame. 0.01 = very rare (1% of rows). 0.1 = frequent (10%).";
    ui_min = 0.005; ui_max = 0.2; ui_step = 0.005;
> = 0.02;

uniform float crt_wiggle_strength <
    ui_type = "drag"; ui_label = "Wiggle Strength";
    ui_category = "Interference";
    ui_tooltip = "Horizontal UV displacement per scanline row.\n"
                 "Scaled by resolution so 1080p value 0.0012 (NewPixie default)\n"
                 "produces the same pixel displacement at any resolution.\n"
                 "At 4K start around 0.0001-0.0003. At 1080p 0.0005-0.0012.\n"
                 "0.0 = disabled.";
    ui_min = 0.0; ui_max = 0.005; ui_step = 0.0001;
> = 0.0;

uniform float crt_wiggle_speed <
    ui_type = "drag"; ui_label = "Wiggle Speed";
    ui_category = "Interference";
    ui_tooltip = "How fast the interference pattern evolves over time.";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.1;
> = 1.0;

uniform float crt_scanline_jitter <
    ui_type = "drag"; ui_label = "Scanline Jitter";
    ui_category = "Interference";
    ui_tooltip = "Per-scanline vertical displacement in pixels.\n"
                 "Simulates raster instability -- each row offset by a small\n"
                 "random amount that drifts slowly over time.\n"
                 "0.0 = disabled. 0.3-0.8 = subtle. 1.0-2.0 = noticeable.";
    ui_min = 0.0; ui_max = 3.0; ui_step = 0.05;
> = 0.0;

uniform float crt_flicker_strength <
    ui_type = "drag"; ui_label = "Rolling Scanlines Strength";
    ui_category = "Interference";
    ui_tooltip = "Rolling scanline scroll speed. 0.0 = no rolling scanlines.\n"
                 "Higher = faster scroll. 0.5 = slow. 2.0+ = fast.\n"
                 "Amplitude fixed at 0.18 matching NewPixie.";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.05;
> = 0.0;

uniform float crt_accum_modulate <
    ui_type = "drag"; ui_label = "Accumulate Modulation";
    ui_category = "Interference";
    ui_tooltip = "Phosphor afterglow accumulation (NewPixie approach).\n"
                 "Blends each frame with a decayed copy of the previous frame:\n"
                 "output = max(prev * modulate, current * 0.96)\n"
                 "Bright content trails and persists for several frames.\n"
                 "0.0 = disabled. 0.5-0.7 = subtle trail. 0.9+ = heavy ghosting.\n"
                 "Implemented as a dedicated accumulation pass.";
    ui_min = 0.0; ui_max = 0.95; ui_step = 0.01;
> = 0.0;

uniform float crt_magnetic_strength <
    ui_type = "drag"; ui_label = "Magnetic Interference Strength";
    ui_category = "Interference";
    ui_tooltip = "Persistent magnetic field interference -- radial hue rotation\n"
                 "around a focal point, creating characteristic rainbow rings.\n"
                 "Simulates a magnet or speaker placed near the CRT.\n"
                 "0.0 = disabled. 0.1-0.3 = subtle. 0.5+ = strong colour shift.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_magnetic_x <
    ui_type = "drag"; ui_label = "Magnetic Source X";
    ui_category = "Interference";
    ui_tooltip = "Horizontal position of the magnetic interference source.\n"
                 "0.0 = left edge. 0.5 = centre. 1.0 = right edge.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.25;

uniform float crt_magnetic_y <
    ui_type = "drag"; ui_label = "Magnetic Source Y";
    ui_category = "Interference";
    ui_tooltip = "Vertical position of the magnetic interference source.\n"
                 "0.0 = top. 0.5 = centre. 1.0 = bottom.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.25;

uniform float crt_magnetic_radius <
    ui_type = "drag"; ui_label = "Magnetic Radius";
    ui_category = "Interference";
    ui_tooltip = "Radius of the interference rings. Larger = wider rings,\n"
                 "effect extends further from the source.";
    ui_min = 0.1; ui_max = 2.0; ui_step = 0.05;
> = 0.5;

uniform float crt_magnetic_speed <
    ui_type = "drag"; ui_label = "Magnetic Animation Speed";
    ui_category = "Interference";
    ui_tooltip = "Speed of the ring animation -- rings slowly pulse outward.\n"
                 "0.0 = static. 1.0 = slow drift. 3.0+ = fast pulsing.";
    ui_min = 0.0; ui_max = 5.0; ui_step = 0.1;
> = 1.0;

uniform float crt_dot_crawl <
    ui_type = "drag"; ui_label = "Dot Crawl";
    ui_category = "Interference";
    ui_tooltip = "NTSC composite colour subcarrier interference pattern.\n"
                 "Creates a moving diagonal noise at luma-chroma boundaries,\n"
                 "characteristic of 240p content through composite video.\n"
                 "Most visible on coloured edges against contrasting backgrounds.\n"
                 "0.0 = disabled. 0.02-0.05 = subtle. 0.1+ = strong.";
    ui_min = 0.0; ui_max = 0.2; ui_step = 0.005;
> = 0.0;

uniform float crt_ghost_strength <
    ui_type = "drag"; ui_label = "Ghost Strength";
    ui_category = "Interference";
    ui_tooltip = "Chromatic ghost image displaced from source.\n"
                 "Very sensitive -- start at 0.005-0.01 for subtle effect.\n"
                 "NewPixie hardcoded value is 0.15 (ghs) at 1080p.\n"
                 "At 4K/5K use much lower values: 0.005-0.02.\n"
                 "0.0 = disabled.";
    ui_min = 0.0; ui_max = 0.3; ui_step = 0.005;
> = 0.0;

uniform float crt_ghost_speed <
    ui_type = "drag"; ui_label = "Ghost Speed";
    ui_category = "Interference";
    ui_tooltip = "Speed of the animated ghost wobble. Default 1.0 matches NewPixie.\n"
                 "The wobble is very small -- main ghost position is a fixed offset.";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.1;
> = 1.0;
#endif // ENABLE_INTERFERENCE

// Uniforms -- Pipeline (Soop integration)
// Only relevant when PIPELINE=1 (scRGB) or PIPELINE=2 (HDR10)
// ============================================================

#if PIPELINE >= 1
uniform float crt_soop_peak_nits <
    ui_type = "drag"; ui_label = "Display Peak Brightness (nits)";
    ui_category = "Pipeline";
    ui_tooltip = "Peak luminance of your display in nits.\n"
                 "Sony A95L 77\": 1400\n"
                 "Used to set the Reinhard white point for scRGB compression.\n"
                 "Only active when PIPELINE=1 or PIPELINE=2.";
    ui_min = 100.0; ui_max = 4000.0; ui_step = 10.0;
> = 1400.0;

uniform float crt_soop_shadow_gamma <
    ui_type = "drag"; ui_label = "Shadow Gamma";
    ui_category = "Pipeline";
    ui_tooltip = "Gamma lift applied before Reinhard compression.\n"
                 "1.0 = linear (shadows compressed more, highlights cleanest).\n"
                 "1.4 = moderate default, good balance for QD-OLED.\n"
                 "2.0 = shadows better preserved, highlights double-compressed.\n"
                 "Only active when PIPELINE=1 or PIPELINE=2.";
    ui_min = 1.0; ui_max = 2.4; ui_step = 0.05;
> = 1.4;
#endif


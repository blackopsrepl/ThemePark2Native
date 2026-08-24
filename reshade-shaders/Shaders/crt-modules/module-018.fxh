#if PIPELINE == 2
uniform float crt_soop_hdr10_peak_nits <
    ui_type = "drag"; ui_label = "HDR10 Content Peak (nits)";
    ui_category = "Pipeline";
    ui_tooltip = "Peak brightness of the HDR10 content in nits.\n"
                 "Typically 1000 for most HDR10 content.\n"
                 "Only active when PIPELINE=2 (HDR10).";
    ui_min = 100.0; ui_max = 10000.0; ui_step = 10.0;
> = 1000.0;
#endif
uniform float crt_timer < source = "timer"; >;

// ============================================================
// Uniforms -- Anti Burn-In (under Mask category)
// ============================================================

#if ENABLE_BURNIN_PHASE
uniform float crt_burnin_phase_amp <
    ui_type = "drag"; ui_label = "Phase Shift Amplitude (pixels)";
    ui_category = "Mask";
    ui_tooltip = "How many pixels the mask and scanline patterns shift during each cycle.\n"
                 "1-2 pixels is enough to distribute phosphor wear.\n"
                 "Set ENABLE_BURNIN_PHASE=0 in preprocessor to disable entirely.";
    ui_min = 0.0; ui_max = 6.0; ui_step = 0.5;
> = 2.0;

uniform float crt_burnin_phase_period <
    ui_type = "drag"; ui_label = "Phase Shift Period (minutes)";
    ui_category = "Mask";
    ui_tooltip = "How long one full phase cycle takes in minutes.\n"
                 "Longer = slower, less noticeable movement.\n"
                 "Recommended: 3-5 minutes.";
    ui_min = 0.5; ui_max = 20.0; ui_step = 0.5;
> = 3.0;
#endif

#if ENABLE_BURNIN_ORBIT
uniform float crt_burnin_orbit_radius <
    ui_type = "drag"; ui_label = "Pixel Orbit Radius (pixels)";
    ui_category = "Mask";
    ui_tooltip = "Radius of the slow circular pixel shift applied to the entire image.\n"
                 "1-2 pixels is imperceptible but effective for burn-in protection.\n"
                 "Set ENABLE_BURNIN_ORBIT=0 in preprocessor to disable entirely.";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.5;
> = 1.0;

uniform float crt_burnin_orbit_period <
    ui_type = "drag"; ui_label = "Pixel Orbit Period (minutes)";
    ui_category = "Mask";
    ui_tooltip = "How long one full orbit cycle takes in minutes.\n"
                 "Use a different value than the phase period to avoid synchronisation.\n"
                 "Recommended: 7-10 minutes.";
    ui_min = 0.5; ui_max = 30.0; ui_step = 0.5;
> = 7.0;
#endif

// ============================================================
// Intermediate textures
// ============================================================

// Pre-blur H pass output
// PREBLUR_RESOLUTION: 1 = full res (default, acts as AA). 2+ = reduced resolution.
texture2D crt_preblur_h_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH  / PREBLUR_RESOLUTION;
    Height = BUFFER_HEIGHT / PREBLUR_RESOLUTION;
    Format = RGBA16F;
};
sampler2D crt_preblur_h_sampler
{
    Texture   = crt_preblur_h_tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = NONE;
};

// Pre-blur V pass output (= final pre-blurred source)
texture2D crt_preblur_v_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH  / PREBLUR_RESOLUTION;
    Height = BUFFER_HEIGHT / PREBLUR_RESOLUTION;
    Format = RGBA16F;
};
sampler2D crt_preblur_v_sampler
{
    Texture   = crt_preblur_v_tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = NONE;
};

// Edge blur writes directly to backbuffer -- no intermediate texture needed

// ============================================================
// Film Grain: Poisson lookup table (compute shader path)
// 256 color levels x 1024 trials -- built once per frame by CS.
// Stores fraction of halide crystals exposed at each luminance level.
// Falls back to analytical Gaussian path when compute not available.
// ============================================================

// Phosphor persistence: previous frame storage
#if ENABLE_DECAY
// Phase correction: stores cycle index (RGBA8 -- R8 has driver issues on ReShade 6.x)
texture2D crt_decay_phase_tex < pooled = false; >
{
    Width  = 1;
    Height = 1;
    Format = RGBA8;
};
sampler2D crt_decay_phase_sampler { Texture = crt_decay_phase_tex; };

// Auto-resync luminance monitor: two 1x1 textures for lit and dark frame EMA.
// Luma monitor: ping-pong textures so the PS can read previous frame
// while writing current frame (avoids same-pass read/write error).
texture2D crt_decay_luma_lit_tex  < pooled = false; > { Width=1; Height=1; Format=R16F; };
texture2D crt_decay_luma_dark_tex < pooled = false; > { Width=1; Height=1; Format=R16F; };
texture2D crt_decay_luma_lit_prev_tex  < pooled = false; > { Width=1; Height=1; Format=R16F; };
texture2D crt_decay_luma_dark_prev_tex < pooled = false; > { Width=1; Height=1; Format=R16F; };
sampler2D crt_decay_luma_lit_sampler      { Texture=crt_decay_luma_lit_tex;       MipFilter=NONE; MinFilter=POINT; MagFilter=POINT; };
sampler2D crt_decay_luma_dark_sampler     { Texture=crt_decay_luma_dark_tex;      MipFilter=NONE; MinFilter=POINT; MagFilter=POINT; };
sampler2D crt_decay_luma_lit_prev_samp    { Texture=crt_decay_luma_lit_prev_tex;  MipFilter=NONE; MinFilter=POINT; MagFilter=POINT; };
sampler2D crt_decay_luma_dark_prev_samp   { Texture=crt_decay_luma_dark_prev_tex; MipFilter=NONE; MinFilter=POINT; MagFilter=POINT; };

// History format: Pipeline 0 backbuffer is bounded [0,1] so 10-bit is
// lossless there; Pipeline 1/2 hold scRGB/PQ-derived values that can exceed
// 1.0 and need half-float. Halves history bandwidth for SDR-pipeline users.
#if PIPELINE == 0
    #define CRT_DECAY_HIST_FORMAT RGB10A2
#else
    #define CRT_DECAY_HIST_FORMAT RGBA16F
#endif

// prev1: previous raw frame. Always needed when decay is on (dark blend,
// motion sharpen, BB integral).
texture2D crt_decay_prev1_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = CRT_DECAY_HIST_FORMAT;
};
sampler2D crt_decay_prev1_sampler { Texture = crt_decay_prev1_tex; };

#if DECAY_BB_INTEGRAL
// prev2 + raw: only read by the Blur Busters overlap-integral path
// (Variable MPRT with Tube Position on). Gated to avoid two full-resolution
// texture writes per frame for the standard BFI/Fibonacci methods.
texture2D crt_decay_prev2_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = CRT_DECAY_HIST_FORMAT;
};
sampler2D crt_decay_prev2_sampler { Texture = crt_decay_prev2_tex; };
// Raw game frame captured before decay runs -- used for clean history comparison.
// The prev1/prev2 textures capture post-decay output (alternating lit/black),
// which breaks scene-change detection. This texture holds the unmodified signal.
texture2D crt_decay_raw_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = CRT_DECAY_HIST_FORMAT;
};
sampler2D crt_decay_raw_sampler { Texture = crt_decay_raw_tex; };
#endif // DECAY_BB_INTEGRAL
#endif



#if ENABLE_GRAIN
// Grain delta texture: stores (grained - original) delta only
texture2D crt_grain_raw_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA16F;
};
sampler2D crt_grain_raw_samp { Texture = crt_grain_raw_tex; };


// Pre-grain snapshot: clean backbuffer before grain is applied
texture2D crt_pregrain_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA16F;
};
sampler2D crt_pregrain_samp { Texture = crt_pregrain_tex; };
#endif // ENABLE_GRAIN

// Accumulation texture for interference afterglow (NewPixie accumulate modulation)
#if ENABLE_INTERFERENCE
texture2D crt_accum_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};
sampler2D crt_accum_samp { Texture = crt_accum_tex; MagFilter = LINEAR; MinFilter = LINEAR; };
#endif // ENABLE_INTERFERENCE

// Glow horizontal blur output
texture2D crt_glow_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH  / GLOW_RESOLUTION;
    Height = BUFFER_HEIGHT / GLOW_RESOLUTION;
    Format = RGBA16F;
};
sampler2D crt_glow_sampler
{
    Texture   = crt_glow_tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = NONE;
};

// Glow vertical blur output (combined H+V glow, sampled in main pass)
// Resolution set by GLOW_RESOLUTION preprocessor (default 2 = half res).
// Glow is a wide low-frequency effect -- reduced resolution is imperceptible.
texture2D crt_glow_v_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH  / GLOW_RESOLUTION;
    Height = BUFFER_HEIGHT / GLOW_RESOLUTION;
    Format = RGBA16F;
};
sampler2D crt_glow_v_sampler
{
    Texture   = crt_glow_v_tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = NONE;
};

// Wide (secondary) glow textures -- run at 2x lower resolution than tight glow.
// Large-area bloom for bright surfaces, complementing the tight per-element glow.
texture2D crt_glow_wide_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH  / (GLOW_RESOLUTION * 2);
    Height = BUFFER_HEIGHT / (GLOW_RESOLUTION * 2);
    Format = RGBA16F;
};
sampler2D crt_glow_wide_sampler
{
    Texture   = crt_glow_wide_tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = NONE;
};
texture2D crt_glow_wide_v_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH  / (GLOW_RESOLUTION * 2);
    Height = BUFFER_HEIGHT / (GLOW_RESOLUTION * 2);
    Format = RGBA16F;
};
sampler2D crt_glow_wide_v_sampler
{
    Texture   = crt_glow_wide_v_tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = NONE;
};

// Halation blur output -- resolution set by HALATION_RESOLUTION preprocessor
// HALATION_RESOLUTION=4 -> quarter res (cheapest, may alias on movement)
// HALATION_RESOLUTION=2 -> half res (good balance, recommended)
// HALATION_RESOLUTION=1 -> full res (best quality, most expensive)

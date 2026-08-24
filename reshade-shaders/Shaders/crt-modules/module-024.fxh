// ============================================================
// Pass 4: Glow horizontal blur
// Samples pre-blurred signal for luminance-weighted glow.
// ============================================================

void crt_glow_h_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float  px     = ReShade::PixelSize.x * float(PREBLUR_RESOLUTION);
    int    radius = min(int(crt_glow_h_radius), GLOW_H_MAX_RADIUS);
    float  sigma_base = crt_glow_sigma * crt_glow_h_radius * 0.25;

    // Spectral bloom: per-channel sigma based on wavelength-dependent diffraction.
    // Red (~700nm) spreads least, blue (~450nm) spreads most.
    // At spectral=0: all channels identical. At spectral=1: R=0.75x, G=1.0x, B=1.35x.
    float3 sigma_rgb = sigma_base * lerp(float3(1.0, 1.0, 1.0),
                                         float3(0.75, 1.0, 1.35),
                                         crt_glow_spectral);

    float3 result  = 0.0;
    float3 wsum_rgb = 0.0;

    [unroll]
    for (int i = -GLOW_H_MAX_RADIUS; i <= GLOW_H_MAX_RADIUS; i++)
    {
        // Per-channel Gaussian weight -- zero for taps outside radius
        float3 w = (abs(i) <= radius)
                 ? float3(gauss(float(i), sigma_rgb.r),
                          gauss(float(i), sigma_rgb.g),
                          gauss(float(i), sigma_rgb.b))
                 : float3(0.0, 0.0, 0.0);

        #if ENABLE_PREBLUR
        float3 s = tex2D(crt_preblur_v_sampler, texcoord + float2(float(i)*px, 0.0)).rgb;
        #elif ENABLE_GEOMETRY
        float2 uv_glow = geom_warp(texcoord) + float2(float(i)*px, 0.0);
        float3 s = tex2D(ReShade::BackBuffer, uv_glow).rgb;
        #else
        float2 uv_glow = texcoord + float2(float(i)*px, 0.0);
        float3 s = tex2D(ReShade::BackBuffer, uv_glow).rgb;
        #endif
        float lum = dot(s, float3(0.2126, 0.7152, 0.0722));
        float gate;
        if (crt_glow_knee < 0.001)
            gate = float(lum > crt_glow_threshold);
        else
            { float t = saturate((lum - crt_glow_threshold) / crt_glow_knee);
              gate = t * t * (3.0 - 2.0 * t); }
        s = max(s - crt_glow_threshold, 0.0) * lum * gate;

        result   += s * w;
        wsum_rgb += w;
    }

    float3 g = result / max(wsum_rgb, 1e-5);
    g = balance_glow(g, crt_glow_balance);
    color = float4(g, 1.0);
}

// ============================================================
// GlowV pass: vertical glow blur + combine with H glow
// Separated from MainCRT to allow independent GPU scheduling
// and to apply GLOW_V_MAX_RADIUS compile-time unroll.
// ============================================================

void crt_glow_v_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 h_glow = tex2D(crt_glow_sampler, texcoord).rgb;

    if (crt_glow_strength < 0.001)
    {
        color = float4(h_glow, 1.0);
        return;
    }

    float3 v_glow = 0.0;
    float  vwsum  = 0.0;
    float  py     = ReShade::PixelSize.y * float(PREBLUR_RESOLUTION);
    int    vrad   = min(int(crt_glow_v_radius), GLOW_V_MAX_RADIUS);
    float  vsigma = crt_glow_sigma * crt_glow_v_radius * 0.5;

    [unroll]
    for (int j = -GLOW_V_MAX_RADIUS; j <= GLOW_V_MAX_RADIUS; j++)
    {
        float w = (abs(j) <= vrad) ? gauss(float(j), vsigma) : 0.0;
        #if ENABLE_PREBLUR
        float3 s = tex2D(crt_preblur_v_sampler, texcoord + float2(0.0, float(j)*py)).rgb;
        #elif ENABLE_GEOMETRY
        float  py_bb = ReShade::PixelSize.y;
        float3 s = tex2D(ReShade::BackBuffer, geom_warp(texcoord) + float2(0.0, float(j)*py_bb)).rgb;
        #else
        float  py_bb = ReShade::PixelSize.y;
        float3 s = tex2D(ReShade::BackBuffer, texcoord + float2(0.0, float(j)*py_bb)).rgb;
        #endif
        float lum = dot(s, float3(0.2126, 0.7152, 0.0722));
        float gate_v;
        if (crt_glow_knee < 0.001)
            gate_v = float(lum > crt_glow_threshold);
        else
            { float t = saturate((lum - crt_glow_threshold) / crt_glow_knee);
              gate_v = t * t * (3.0 - 2.0 * t); }
        s = max(s - crt_glow_threshold, 0.0) * lum * gate_v;
        v_glow += s * w;
        vwsum  += w;
    }
    v_glow /= max(vwsum, 1e-5);
    v_glow = balance_glow(v_glow, crt_glow_balance);

    float3 glow = lerp(v_glow, h_glow, crt_glow_h_mix);
    color = float4(glow, 1.0);
}

// ============================================================
// Wide glow H pass: large-area bloom at quarter resolution
// ============================================================

void crt_glow_wide_h_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    if (crt_glow_wide_strength < 0.001) { color = float4(0.0, 0.0, 0.0, 1.0); return; }

    float  px     = ReShade::PixelSize.x * float(GLOW_RESOLUTION * 2);
    int    radius = min(int(crt_glow_wide_radius), GLOW_H_MAX_RADIUS);
    float  sigma  = crt_glow_sigma * crt_glow_wide_radius * 0.5;
    float3 result = 0.0;
    float  wsum   = 0.0;

    [unroll]
    for (int i = -GLOW_H_MAX_RADIUS; i <= GLOW_H_MAX_RADIUS; i++)
    {
        float w = (abs(i) <= radius) ? gauss(float(i), sigma) : 0.0;
        #if ENABLE_PREBLUR
        float3 s = tex2D(crt_preblur_v_sampler, texcoord + float2(float(i)*px, 0.0)).rgb;
        #else
        float3 s = tex2D(ReShade::BackBuffer, texcoord + float2(float(i)*px, 0.0)).rgb;
        #endif
        float lum = dot(s, float3(0.2126, 0.7152, 0.0722));
        float gate = float(lum > crt_glow_wide_threshold);
        s = max(s - crt_glow_wide_threshold, 0.0) * lum * gate;
        result += s * w;
        wsum   += w;
    }
    color = float4(result / max(wsum, 1e-5), 1.0);
}

// Wide glow V pass: vertical blur + combine
void crt_glow_wide_v_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    if (crt_glow_wide_strength < 0.001) { color = float4(0.0, 0.0, 0.0, 1.0); return; }

    float  py     = ReShade::PixelSize.y * float(GLOW_RESOLUTION * 2);
    int    vrad   = min(int(crt_glow_wide_radius), GLOW_V_MAX_RADIUS);
    float  vsigma = crt_glow_sigma * crt_glow_wide_radius * 0.5;
    float3 result = 0.0;
    float  wsum   = 0.0;

    [unroll]
    for (int j = -GLOW_V_MAX_RADIUS; j <= GLOW_V_MAX_RADIUS; j++)
    {
        float w = (abs(j) <= vrad) ? gauss(float(j), vsigma) : 0.0;
        #if ENABLE_PREBLUR
        float3 s = tex2D(crt_preblur_v_sampler, texcoord + float2(0.0, float(j)*py)).rgb;
        #else
        float3 s = tex2D(ReShade::BackBuffer, texcoord + float2(0.0, float(j)*py)).rgb;
        #endif
        float lum = dot(s, float3(0.2126, 0.7152, 0.0722));
        float gate = float(lum > crt_glow_wide_threshold);
        s = max(s - crt_glow_wide_threshold, 0.0) * lum * gate;
        result += s * w;
        wsum   += w;
    }

    // Sample wide H glow and combine
    float3 wide_h = tex2D(crt_glow_wide_sampler, texcoord).rgb;
    float3 wide_v = result / max(wsum, 1e-5);
    float3 wide   = lerp(wide_v, wide_h, crt_glow_h_mix);
    wide = balance_glow(wide, crt_glow_balance);
    color = float4(wide, 1.0);
}

// ============================================================
// Pass 5: Main CRT pass
// Uses pre-blurred signal as source instead of raw backbuffer.
// ============================================================

void crt_main_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float2 fc = texcoord * float2(BUFFER_WIDTH, BUFFER_HEIGHT);

    // -- Anti burn-in offsets --
    // IMPORTANT: All offsets applied only to mask and scanline pattern coordinates,
    // never to the image sampling UVs. Sub-pixel shifts on scanlines cause
    // brightness fluctuation because frac() is non-linear across the beam profile.
    // Scanlines use integer steps only. Mask uses continuous sinusoidal shift.

    // Anti burn-in: integer triad-width steps only.
    // Shifting by exact multiples of the triad width is visually identical
    // (the pattern is periodic) but different display pixels receive each phosphor,
    // distributing wear. No brightness fluctuation possible at any mask strength.

    #if ENABLE_BURNIN_PHASE
        // Phase: alternates between 0 and crt_burnin_phase_amp pixels on a slow
        // timer. Shift is rounded to WHOLE pixels: integer-pixel shifts relocate
        // exactly the same set of sampled mask values, guaranteeing identical
        // average brightness at any mask strength (no brightness fluctuation).
        float phase_ms      = crt_burnin_phase_period * 60000.0;
        float phase_steps_  = floor(crt_timer / phase_ms);
        float phase_toggle  = phase_steps_ - floor(phase_steps_ * 0.5) * 2.0; // 0 or 1
        float phase_h       = phase_toggle * round(crt_burnin_phase_amp
                            * (float(BUFFER_WIDTH) / 3840.0)); // integer pixels
    #else
        float phase_h       = 0.0;
    #endif

    #if ENABLE_BURNIN_ORBIT
        // Orbit: steps through 8 discrete positions on a circle of radius
        // crt_burnin_orbit_radius pixels. Each position is rounded to WHOLE
        // pixels (see phase note above -- guarantees zero brightness change).
        // Discrete stepping avoids perceptible motion; each step holds one period.
        float orbit_ms      = crt_burnin_orbit_period * 60000.0;
        float orbit_steps_  = floor(crt_timer / orbit_ms);
        float orbit_idx     = orbit_steps_ - floor(orbit_steps_ * 0.125) * 8.0; // 0..7
        float orbit_angle   = orbit_idx * 0.7853982; // 2pi/8
        float orbit_r       = crt_burnin_orbit_radius * (float(BUFFER_WIDTH) / 3840.0);
        float2 orbit_offs   = round(float2(cos(orbit_angle), sin(orbit_angle)) * orbit_r);
    #else
        float2 orbit_offs   = float2(0.0, 0.0);
    #endif



    // Chromatic aberration + convergence UV offsets.
    // When disabled, all channels sample from the same texcoord.
    #if ENABLE_CA
    float2 ca_centre  = texcoord - 0.5;
    float  ca_dist    = pow(length(ca_centre * float2(float(BUFFER_WIDTH)/float(BUFFER_HEIGHT), 1.0)),
                            crt_ca_falloff);
    float2 ca_vec     = ca_centre * ca_dist * crt_ca_strength;
    float2 ca_r = -ca_vec * 0.5;
    float2 ca_b =  ca_vec;
    #else
    float2 ca_r = 0.0;
    float2 ca_b = 0.0;
    #endif

    #if ENABLE_CONVERGENCE
    // Radial misconvergence: Δy = k * x² where x is normalised screen position.
    // Grows from zero at centre to maximum at horizontal edges.
    // Red diverges upward, blue downward -- matches real pincushion misconvergence.
    float  cx          = (texcoord.x - 0.5) * 2.0;
    float  ar          = float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);
    float  radial_err  = crt_convergence_radial * cx * cx * ar * ReShade::PixelSize.y;
    // Horizontal convergence: independent per-channel X offset
    float2 h_r = float2(crt_convergence_h_r * ReShade::PixelSize.x, 0.0);
    float2 h_b = float2(crt_convergence_h_b * ReShade::PixelSize.x, 0.0);
    float2 uv_r = texcoord + float2(0.0, (crt_convergence_r - radial_err) * ReShade::PixelSize.y) + ca_r + h_r;
    float2 uv_g = texcoord + float2(0.0,  crt_convergence_g               * ReShade::PixelSize.y);
    float2 uv_b = texcoord + float2(0.0, (crt_convergence_b + radial_err) * ReShade::PixelSize.y) + ca_b + h_b;
    #else
    float2 uv_r = texcoord + ca_r;
    float2 uv_g = texcoord;
    float2 uv_b = texcoord + ca_b;
    #endif

    float3 c;

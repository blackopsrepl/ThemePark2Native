#if ENABLE_SHARPEN
void crt_sharpen_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    if (crt_sharpen_strength < 0.001)
    {
        color = tex2D(ReShade::BackBuffer, texcoord);
        return;
    }
    float2 px = ReShade::PixelSize;

    float3 c  = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float3 n  = tex2D(ReShade::BackBuffer, texcoord + float2( 0.0, -px.y)).rgb;
    float3 s  = tex2D(ReShade::BackBuffer, texcoord + float2( 0.0,  px.y)).rgb;
    float3 e  = tex2D(ReShade::BackBuffer, texcoord + float2( px.x, 0.0)).rgb;
    float3 w  = tex2D(ReShade::BackBuffer, texcoord + float2(-px.x, 0.0)).rgb;

    // Diagonal neighbours for more accurate local contrast estimate.
    // AMD full CAS uses 8-neighbour min/max for the weight computation
    // while keeping the 4-axis sharpening kernel -- better on diagonal edges.
    float3 ne = tex2D(ReShade::BackBuffer, texcoord + float2( px.x, -px.y)).rgb;
    float3 nw = tex2D(ReShade::BackBuffer, texcoord + float2(-px.x, -px.y)).rgb;
    float3 se = tex2D(ReShade::BackBuffer, texcoord + float2( px.x,  px.y)).rgb;
    float3 sw = tex2D(ReShade::BackBuffer, texcoord + float2(-px.x,  px.y)).rgb;

    // Local min/max across all 8 neighbours (contrast estimate only)
    float3 mn = min(min(min(n, s), min(e, w)), min(min(ne, nw), min(se, sw)));
    float3 mx = max(max(max(n, s), max(e, w)), max(max(ne, nw), max(se, sw)));
    mn = min(mn, c); mx = max(mx, c);

    // Normalise range relative to peak -- makes weight HDR-safe
    // Without normalisation, large HDR values cause near-division-by-zero
    float3 rng      = mx - mn;
    float3 rng_norm = rng / (mx + 0.001);
    float3 w_cas    = -rng_norm / (4.0 - 2.0 * rng_norm + 0.001);
    w_cas = clamp(w_cas, -crt_sharpen_clamp, 0.0) * crt_sharpen_strength;

    float3 sharpened = (c + (n + s + e + w) * w_cas) / (1.0 + 4.0 * w_cas);
    color = float4(max(sharpened, 0.0), 1.0);
}
#endif

// ============================================================
// Motion-adaptive sharpening pass
// Uses frame difference (current vs prev1_tex) as a motion mask.
// CAS sharpening is applied with strength proportional to per-pixel
// motion magnitude -- moving areas get sharpened, static areas don't.
// Requires ENABLE_DECAY=1 for prev1_tex to be populated.
// ============================================================
#if ENABLE_MOTION_SHARPEN
void crt_motion_sharpen_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float2 px = ReShade::PixelSize;

    float3 c = tex2D(ReShade::BackBuffer, texcoord).rgb;

    // Motion magnitude: luma difference between current and previous frame.
    // prev1_tex holds the pre-decay raw frame from last frame's store pass.
    // If ENABLE_DECAY is off, prev1 is uninitialised -- guard with the define.
    #if ENABLE_DECAY
    float3 prev     = tex2D(crt_decay_prev1_sampler, texcoord).rgb;
    float  luma_c   = dot(c,    float3(0.2126, 0.7152, 0.0722));
    float  luma_p   = dot(prev, float3(0.2126, 0.7152, 0.0722));
    float  motion   = saturate((abs(luma_c - luma_p) - crt_msharpen_motion_threshold)
                               / max(crt_msharpen_motion_threshold, 0.001));
    #else
    float motion = 1.0; // no motion data -- apply uniformly
    #endif

    // CAS sharpening weighted by motion magnitude
    float effective_strength = crt_msharpen_strength * motion;

    if (effective_strength < 0.001)
    {
        color = float4(c, 1.0);
        return;
    }

    float3 n = tex2D(ReShade::BackBuffer, texcoord + float2( 0.0, -px.y)).rgb;
    float3 s = tex2D(ReShade::BackBuffer, texcoord + float2( 0.0,  px.y)).rgb;
    float3 e = tex2D(ReShade::BackBuffer, texcoord + float2( px.x,  0.0)).rgb;
    float3 w = tex2D(ReShade::BackBuffer, texcoord + float2(-px.x,  0.0)).rgb;

    float3 mn       = min(min(min(n, s), min(e, w)), c);
    float3 mx       = max(max(max(n, s), max(e, w)), c);
    float3 rng      = mx - mn;
    float3 rng_norm = rng / (mx + 0.001);
    float3 w_cas    = -rng_norm / (4.0 - 2.0 * rng_norm + 0.001);
    w_cas = clamp(w_cas, -crt_msharpen_clamp, 0.0) * effective_strength;

    float3 sharpened = (c + (n + s + e + w) * w_cas) / (1.0 + 4.0 * w_cas);
    color = float4(max(sharpened, 0.0), 1.0);
}
#endif

// ============================================================
// Phosphor persistence pass
// Blends a downward-offset copy of the image at low opacity
// to simulate phosphor decay trailing below each scanline.
// Also stores current frame for next frame blend.
// ============================================================

#if ENABLE_PERSISTENCE
void crt_persistence_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 current = tex2D(ReShade::BackBuffer, texcoord).rgb;

    // Skip when the effect is fully off. This must consider the per-channel
    // R/G/B sliders as well as the master strength: gating on strength alone
    // made the per-channel controls dead unless strength was also raised.
    float max_persist = max(crt_persistence_strength,
                        max(crt_persistence_r,
                        max(crt_persistence_g, crt_persistence_b)));
    if (max_persist < 0.001)
    {
        color = float4(current, 1.0);
        return;
    }

    // Sample from above -- the phosphor trail appears below the beam
    // The beam scans top to bottom, so pixels above were lit slightly earlier
    // and their phosphor emission trails downward
    float py = ReShade::PixelSize.y * crt_persistence_decay;

    // Trail source: the pixel above (scanned slightly earlier by the beam).
    // Optionally spread horizontally -- phosphor grain scatter and diffusion
    // through the glass make the persisting glow a small patch, not a point.
    // Taps are converted to linear BEFORE averaging so the sum is physically a
    // sum of light rather than of encoded values.
    float3 above_lin;
    if (crt_persistence_h_bleed > 0.001)
    {
        float hx = ReShade::PixelSize.x * crt_persistence_h_bleed;
        float3 a_c = glin(tex2D(ReShade::BackBuffer, texcoord + float2(0.0, -py)).rgb);
        float3 a_l = glin(tex2D(ReShade::BackBuffer, texcoord + float2(-hx, -py)).rgb);
        float3 a_r = glin(tex2D(ReShade::BackBuffer, texcoord + float2( hx, -py)).rgb);
        // Normalised centre-weighted kernel (0.25/0.5/0.25): unit gain, so a
        // flat field is unchanged and the trail cannot gain brightness.
        above_lin = a_c * 0.5 + (a_l + a_r) * 0.25;
    }
    else
    {
        above_lin = glin(tex2D(ReShade::BackBuffer, texcoord + float2(0.0, -py)).rgb);
    }

    // Per-channel persistence: R/G/B have different phosphor decay rates.
    // Green persists longest (P22 ~2-3ms), red intermediate, blue shortest (~0.5ms).
    // crt_persistence_r/g/b override per-channel; if all zero, fall back to uniform.
    float3 cur_lin = glin(current);

    // Per-channel blend weights: use per-channel if any non-zero, else uniform
    float use_perchannel = max(max(crt_persistence_r, crt_persistence_g), crt_persistence_b);
    float3 blend = (use_perchannel > 0.001)
                 ? float3(crt_persistence_r, crt_persistence_g, crt_persistence_b)
                 : float3(crt_persistence_strength, crt_persistence_strength, crt_persistence_strength);

    float3 trail_lin = lerp(cur_lin, above_lin, blend);
    float3 trail     = genc(max(trail_lin, 0.0));
    // Only ever adds light -- never darkens
    color = float4(max(current, trail), 1.0);
}

#endif

// ============================================================
// Pipeline: Soop Before/After passes
// ============================================================

#if PIPELINE >= 1
void crt_soop_before_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 c = tex2D(ReShade::BackBuffer, texcoord).rgb;
#if PIPELINE == 1
    // scRGB: apply Reinhard compression with shadow gamma lift
    c = soop_reinhard(c, crt_soop_peak_nits, crt_soop_shadow_gamma);
#elif PIPELINE == 2
    // HDR10: PQ decode to linear, then Reinhard compress
    c = soop_pq_to_linear(c, crt_soop_hdr10_peak_nits);
    c = soop_reinhard_simple(c);
    c = soop_linear_to_srgb(c);
#endif
    color = float4(c, 1.0);
}

void crt_soop_after_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 c = tex2D(ReShade::BackBuffer, texcoord).rgb;
#if PIPELINE == 1
    // scRGB: apply InvReinhard to restore HDR range
    c = soop_inv_reinhard(c, crt_soop_shadow_gamma);
#elif PIPELINE == 2
    // HDR10: sRGB to linear, InvReinhard, then PQ encode
    c = soop_srgb_to_linear(c);
    c = soop_inv_reinhard_simple(c);
    c = soop_linear_to_pq(c, crt_soop_hdr10_peak_nits);
#endif
    color = float4(c, 1.0);
}
#endif // PIPELINE >= 1

// ============================================================
// Geometry: barrel distortion (final pass UV warp)
// Simulates CRT glass curvature. Applied after all CRT processing
// so scanlines and mask remain geometrically straight (physically correct).
// No corner masking -- pixels at edges clamp to edge colour, stay lit.
// ============================================================

#if ENABLE_GEOMETRY
// Geometry: pincushion/barrel UV warp simulating CRT screen curvature
// Mode 1 (Spherical): curves both H and V -- classic consumer CRT
// Mode 2 (Alt Spherical): stronger corner distortion
// Mode 3 (Cylindrical/Trinitron): horizontal curvature only, V stays straight
// Based on crt-geom pincushion formula -- no 3D projection needed.
// Corners are clamped to edge colour, no black masking, all pixels lit.
void crt_geometry_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    if (crt_geom_mode == 0)
    {
        color = tex2D(ReShade::BackBuffer, texcoord);
        return;
    }

    // Map to -1..1, apply zoom (scale UV so values > 1.0 zoom in)
    float2 uv = (texcoord * 2.0 - 1.0) / crt_geom_zoom;

    // Aspect ratio -- needed so curvature appears circular not elliptical
    float ar = float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);
    uv.x *= ar;

    float cv = crt_geom_curvature; // divisor -- smaller = more curved

    if (crt_geom_mode == 1)
    {
        // Spherical: pincushion on both axes
        uv.x *= 1.0 + (uv.y * uv.y) / (cv * cv);
        uv.y *= 1.0 + (uv.x * uv.x) / (cv * cv * ar * ar);
    }
    else if (crt_geom_mode == 2)
    {
        // Alt Spherical: stronger distortion -- power of 1.5 instead of 2
        uv.x *= 1.0 + pow(abs(uv.y) / cv, 1.5);
        uv.y *= 1.0 + pow(abs(uv.x) / (cv * ar), 1.5);
    }
    else
    {
        // Cylindrical (Trinitron): horizontal curvature only
        // Vertical axis stays perfectly straight
        uv.x *= 1.0 + (uv.y * uv.y) / (cv * cv);
        // uv.y unchanged
    }

    // Undo aspect correction
    uv.x /= ar;

    // Map back to 0..1, clamp to edge (no black corners, all pixels lit)
    float2 tc = clamp(uv * 0.5 + 0.5, 0.0, 1.0);
    color = tex2D(ReShade::BackBuffer, tc);
}
#endif// ============================================================
// Phosphor Decay pass (BFI-style motion clarity)
// Fibonacci-weighted exponential decay modulates current frame
// brightness based on position within the decay cycle.
// Based on CRT Dusha by Maxim Lapounov (MIT license)
// ============================================================

#include "module-006.fxh"
// ============================================================
// ============================================================
// Gamut Expansion PS
// Three methods selectable via the Expansion Method dropdown in the UI:
// 0 = Oklab chroma boost
// 1 = ICtCp luminance-weighted (Dolby/ITU, recommended for HDR content)

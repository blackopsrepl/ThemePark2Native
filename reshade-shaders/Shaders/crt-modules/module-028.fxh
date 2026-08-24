#if ENABLE_GRAIN
// ============================================================
// Grain pass (merged): Snapshot + delta in one dual-output pass
// Output 0 -> crt_pregrain_tex (clean snapshot)
// Output 1 -> crt_grain_raw_tex (grain delta)
// Saves one full-res pass vs separate snapshot + raw passes.
// ============================================================

void crt_grain_merged_PS(
    in  float4 position  : SV_Position,
    in  float2 texcoord  : TEXCOORD0,
    out float4 out_clean : SV_Target0,
    out float4 out_delta : SV_Target1)
{
    float3 c  = tex2D(ReShade::BackBuffer, texcoord).rgb;
    out_clean = float4(c, 1.0);
    float3 delta = float3(0.5, 0.5, 0.5);

    if (crt_grain_intensity > 0.001)
    {
        uint2  p   = uint2(texcoord * float2(BUFFER_WIDTH, BUFFER_HEIGHT));
        float3 cl  = glin(c);
        float  luma_g = dot(cl, float3(0.2126, 0.7152, 0.0722));

        uint rng = grain_uhash(grain_uhash(p.y) + p.x);
        if (crt_grain_animate) rng += FRAMECOUNT;

        float  shadow_blend = lerp(crt_grain_shadows, 1.0, saturate(luma_g * 8.0));
        float3 cl_grained;

        float  luma_e = dot(cl, float3(0.2126, 0.7152, 0.0722));

        if (crt_grain_emulsion)
        {
            uint   fsalt = crt_grain_animate ? FRAMECOUNT : 0u;
            float  cell_scale = 0.25 + crt_grain_size * 1.0;
            float2 pos        = float2(p);
            float3 gn_e  = grain_emulsion(pos, cell_scale,
                                          fsalt, crt_grain_intensity, luma_e);
            gn_e *= shadow_blend;
            cl_grained = grain_hdr(cl);
            cl_grained += gn_e;
            cl_grained = grain_sdr(cl_grained);
        }
        else
        {
            // Standard Gaussian grain (METEOR-style)
            float3 u3 = float3(grain_next2(rng), grain_next1(rng));
            float3 gn = grain_bm3(u3);
            float  poisson_amp = grain_poisson_sigma(luma_e, crt_grain_intensity);
            poisson_amp *= shadow_blend;

            if (crt_grain_colour)
            {
                cl_grained = grain_hdr(cl);
                cl_grained += gn * poisson_amp;
                cl_grained = grain_sdr(cl_grained);
            }
            else
            {
                float grey  = dot(cl, float3(0.2126, 0.7152, 0.0722));
                float grey3 = grain_hdr(grey.xxx).x;
                grey3 += gn.x * poisson_amp;
                grey3 = grain_sdr(grey3.xxx).x;
                float orig  = dot(cl, float3(0.2126, 0.7152, 0.0722));
                cl_grained  = (orig > 0.0001) ? cl * (grey3 / orig) : cl;
            }
        }
        delta = (genc(cl_grained) - c) * 0.5 + 0.5;
    }

    // Temporal grain correlation: blend previous frame's grain into static areas.
    // Real film grain has temporal coherence -- the silver halide crystals are
    // physically fixed on the film stock, so static scenes see consistent grain.
    // Motion mask from prev1_tex: large difference = motion = fresh grain.
    out_delta = float4(delta, 1.0);
}

// Legacy single-output stubs kept for reference but no longer used in technique
void crt_pregrain_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    color = tex2D(ReShade::BackBuffer, texcoord);
}

void crt_grain_raw_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 c  = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float2 fc = texcoord * float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float3 delta = float3(0.5, 0.5, 0.5);

    if (crt_grain_intensity > 0.001)
    {
        uint2  p   = uint2(fc);
        uint   rng = grain_uhash(grain_uhash(p.y) + p.x);
        if (crt_grain_animate) rng += FRAMECOUNT;
        float3 u3     = float3(grain_next2(rng), grain_next1(rng));
        float3 gn     = grain_bm3(u3);
        float3 cl     = glin(c);
        float  luma_g = dot(cl, float3(0.2126, 0.7152, 0.0722));
        float  poisson_amp = grain_poisson_sigma(luma_g, crt_grain_intensity);
        poisson_amp *= lerp(crt_grain_shadows, 1.0, saturate(luma_g * 8.0));
        float3 cl_grained;
        if (crt_grain_colour)
        {
            cl_grained = grain_hdr(cl);
            cl_grained += gn * poisson_amp;
            cl_grained = grain_sdr(cl_grained);
        }
        else
        {
            float grey = dot(cl, float3(0.2126, 0.7152, 0.0722));
            float grey3 = grain_hdr(grey.xxx).x;
            grey3 += gn.x * poisson_amp;
            grey3 = grain_sdr(grey3.xxx).x;
            float orig = dot(cl, float3(0.2126, 0.7152, 0.0722));
            cl_grained = (orig > 0.0001) ? cl * (grey3 / orig) : cl;
        }
        delta = (genc(cl_grained) - c) * 0.5 + 0.5;
    }
    else
    {
        delta = float3(0.5, 0.5, 0.5); // neutral (zero delta)
    }

    color = float4(delta, 1.0);
}

// ============================================================
// Grain pass 2: Diffuse the delta, add back to clean image
// Blurs only the grain delta (not the image), then composites.
// This is the correct approach: diffusion softens grain clumps
// without affecting underlying image sharpness.
// ============================================================

void crt_grain_diffuse_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 clean = tex2D(crt_pregrain_samp, texcoord).rgb;

    if (crt_grain_intensity < 0.001)
    {
        color = float4(clean, 1.0);
        return;
    }

    float2 px = ReShade::PixelSize;
    float2 fc = texcoord * float2(BUFFER_WIDTH, BUFFER_HEIGHT);

    // Sigma: tight diffusion -- the organic look comes from Morton spatial correlation,
    // not from blurring. Keep sigma small so individual grain pixels stay sharp.
    float sigma = lerp(0.3, 1.5, crt_grain_size);

    float3 diffused_delta;

    if (crt_grain_size < 0.001)
    {
        diffused_delta = tex2D(crt_grain_raw_samp, texcoord).rgb;
    }
    else
    {
        float3 result = 0.0;
        float  wsum   = 0.0;

        for (int x = -1; x <= 1; x++)
        for (int y = -1; y <= 1; y++)
        {
            float2 tp  = float2(float(x), float(y));
            float2 uv  = texcoord + tp * px;
            float3 d   = tex2D(crt_grain_raw_samp, uv).rgb;

            uint2  pi  = uint2(uv * float2(BUFFER_WIDTH, BUFFER_HEIGHT));
            uint   rng = grain_uhash(grain_uhash(pi.y) + pi.x);
            if (crt_grain_animate) rng += FRAMECOUNT;
            float2 rand01 = float2(rng & 31u, rng >> 5u) / 32.0;
            float2 bm     = grain_boxmuller_2d(rand01) * sigma;
            float2 offs   = tp + bm;

            float w = exp(-dot(offs, offs));

            result += d * w;
            wsum   += w;
        }
        diffused_delta = result / max(wsum, 1e-5);
    }

    // Decode delta from [0,1] storage back to signed [-0.5, 0.5]
    float3 grain = (diffused_delta - 0.5) * 2.0;

    // Add diffused grain delta to clean pre-grain image
    color = float4(saturate(clean + grain), 1.0);
}

#endif // ENABLE_GRAIN

// ============================================================
// Post-scanline vertical softening pass
// Tiny vertical gaussian to smooth scanline-edge intersections
// on curved geometry. Asymmetric -- slightly stronger below
// to match natural phosphor spread direction.
// ============================================================

#if ENABLE_SCANLINE_SOFTEN
void crt_soften_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    if (crt_soften_strength < 0.001)
    {
        color = tex2D(ReShade::BackBuffer, texcoord);
        return;
    }
    float py    = ReShade::PixelSize.y;
    float sigma = crt_soften_strength * 0.8;

    // 5-tap asymmetric vertical gaussian
    // Slight downward bias matches CRT beam sweep direction
    float w0 = gauss(0.0,  sigma);
    float w1 = gauss(1.0,  sigma);
    float w2 = gauss(2.0,  sigma);
    float w1d = gauss(0.8, sigma); // slightly closer below
    float w2d = gauss(1.8, sigma);

    float3 c =
        tex2D(ReShade::BackBuffer, texcoord + float2(0.0, -2.0*py)).rgb * w2  +
        tex2D(ReShade::BackBuffer, texcoord + float2(0.0, -1.0*py)).rgb * w1  +
        tex2D(ReShade::BackBuffer, texcoord).rgb                         * w0  +
        tex2D(ReShade::BackBuffer, texcoord + float2(0.0,  1.0*py)).rgb * w1d +
        tex2D(ReShade::BackBuffer, texcoord + float2(0.0,  2.0*py)).rgb * w2d;

    float wsum = w2 + w1 + w0 + w1d + w2d;
    color = float4(c / wsum, 1.0);
}
#endif

// ============================================================
// Contrast-adaptive sharpening pass
// Sharpens edges without amplifying noise or flat areas.
// Based on AMD CAS approach: compare pixel to neighbourhood,
// apply sharpening proportional to local contrast.
// ============================================================


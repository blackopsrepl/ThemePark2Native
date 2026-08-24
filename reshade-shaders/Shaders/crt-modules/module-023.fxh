// ============================================================
// Grain helpers (Marty METEOR inlined)
// ============================================================

uint grain_uhash(uint x) { x^=x>>16; x*=0x21f0aaad; x^=x>>15; x*=0xd35a2d97; x^=x>>16; return x; }
float  grain_unorm1(uint u) { return asfloat((u>>9u)|0x3F800000u)-1.0; }
float2 grain_unorm2(uint u) { return asfloat((uint2(u<<7u,u>>9u)&0x7FFF80u)|0x3F800000u)-1.0; }
float  grain_next1(inout uint r) { r=grain_uhash(r); return grain_unorm1(r); }
float2 grain_next2(inout uint r) { r=grain_uhash(r); return grain_unorm2(r); }
float3 grain_bm3(float3 u) { float2 d; sincos(u.x*6.2831853,d.y,d.x); d*=sqrt(-2.0*log(u.z)); return float3(d.x,d.y,d.x*d.y); }
float2 grain_boxmuller_2d(float2 u) { float2 d; sincos(u.x*6.2831853,d.y,d.x); d*=sqrt(-2.0*log(max(1.0-u.y,1e-6))); return d; }
#define GWP 15.0
float3 grain_hdr(float3 c) { float w=1+rcp(1e-6+GWP); return c/(w-c); }
float3 grain_sdr(float3 c) { float w=1+rcp(1e-6+GWP); return w*c*rcp(1+c); }
#define glin(x)  ((x)*0.283799*((2.52405+(x))*(x)))
#define genc(x)  (1.14374*(-0.126893*(x)+sqrt((x))))

// Analytical Poisson variance for film grain.
// Models highlight rolloff: grain peaks at midtones (luma=0.5) and rolls
// off in both shadows and highlights -- luma*(1-luma) peaks at 0.25 when luma=0.5.
float grain_poisson_sigma(float luma, float intensity)
{
    float poisson_shape = luma * (1.0 - luma);
    return (intensity * intensity * 0.35) * (poisson_shape * 4.0);
}

// Voronoi grain: scatter seed points, each pixel gets value of nearest seed.
// Creates genuine blob/cluster structure -- cannot be replicated by blurring noise.
// cell_size controls blob scale. Returns value in [-1, 1].
float grain_voronoi(float2 pos, float cell_size, uint frame_salt)
{
    float2 cell    = floor(pos / cell_size);
    float  min_d   = 1e9;
    float  val     = 0.0;

    // Check 3x3 neighbourhood of cells
    for (int cy = -1; cy <= 1; cy++)
    for (int cx = -1; cx <= 1; cx++)
    {
        float2 nc     = cell + float2(cx, cy);
        uint   seed   = grain_uhash(grain_uhash(uint(nc.y * 1031.0 + 7919.0))
                      + uint(nc.x * 3571.0 + 5003.0) + frame_salt);
        // Jitter seed point within cell
        float2 jitter = float2(grain_unorm1(seed),
                               grain_unorm1(grain_uhash(seed))) * 0.5 + 0.5;
        float2 sp     = (nc + jitter) * cell_size;
        float  d      = length(pos - sp);
        if (d < min_d)
        {
            min_d = d;
            // Value from seed -- Gaussian distributed for realistic amplitude
            float u1 = grain_unorm1(grain_uhash(seed + 1u));
            float u2 = grain_unorm1(grain_uhash(seed + 2u));
            val = sqrt(-2.0 * log(max(u1, 1e-6))) * cos(6.2831853 * u2);
        }
    }
    return val;
}

// Per-channel grain with physically correct layer sizes.
// Blue layer (top) is coarsest -- historically blue-sensitive grains are largest.
// Green is mid-size. Red (deepest layer) is finest.
// cell_scale: 1.0 = standard, >1 = coarser (higher ISO simulation).
float3 grain_emulsion(float2 pos, float cell_scale, uint frame_salt, float intensity, float luma)
{
    float amp = grain_poisson_sigma(luma, intensity);

    // Layer cell sizes -- ratios from typical colour negative emulsions
    // Multipliers kept close to 1.0 so cell_scale directly controls visible size
    float sz_b = cell_scale * 1.9; // blue: coarsest (top emulsion layer)
    float sz_g = cell_scale * 1.4; // green: mid layer
    float sz_r = cell_scale * 1.0; // red: finest (deepest layer)

    float gR = grain_voronoi(pos, sz_r, frame_salt)           * amp;
    float gG = grain_voronoi(pos, sz_g, frame_salt + 0x1111u) * amp;
    float gB = grain_voronoi(pos, sz_b, frame_salt + 0x2222u) * amp;

    // Highlight residual: small floor so highlights never go completely grain-free
    // Physically represents maximum silver density at Dmax
    float hl_floor = intensity * intensity * 0.015 * luma * luma;
    uint  hl_seed  = grain_uhash(grain_uhash(uint(pos.y)*7919u + uint(pos.x)) + frame_salt);
    float hl_noise = grain_unorm1(hl_seed) * 2.0 - 1.0;
    float hl_grain = hl_noise * hl_floor;

    return float3(gR + hl_grain, gG + hl_grain, gB + hl_grain);
}

// ============================================================
// Pass 1: Pre-blur horizontal
// Samples clean backbuffer, blurs horizontally.
// Equivalent to Guest Advanced SIZEH/SIGMA_H gaussian pass.
// ============================================================

#if ENABLE_PREBLUR
void crt_preblur_h_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float2 texcoord_w = geom_warp(texcoord);

    if (crt_preblur_h_sigma < 0.001)
    {
        color = float4(geom_sample_lanczos2(ReShade::BackBuffer, texcoord_w), 1.0);
        return;
    }

    float3 result = 0.0;
    float  wsum   = 0.0;
    float  px     = ReShade::PixelSize.x;
    int    radius = int(crt_preblur_h_radius);

    float3 centre_h   = geom_sample_lanczos2(ReShade::BackBuffer, texcoord_w);
    float3 centre_ycc = crt_rgb_to_ycbcr(centre_h);
    float  centre_Y   = centre_ycc.x;
    if (crt_preblur_luma_only)
    {
        // Blur Y channel only -- chroma from centre pixel preserved
        // Optional bilateral range weight on luma difference -- preserves edges
        float  y_result = 0.0;
        for (int i = -radius; i <= radius; i++)
        {
            float3 s   = (i == 0) ? centre_h
                : tex2D(ReShade::BackBuffer, texcoord_w + float2(float(i)*px, 0.0)).rgb;
            float  sY  = crt_rgb_to_ycbcr(s).x;
            float  ws  = gauss(float(i), crt_preblur_h_sigma);
            float  wr  = lerp(1.0, gauss(sY - centre_Y, 0.10), crt_preblur_bilateral);
            float  w   = ws * wr;
            y_result  += sY * w;
            wsum      += w;
        }
        color = float4(crt_ycbcr_to_rgb(float3(y_result / max(wsum, 1e-5),
                                                centre_ycc.y, centre_ycc.z)), 1.0);
    }
    else
    {
        for (int i = -radius; i <= radius; i++)
        {
            float3 s   = (i == 0) ? centre_h
                : tex2D(ReShade::BackBuffer, texcoord_w + float2(float(i)*px, 0.0)).rgb;
            float  sY  = crt_rgb_to_ycbcr(s).x;
            float  ws  = gauss(float(i), crt_preblur_h_sigma);
            float  wr  = lerp(1.0, gauss(sY - centre_Y, 0.10), crt_preblur_bilateral);
            float  w   = ws * wr;
            result    += s * w;
            wsum      += w;
        }
        color = float4(result / max(wsum, 1e-5), 1.0);
    }
}
#endif

// ============================================================
// Pass 2: Pre-blur vertical
// Samples H-blurred texture, blurs vertically.
// Equivalent to Guest Advanced SIZEV/SIGMA_V gaussian pass.
// ============================================================

#if ENABLE_PREBLUR
void crt_preblur_v_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    if (crt_preblur_v_sigma < 0.001)
    {
        color = tex2D(crt_preblur_h_sampler, texcoord);
        return;
    }

    float3 result = 0.0;
    float  wsum   = 0.0;
    float  py     = ReShade::PixelSize.y * float(PREBLUR_RESOLUTION);
    int    radius = int(crt_preblur_v_radius);

    float3 centre_v   = tex2D(crt_preblur_h_sampler, texcoord).rgb;
    float3 centre_ycc_v = crt_rgb_to_ycbcr(centre_v);
    float  centre_Yv  = centre_ycc_v.x;
    if (crt_preblur_luma_only)
    {
        // Blur Y channel only -- bilateral range weight optional
        float  y_result = 0.0;
        for (int j = -radius; j <= radius; j++)
        {
            float3 s   = tex2D(crt_preblur_h_sampler, texcoord + float2(0.0, float(j)*py)).rgb;
            float  sY  = crt_rgb_to_ycbcr(s).x;
            float  ws  = gauss(float(j), crt_preblur_v_sigma);
            float  wr  = lerp(1.0, gauss(sY - centre_Yv, 0.10), crt_preblur_bilateral);
            float  w   = ws * wr;
            y_result  += sY * w;
            wsum      += w;
        }
        color = float4(crt_ycbcr_to_rgb(float3(y_result / max(wsum, 1e-5),
                                                centre_ycc_v.y, centre_ycc_v.z)), 1.0);
    }
    else
    {
        for (int j = -radius; j <= radius; j++)
        {
            float3 s   = tex2D(crt_preblur_h_sampler, texcoord + float2(0.0, float(j)*py)).rgb;
            float  sY  = crt_rgb_to_ycbcr(s).x;
            float  ws  = gauss(float(j), crt_preblur_v_sigma);
            float  wr  = lerp(1.0, gauss(sY - centre_Yv, 0.10), crt_preblur_bilateral);
            float  w   = ws * wr;
            result    += s * w;
            wsum      += w;
        }
        color = float4(result / max(wsum, 1e-5), 1.0);
    }
}
#endif

// ============================================================
// Pass 3: Halation (bright-only blur at quarter resolution)
// Only bright elements scatter -- no global haze.
// Bilinear sampling of the quarter-res texture in main pass
// gives free additional smoothing.
// ============================================================

#if ENABLE_HALATION
void crt_halation_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 result = 0.0;
    float  wsum   = 0.0;
    // Pixel size scaled by resolution divisor
    float  px     = ReShade::PixelSize.x * float(HALATION_RESOLUTION);
    int    radius = int(crt_halation_radius);

    for (int i = -radius; i <= radius; i++)
    {
        #if ENABLE_PREBLUR
        float3 s = tex2D(crt_preblur_v_sampler, texcoord + float2(float(i)*px, 0.0)).rgb;
        #elif ENABLE_GEOMETRY
        float  px_bb = ReShade::PixelSize.x;
        float2 uv_hal = geom_warp(texcoord) + float2(float(i)*px_bb, 0.0);
        float3 s = tex2D(ReShade::BackBuffer, uv_hal).rgb;
        #else
        float  px_bb = ReShade::PixelSize.x;
        float2 uv_hal = texcoord + float2(float(i)*px_bb, 0.0);
        float3 s = tex2D(ReShade::BackBuffer, uv_hal).rgb;
        #endif

        float luma  = dot(s, float3(0.2126, 0.7152, 0.0722));
        float above = max(luma - crt_halation_threshold, 0.0);
        // Warm target: lerp between neutral white and warm orange-red.
        // crt_halation_warmth=0 -> (1,1,1)*luma (neutral white desaturation)
        // crt_halation_warmth=1 -> (1.08,0.95,0.82)*luma (warm CRT phosphor tint)
        float3 warm_tint = lerp(float3(1.0, 1.0, 1.0),
                                float3(1.08, 0.95, 0.82),
                                crt_halation_warmth) * luma;
        s = lerp(s, warm_tint, crt_halation_saturation) * (above / max(luma, 0.0001));

        // sigma_h = sigma * anisotropy -- wider H spread when anisotropy > 1
        float w = gauss(float(i), crt_halation_sigma * max(crt_halation_anisotropy, 0.01));
        result += s * w;
        wsum   += w;
    }

    color = float4(result / max(wsum, 1e-5), 1.0);
}


// Vertical halation pass: blurs the horizontal result vertically.
// sigma_v = sigma / anisotropy -- narrower when anisotropy > 1 (wider H than V).
void crt_halation_v_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 result = 0.0;
    float  wsum   = 0.0;
    float  py     = ReShade::PixelSize.y * float(HALATION_RESOLUTION);
    int    radius = int(crt_halation_radius);
    float  sigma_v = crt_halation_sigma / max(crt_halation_anisotropy, 0.01);

    for (int j = -radius; j <= radius; j++)
    {
        float3 s = tex2D(crt_halation_sampler, texcoord + float2(0.0, float(j)*py)).rgb;
        float w = gauss(float(j), sigma_v);
        result += s * w;
        wsum   += w;
    }
    color = float4(result / max(wsum, 1e-5), 1.0);
}
#endif


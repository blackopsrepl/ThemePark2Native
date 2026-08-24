#if ENABLE_GEOMETRY
    if (crt_geom_mode == 0) return tc;

    float ar = float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);
    float2 uv = (tc * 2.0 - 1.0) / crt_geom_zoom;
    uv.x *= ar;

    float cv = crt_geom_curvature;

    if (crt_geom_mode == 1)
    {
        uv.x *= 1.0 + (uv.y * uv.y) / (cv * cv);
        uv.y *= 1.0 + (uv.x * uv.x) / (cv * cv * ar * ar);
    }
    else if (crt_geom_mode == 2)
    {
        uv.x *= 1.0 + pow(abs(uv.y) / cv, 1.5);
        uv.y *= 1.0 + pow(abs(uv.x) / (cv * ar), 1.5);
    }
    else
    {
        uv.x *= 1.0 + (uv.y * uv.y) / (cv * cv);
    }

    uv.x /= ar;
    return clamp(uv * 0.5 + 0.5, 0.0, 1.0);
#else
    return tc;
#endif
}

// ============================================================
// Lanczos2 kernel: 2-lobe sinc approximation
// Sharper reconstruction than bilinear -- significantly reduces
// the softening introduced by the geometry UV warp.
// 4x4 tap grid (16 samples) centred on the warped texcoord.
// ============================================================
// ── Reconstruction filter functions ─────────────────────────────
// Used by pre-blur and geometry warp sampling.
// Selected by PREBLUR_FILTER: 0=Lanczos2, 1=Lanczos3, 2=Catmull-Rom

// Lanczos: sinc(x)*sinc(x/a), a = lobe count (2 or 3)
float lanczos_weight(float x, float a)
{
    const float PI = 3.14159265358979;
    if (abs(x) < 0.0001) return 1.0;
    if (abs(x) >= a)     return 0.0;
    float px  = PI * x;
    float pxa = PI * x / a;
    return (sin(px) / px) * (sin(pxa) / pxa);
}

// Catmull-Rom: piecewise cubic spline, 4-tap support [-2,2]
// Slightly crisper than Lanczos2 on high-contrast edges with less ringing.
float catmull_rom_weight(float x)
{
    x = abs(x);
    if (x >= 2.0) return 0.0;
    if (x >= 1.0) return ((-0.5*x + 2.5)*x - 4.0)*x + 2.0;
    return ((1.5*x - 2.5)*x*x + 1.0);
}

// Legacy alias
float lanczos2_weight(float x) { return lanczos_weight(x, 2.0); }

// Unified reconstruction sampler -- switches on PREBLUR_FILTER
float recon_weight(float x)
{
#if PREBLUR_FILTER == 2
    return catmull_rom_weight(x);
#elif PREBLUR_FILTER == 1
    return lanczos_weight(x, 3.0);
#else
    return lanczos_weight(x, 2.0);
#endif
}

float3 geom_sample_lanczos2(sampler2D tex, float2 tc)
{
    float2 px      = ReShade::PixelSize;
    float2 tc_px   = tc / px;
    float2 tc_base = floor(tc_px);

    // Tap radius: 2 for Lanczos2/Catmull-Rom (4x4=16 taps),
    //             3 for Lanczos3 (6x6=36 taps)
#if PREBLUR_FILTER == 1
    const int r = 3;
#else
    const int r = 2;
#endif

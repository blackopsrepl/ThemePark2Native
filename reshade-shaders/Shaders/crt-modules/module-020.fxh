
// Colour temperature: warm/cool shift relative to D65
// Uses a cross-channel matrix approach similar to Megatron's white balance.
// Negative = warm (less blue, more red), positive = cool (more blue, less red).
// Applied in linear space, luminance-preserving via per-channel scaling.
float3 apply_colour_temp(float3 c, float temp)
{
    if (abs(temp) < 0.001) return c;

    // D65 reference RGB multipliers for warm (-1) and cool (+1) extremes
    // Derived from Kelvin approximation: warm~2700K, cool~12000K
    // These multipliers are relative to D65 (1,1,1)
    float3 warm = float3(1.12, 1.00, 0.72); // ~3200K relative to D65
    float3 cool = float3(0.82, 0.97, 1.22); // ~9000K relative to D65

    float3 wb = (temp < 0.0)
        ? lerp(float3(1.0, 1.0, 1.0), warm, -temp)
        : lerp(float3(1.0, 1.0, 1.0), cool,  temp);

    float3 shifted = c * wb;

    // Preserve luminance so temperature shift doesn't change brightness
    float luma_before = dot(max(c,       0.0), float3(0.2126, 0.7152, 0.0722));
    float luma_after  = dot(max(shifted, 0.0), float3(0.2126, 0.7152, 0.0722));
    shifted = (luma_after > 0.0001) ? shifted * (luma_before / luma_after) : shifted;

    return shifted;
}

float3 apply_bcs(float3 c, float brightness, float contrast, float saturation)
{
#if LINEAR_HDR_INPUT
    // --------------------------------------------------------
    // Linear HDR path (Luma / raw scRGB)
    // Avoids XYZ/Yxy matrix math which breaks when channel
    // values are >> 1.0. Operates directly in linear RGB.
    // Brightness/contrast use luma-normalised curves so
    // hue is preserved. Saturation is a simple luma lerp.
    // --------------------------------------------------------
    // Normalise against display peak so BCS never pushes above peak nits
    // LINEAR_HDR_PEAK = display_peak_nits / 80 (scRGB units)
    float3 c_safe  = max(c, 0.0);
    float  luma_in = dot(c_safe, float3(0.2126, 0.7152, 0.0722));

    // Use peak nits ceiling as normalisation reference
    // This ensures Bezier operates on [0,1] relative to display peak
    // and the reconstruction cannot exceed that peak
    float  L_ref  = float(LINEAR_HDR_PEAK_NITS) / 80.0; // convert nits to scRGB units
    float  L_norm = luma_in / L_ref;
    float  L_g    = pow(clamp(L_norm, 0.0, 1.0), 1.0/2.4);

    float L_b = (brightness >= 0.0)
        ? Bezier(L_g, lerp(kMidBrightness, kTopBrightness, brightness))
        : Bezier(L_g, lerp(kMidBrightness, kBotBrightness, -brightness));
    float L_c = (contrast >= 0.0)
        ? Bezier(L_b, lerp(kMidContrast, kTopContrast, contrast))
        : Bezier(L_b, lerp(kMidContrast, kBotContrast, -contrast));

    float L_out = pow(max(L_c, 0.0), 2.4) * L_ref;

    // Scale RGB by luma ratio to preserve hue
    float3 rgb = (luma_in > 0.0001) ? c_safe * (L_out / luma_in) : c_safe;

    // Saturation: lerp toward luma, clamped to display peak
    float  sat = 0.5 + saturation * 0.5;
    rgb = lerp(L_out, rgb, sat * 2.0);
    rgb = min(rgb, L_ref); // hard ceiling at display peak

    return rgb;

#else
    // --------------------------------------------------------
    // Standard path (Soop sandwich, SDR, or gamma-encoded)
    // Hybrid: XYZ/Yxy chromaticity separation for perceptual accuracy,
    // but normalisation uses max channel instead of CIE Y.
    // This prevents blue-dominant scenes from being under-normalised
    // (CIE Y weights blue at only 7.2%, max channel is colour-agnostic).
    // Chromaticity (x,y) is still preserved from Yxy so hue is accurate.
    // --------------------------------------------------------
    float3 xyz = mul(k709_to_XYZ, c);
    float3 Yxy = XYZtoYxy(xyz);

    // Use max channel as luminance reference -- colour-agnostic,
    // correctly handles blue/cyan dominant content
    float ch_max  = max(max(c.r, c.g), c.b);
    float Y_lin   = max(ch_max, 0.0);
    float Y_peak  = max(Y_lin, 1.0);
    float Y_norm  = Y_lin / Y_peak;
    float Y_g     = pow(Y_norm, 1.0/2.4);

    float Y_b = (brightness >= 0.0)
        ? Bezier(Y_g, lerp(kMidBrightness, kTopBrightness, brightness))
        : Bezier(Y_g, lerp(kMidBrightness, kBotBrightness, -brightness));
    float Y_c = (contrast >= 0.0)
        ? Bezier(Y_b, lerp(kMidContrast, kTopContrast, contrast))
        : Bezier(Y_b, lerp(kMidContrast, kBotContrast, -contrast));

    float Y_out   = pow(max(Y_c, 0.0), 2.4) * Y_peak;

    // Scale input RGB by the ratio of new to old max channel
    float3 rgb = (Y_lin > 0.0001) ? c * (Y_out / Y_lin) : c;

    // Clamp negatives -- wide-gamut content (DCI-P3, BT.2020) can produce
    // negative Rec.709 values after the XYZ round-trip. A zero floor prevents
    // downstream inversion without affecting in-gamut content.
    rgb = max(rgb, 0.0);

#if BCS_GAMUT_CLAMP
    rgb = clamp(rgb, 0.0, 1.0);
#endif

    float  luma  = dot(rgb, float3(0.2125, 0.7154, 0.0721));
    float  sat   = 0.5 + saturation * 0.5;
    rgb = lerp(luma, rgb, sat * 2.0);
    rgb = max(rgb, 0.0); // guard saturation lerp against negative luma

    return rgb;
#endif
}

// YCbCr helpers for luma-only preblur
// BT.601 coefficients -- perceptually correct for CRT content
float3 crt_rgb_to_ycbcr(float3 rgb)
{
    float Y  =  0.2990 * rgb.r + 0.5870 * rgb.g + 0.1140 * rgb.b;
    float Cb = -0.1687 * rgb.r - 0.3313 * rgb.g + 0.5000 * rgb.b;
    float Cr =  0.5000 * rgb.r - 0.4187 * rgb.g - 0.0813 * rgb.b;
    return float3(Y, Cb, Cr);
}

float3 crt_ycbcr_to_rgb(float3 ycbcr)
{
    float Y = ycbcr.x, Cb = ycbcr.y, Cr = ycbcr.z;
    return float3(
        Y                + 1.4020 * Cr,
        Y - 0.3441 * Cb  - 0.7141 * Cr,
        Y + 1.7720 * Cb);
}

// ============================================================
// Gamma helpers
// ============================================================

float3 to_linear(float3 x)   { return x < 0.04045 ? x/12.92 : pow((x+0.055)/1.055, 2.4); }
float3 from_linear(float3 x) { return x < 0.0031308 ? 12.92*x : 1.055*pow(max(x,0.0),1.0/2.4)-0.055; }
float3 crt_to_linear(float3 x)   { return pow(max(x, 0.0), crt_gamma_in); }
float3 crt_from_linear(float3 x) { return pow(max(x, 0.0), 1.0/crt_gamma_out); }

// ============================================================
// Gaussian helper
// ============================================================

float gauss(float x, float sigma)
{
    return exp(-(x*x) / (2.0*sigma*sigma));
}

// Fast erf approximation (Abramowitz & Stegun 7.1.26, max error 1.5e-7)
float crt_erf(float x)
{
    float t = 1.0 / (1.0 + 0.3275911 * abs(x));
    float p = t * (0.254829592
              + t * (-0.284496736
              + t * (1.421413741
              + t * (-1.453152027
              + t *  1.061405429))));
    return sign(x) * (1.0 - p * exp(-(x*x)));
}

// Analytically integrate Gaussian over pixel footprint [f-hw, f+hw].
// Eliminates stairstepping at any subpixel position.
float gauss_integral(float f, float hw, float sigma)
{
    // Guarded to match gen_gauss_integral's quadrature path. Reachable sigma
    // never gets near zero today (slider minimum 0.05, scaled by factors that
    // stay above ~0.12), but the two paths should defend identically.
    float s = max(sigma * 1.41421356, 0.0001); // sigma * sqrt(2)
    return 0.5 * (crt_erf((f + hw) / s) - crt_erf((f - hw) / s));
}

// Generalized Gaussian integral over pixel footprint [f-hw, f+hw].
// gen_gauss(x, sigma, n) = exp(-(|x|/(sigma*sqrt2))^n), normalised so that
// n=2 is exactly the standard Gaussian used by the erf path.
// For n=2: takes the fast erf path (exact, and matches the quadrature form).
// For n!=2: 16-point Gauss-Legendre quadrature (8 symmetric pairs).
// 4-point GL fails badly when sigma << hw (e.g. sigma=0.05, tight beam)
// because the narrow spike is missed by coarse nodes -- 85% error at n=8.
// 16-point GL gives < 3% error even at sigma=0.05, n=8.
// Shape n>2 produces flatter scanline plateau and steeper dark gap transition,
// matching real well-focused CRT beam cross-sections.
float gen_gauss_integral(float f, float hw, float sigma, float n)
{
    if (abs(n - 2.0) < 0.05)
    {
        // n=2: exact erf path (fast)
        return gauss_integral(f, hw, sigma);
    }

    // Match the n==2 erf path exactly. That path integrates the standard
    // normal exp(-x^2/(2*sigma^2)); writing the generalized form as
    // exp(-(|x|/(sigma*sqrt2))^n) makes n=2 reduce to precisely that, so the
    // two branches agree at the threshold instead of the quadrature kernel
    // being narrower by sqrt(2) (which caused a brightness/width step of up
    // to -28% when Beam Shape crossed 2.05).
    float inv_sigma = 1.0 / max(sigma * 1.41421356, 0.0001);
    float s = 1.0 / (sigma * sqrt(2.0 * 3.14159265)); // normalisation

    // 16-point GL nodes and weights (8 symmetric pairs on [-1,1])
    static const float nd[8] = {
        0.0950125098, 0.2816035508, 0.4580167777, 0.6178762444,
        0.7554044084, 0.8656312024, 0.9445750231, 0.9894009350
    };
    static const float wt[8] = {
        0.1894506105, 0.1826034150, 0.1691565194, 0.1495959889,
        0.1246289863, 0.0951585117, 0.0622535239, 0.0271524594
    };

    float v = 0.0;
    [unroll] for (int i = 0; i < 8; i++)
    {
        float tp = f + hw * nd[i];
        float tn = f - hw * nd[i];
        v += wt[i] * (exp(-pow(max(abs(tp) * inv_sigma, 0.0), n))
                    + exp(-pow(max(abs(tn) * inv_sigma, 0.0), n)));
    }

    return v * hw * s;
}

// Per-scanline brightness variation.
// Spatially correlated low-frequency hash -- adjacent rows similar, not random.
// Models HV supply ripple + phosphor coating unevenness in real CRTs.
// Standalone integer hash -- used by crt_scanline_roll independently of ENABLE_GRAIN
uint crt_row_hash(uint x)
{
    x ^= x >> 16u;
    x *= 0x45D9F3Bu;
    x ^= x >> 16u;
    return x;
}

float crt_scanline_roll(float row)
{
    // Per-row hash with slight spatial correlation to adjacent rows.
    // Models real CRT HV supply ripple -- each scanline independently varies,
    // with neighbours similar but not identical (short-range correlation).
    // Much higher frequency than sine waves -- matches actual tube behaviour.
    float r = floor(row);

    uint  seed0 = crt_row_hash(uint(r));
    uint  seed1 = crt_row_hash(uint(r + 1.0));
    uint  seedm = crt_row_hash(uint(r - 1.0));

    float v0 = float(seed0 & 0xFFFFu) / 32767.5 - 1.0;
    float v1 = float(seed1 & 0xFFFFu) / 32767.5 - 1.0;
    float vm = float(seedm & 0xFFFFu) / 32767.5 - 1.0;

    // Weighted average: 50% current row, 25% each neighbour
    return v0 * 0.5 + (v1 + vm) * 0.25;
}

// ============================================================
// Geometry warp: pincushion UV distortion applied at source
// sampling to keep scanlines/mask geometrically straight.
// ============================================================

// Compute warped texcoord only -- no sampling
float2 geom_warp(float2 tc)
{

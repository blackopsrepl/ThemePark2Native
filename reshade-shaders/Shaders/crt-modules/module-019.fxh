#if ENABLE_HALATION
texture2D crt_halation_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH  / HALATION_RESOLUTION;
    Height = BUFFER_HEIGHT / HALATION_RESOLUTION;
    Format = RGBA16F;
};
sampler2D crt_halation_sampler
{
    Texture   = crt_halation_tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
};
// Vertical halation pass output (anisotropy support)
texture2D crt_halation_v_tex < pooled = false; >
{
    Width  = BUFFER_WIDTH  / HALATION_RESOLUTION;
    Height = BUFFER_HEIGHT / HALATION_RESOLUTION;
    Format = RGBA16F;
};
sampler2D crt_halation_v_sampler
{
    Texture   = crt_halation_v_tex;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
};
#endif

// ============================================================
// Megatron cubic Bezier
// ============================================================

static const float4x4 kCubicBezier = float4x4(
     1.0f,  0.0f,  0.0f,  0.0f,
    -3.0f,  3.0f,  0.0f,  0.0f,
     3.0f, -6.0f,  3.0f,  0.0f,
    -1.0f,  3.0f, -3.0f,  1.0f);

float Bezier(float t, float4 cp)
{
    float4 tv = float4(1.0, t, t*t, t*t*t);
    return dot(tv, mul(kCubicBezier, cp));
}

// ============================================================
// Pipeline: Soop-compatible HDR sandwich functions
// Ported from smolbbsoop by Violet Cleathero (MIT)
// Modified: runtime peak_nits and shadow_gamma uniforms
// ============================================================

#if PIPELINE >= 1

// PQ constants for HDR10
#define PQ_m1 0.1593017578125
#define PQ_m2 78.84375
#define PQ_c1 0.8359375
#define PQ_c2 18.8515625
#define PQ_c3 18.6875

float3 soop_srgb_to_linear(float3 x)
{
    return x < 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4);
}
float3 soop_linear_to_srgb(float3 x)
{
    return x < 0.0031308 ? 12.92 * x : 1.055 * pow(max(x, 0.0), 1.0 / 2.4) - 0.055;
}

// scRGB Reinhard forward (Before pass)
float3 soop_reinhard(float3 x, float peak_nits, float shadow_gamma)
{
    float W = peak_nits / 80.0; // scRGB peak
    x = pow(max(x, 0.0), 1.0 / shadow_gamma);
    return (x * (1.0 + x / (W * W))) / (1.0 + x);
}

// scRGB Inverse Reinhard (After pass)
float3 soop_inv_reinhard(float3 x, float shadow_gamma)
{
    x = clamp(x, 0.0, 1.0);
    float maxCh = max(max(x.r, x.g), x.b);
    if (maxCh >= 1.0) x *= (0.9999 / maxCh);
    x = x / (1.0 - x);
    return pow(max(x, 0.0), shadow_gamma);
}

#if PIPELINE == 2
// HDR10 PQ decode to linear
float3 soop_pq_to_linear(float3 x, float content_peak_nits)
{
    float3 xpow = pow(max(x, 0.0), 1.0 / PQ_m2);
    float3 num  = max(xpow - PQ_c1, 0.0);
    float3 den  = max(PQ_c2 - PQ_c3 * xpow, 1e-10);
    float  S    = 20375.99 * pow(content_peak_nits, -0.995);
    return pow(num / den, 1.0 / PQ_m1) * S;
}

// Linear to HDR10 PQ encode
float3 soop_linear_to_pq(float3 x, float content_peak_nits)
{
    float  S       = 0.003789 * content_peak_nits;
    float3 x_sc    = x * S;
    float3 Y       = clamp(x_sc / 80.0, 0.0, 1.0);
    float3 Ym1     = pow(Y, PQ_m1);
    float3 num     = PQ_c1 + PQ_c2 * Ym1;
    float3 den     = 1.0 + PQ_c3 * Ym1;
    return pow(num / den, PQ_m2);
}

// HDR10 simple Reinhard (no white point -- HDR10 path is already in linear after decode)
float3 soop_reinhard_simple(float3 x)
{
    return x / (1.0 + x);
}
float3 soop_inv_reinhard_simple(float3 x)
{
    x = clamp(x, 0.0, 1.0);
    return x / (1.0 - x);
}
#endif // PIPELINE == 2

#endif // PIPELINE >= 1

// ============================================================
// Phosphor profile correction
// Matrices from Guest Advanced CRT (guest.r, GPL)
// RGB->XYZ input matrices (CRT phosphor primaries)
// XYZ->RGB output matrices (display gamut)
// ============================================================

#if ENABLE_PHOSPHOR
// ── Phosphor input matrices: RGB -> XYZ ─────────────────────────────────────
// Each matrix converts from the CRT's native phosphor primaries to CIE XYZ.
// All computed from CIE xy chromaticity coordinates via the standard method:
// M = [R|G|B] * diag(solve([R|G|B], W)) where R,G,B are primary XYZ columns
// and W is the white point XYZ.
// White point is D65 (x=0.3127, y=0.3290) unless noted.
//
// Profile            R_xy        G_xy        B_xy        White
// EBU (PAL)         0.640,0.330 0.290,0.600 0.150,0.060 D65
// P22               0.625,0.340 0.280,0.595 0.155,0.070 D65
// SMPTE-C / BVM-D   0.630,0.340 0.310,0.595 0.155,0.070 D65
// Trinitron         0.621,0.341 0.295,0.605 0.150,0.063 D65 (measured)
// NTSC 1953         0.670,0.330 0.210,0.710 0.140,0.080 Illum C (x=0.3101,y=0.3162)
// NTSC 1953 D93     0.670,0.330 0.210,0.710 0.140,0.080 D93 (x=0.2848,y=0.2932)

// EBU (PAL) -- European Broadcasting Union Tech 3213.
// Used by PAL CRTs from 1970s onwards. Green slightly more yellow than sRGB.
static const float3x3 kPhosphor_EBU     = float3x3(0.430554,0.222004,0.020182, 0.341550,0.706655,0.129553, 0.178352,0.071341,0.939322);

// P22 -- common US consumer CRT phosphor set (ca. 1970s-90s NTSC sets).
// Slightly warmer red, cooler green than EBU.
static const float3x3 kPhosphor_P22     = float3x3(0.449662,0.244616,0.025181, 0.316256,0.672044,0.141186, 0.184538,0.083340,0.922691);

// SMPTE-C (1987) -- North American broadcast standard, also used by Sony BVM-D
// broadcast reference monitors and Philips European CRTs (same chromaticities).
// Most PS1/PS2/N64 era games were mastered on BVM-D.
static const float3x3 kPhosphor_SMPTEC  = float3x3(0.393521,0.212376,0.018739, 0.365258,0.701060,0.111934, 0.191677,0.086564,0.958385);

// Sony Trinitron -- measured phosphor chromaticities from Trinitron tubes.
// Slightly more saturated green, deeper blue than standard EBU.
static const float3x3 kPhosphor_Trinitron = float3x3(0.435625,0.239208,0.026657, 0.333914,0.684807,0.113191, 0.180917,0.075985,0.949210);

// NTSC 1953 -- original FCC NTSC specification with Illuminant C white point.
// Very wide gamut (especially saturated reds and greens), but Illuminant C
// white (~6774K) is warmer than D65. The widest gamut CRT standard.
// Games did NOT target this -- it reflects early 1950s TV receiver phosphors.
static const float3x3 kPhosphor_NTSC1953 = float3x3(0.606937,0.298939,0.000000, 0.173509,0.586625,0.066099, 0.200263,0.114436,1.115748);

// NTSC 1953 at D93 white point -- Japanese CRT monitors (~9300K).
// Japan never adopted SMPTE-C, continuing to use 1953 NTSC primaries
// but with a cooler 9300K white point standard. Very blue whites.
// Most relevant for SNES, Mega Drive, and Saturn era content as seen
// in Japan on consumer CRTs of that period.
static const float3x3 kPhosphor_NTSC1953_D93 = float3x3(0.551060,0.271418,0.000000, 0.173843,0.587755,0.066226, 0.246448,0.140827,1.373065);

// ── Display output matrices: XYZ -> RGB ─────────────────────────────────────
// Output: XYZ -> RGB for each display gamut
static const float3x3 kGamut_sRGB    = float3x3( 3.240970,-0.969244, 0.055630,-1.537383, 1.875968,-0.203977,-0.498611, 0.041555, 1.056972);
static const float3x3 kGamut_Modern  = float3x3( 2.791723,-0.894766, 0.041678,-1.173165, 1.815586,-0.130886,-0.440973, 0.032000, 1.002034);
static const float3x3 kGamut_DCI     = float3x3( 2.493497,-0.829489, 0.035846,-0.931384, 1.762664,-0.076172,-0.402711, 0.023625, 0.956885);
static const float3x3 kGamut_Adobe   = float3x3( 2.041588,-0.969244, 0.013444,-0.565007, 1.875968,-0.118360,-0.344731, 0.041555, 1.015175);
static const float3x3 kGamut_Rec2020 = float3x3( 1.716651,-0.666684, 0.017640,-0.355671, 1.616481,-0.042771,-0.253366, 0.015769, 0.942103);

float3 apply_phosphor(float3 c)
{
    // Select input phosphor matrix (CRT primaries -> XYZ)
    float3x3 m_in;
    if      (crt_phosphor_profile == 0) m_in = kPhosphor_EBU;
    else if (crt_phosphor_profile == 1) m_in = kPhosphor_P22;
    else if (crt_phosphor_profile == 2) m_in = kPhosphor_SMPTEC;
    else if (crt_phosphor_profile == 3) m_in = kPhosphor_Trinitron;
    else if (crt_phosphor_profile == 4) m_in = kPhosphor_NTSC1953;
    else                                m_in = kPhosphor_NTSC1953_D93;

    // Select output display gamut matrix (XYZ -> display RGB)
    float3x3 m_out;
    if      (crt_display_gamut == 0) m_out = kGamut_sRGB;
    else if (crt_display_gamut == 1) m_out = kGamut_Modern;
    else if (crt_display_gamut == 2) m_out = kGamut_DCI;
    else if (crt_display_gamut == 3) m_out = kGamut_Adobe;
    else                             m_out = kGamut_Rec2020;

    // Decode to linear using sRGB piecewise TRC (correct IEC 61966-2-1).
    // Defined inline because glin/genc macros are not yet in scope here.
    // sRGB decode: linear = c/12.92 if c <= 0.04045, else ((c+0.055)/1.055)^2.4
    float3 c_lin = (c <= 0.04045)
                 ? c / 12.92
                 : pow((c + 0.055) / 1.055, 2.4);
    float3 xyz   = mul(c_lin, m_in);   // CRT phosphor RGB -> XYZ
    float3 rgb   = mul(xyz,   m_out);  // XYZ -> display RGB
    // sRGB encode: c/12.92 if linear <= 0.0031308, else 1.055*linear^(1/2.4)-0.055
    float3 rgb_s = max(rgb, 0.0);
    float3 c_out = (rgb_s <= 0.0031308)
                 ? rgb_s * 12.92
                 : 1.055 * pow(rgb_s, 1.0/2.4) - 0.055;

    return lerp(c, c_out, crt_phosphor_strength);
}
#endif

// ============================================================
// Colour temperature chromatic adaptation (D65 to D55 / D93)
// Matrices from CRT Guest Advanced (GPL v2+)
// ============================================================
#if ENABLE_PHOSPHOR
static const float3x3 kD65_to_D55 = float3x3(
    0.485034, 0.250096, 0.022736,
    0.348896, 0.697791, 0.116299,
    0.130282, 0.052113, 0.686154);

static const float3x3 kD65_to_D93 = float3x3(
    0.341275, 0.175970, 0.015997,
    0.364617, 0.729234, 0.121539,
    0.236989, 0.094796, 1.248144);

// Standard XYZ to sRGB (D65) for colour temperature output re-encoding
static const float3x3 kXYZ_to_sRGB = float3x3(
     3.240970,-1.537383,-0.498611,
    -0.969244, 1.875968, 0.041555,
     0.055630,-0.203977, 1.056972);
#endif

// ============================================================
// Hue rotation helper (for magnetic interference)
// ============================================================
float3 hue_rotate(float3 c, float angle)
{
    // Rotate hue by angle (radians) using RGB rotation matrix
    float s = sin(angle);
    float cs = cos(angle);
    float3x3 m = float3x3(
        cs + (1.0-cs)/3.0,        (1.0-cs)/3.0 - s*0.57735, (1.0-cs)/3.0 + s*0.57735,
        (1.0-cs)/3.0 + s*0.57735, cs + (1.0-cs)/3.0,         (1.0-cs)/3.0 - s*0.57735,
        (1.0-cs)/3.0 - s*0.57735, (1.0-cs)/3.0 + s*0.57735,  cs + (1.0-cs)/3.0);
    return max(mul(c, m), 0.0);
}

// ============================================================
// Megatron BCS in Yxy space
// ============================================================

static const float4 kTopBrightness = float4(0.0, 1.0, 1.0, 1.0);
static const float4 kMidBrightness = float4(0.0, 1.0/3.0, 2.0/3.0, 1.0);
static const float4 kBotBrightness = float4(0.0, 0.0, 0.0, 1.0);
static const float4 kTopContrast   = float4(0.0, 0.0, 1.0, 1.0);
static const float4 kMidContrast   = float4(0.0, 1.0/3.0, 2.0/3.0, 1.0);
static const float4 kBotContrast   = float4(0.0, 1.0, 0.0, 1.0);

static const float3x3 kXYZ_to_709 = float3x3(
     3.240970, -1.537383, -0.498611,
    -0.969244,  1.875968,  0.041555,
     0.055630, -0.203977,  1.056972);
static const float3x3 k709_to_XYZ = float3x3(
    0.412391, 0.357584, 0.180481,
    0.212639, 0.715169, 0.072192,
    0.019331, 0.119195, 0.950532);

float3 XYZtoYxy(float3 XYZ)
{
    float s = XYZ.r + XYZ.g + XYZ.b;
    return float3(XYZ.g, (s<=0.0)?0.3805:XYZ.r/s, (s<=0.0)?0.3769:XYZ.g/s);
}
float3 YxytoXYZ(float3 Yxy)
{
    float Xs = Yxy.r * (Yxy.g / max(Yxy.b, 1e-5));
    float nz = (Yxy.r <= 0.0) ? 0.0 : 1.0;
    return float3(nz,nz,nz) * float3(Xs, Yxy.r, (Xs/max(Yxy.g,1e-5)) - Xs - Yxy.r);
}

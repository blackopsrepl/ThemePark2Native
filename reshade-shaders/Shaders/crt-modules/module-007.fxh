
// ---- Method 0: Oklab ------------------------------------------------
static const float3x3 CRT_OKLAB_M1 = float3x3(
    0.4122214708, 0.5363325363, 0.0514459929,
    0.2119034982, 0.6806995451, 0.1073969566,
    0.0883024619, 0.2817188376, 0.6299787005
);
static const float3x3 CRT_OKLAB_M2 = float3x3(
     0.2104542553,  0.7936177850, -0.0040720468,
     1.9779984951, -2.4285922050,  0.4505937099,
     0.0259040371,  0.7827717662, -0.8086757660
);
static const float3x3 CRT_OKLAB_M1_INV = float3x3(
     4.0767416621, -3.3077115913,  0.2309699292,
    -1.2684380046,  2.6097574011, -0.3413193965,
    -0.0041960863, -0.7034186147,  1.7076147010
);
static const float3x3 CRT_OKLAB_M2_INV = float3x3(
    1.0000000000,  0.3963377774,  0.2158037573,
    1.0000000000, -0.1055613458, -0.0638541728,
    1.0000000000, -0.0894841775, -1.2914855480
);

float3 crt_linear_to_oklab(float3 c)
{
    float3 lms = mul(CRT_OKLAB_M1, max(c, 0.0));
    lms = pow(max(lms, 0.0), 0.333333);
    return mul(CRT_OKLAB_M2, lms);
}

float3 crt_oklab_to_linear(float3 lab)
{
    float3 lms = mul(CRT_OKLAB_M2_INV, lab);
    lms = lms * lms * lms;
    return mul(CRT_OKLAB_M1_INV, max(lms, 0.0));
}

float3 crt_gamut_expand_oklab(float3 lin, float strength, float neutral, float skin)
{
    float3 lab   = crt_linear_to_oklab(lin);
    float  chroma = sqrt(lab.y*lab.y + lab.z*lab.z);

    float neutral_mask = saturate((chroma - neutral*0.1) / max(neutral*0.1+0.01, 0.01));
    neutral_mask = neutral_mask * neutral_mask;

    float hue_angle = atan2(lab.z, lab.y) * 57.29578;
    float skin_dist = saturate(1.0 - abs(hue_angle - 30.0) / 25.0);
    float skin_mask = 1.0 - skin_dist * skin;

    float expand_mask = neutral_mask * skin_mask;
    float boost = 1.0 + strength * expand_mask * (1.0 + chroma * 2.0);
    float new_chroma = chroma * boost;

    float2 ab_dir = (chroma > 0.0001) ? float2(lab.y, lab.z) / chroma : float2(1.0, 0.0);
    return max(crt_oklab_to_linear(float3(lab.x, ab_dir * new_chroma)), 0.0);
}

// ---- Method 1: ICtCp (Dolby/ITU broadcast standard) -----------------
// ICtCp separates intensity from chroma more cleanly than Oklab for HDR.
// Uses PQ-based nonlinearity so chroma scaling is luminance-correct for
// high-nit content. Chroma boost scales inversely with intensity so
// bright highlights are expanded less -- correct for HDR 709 content.
// Reference: Rec. ITU-R BT.2100, Dolby ICtCp paper 2016.

float3 crt_linear_to_ictcp(float3 c)
{
    // Convert linear Rec.709 -> linear Rec.2020 primaries
    static const float3x3 M709_2020 = float3x3(
        0.6274040, 0.3292820, 0.0433140,
        0.0690970, 0.9195400, 0.0113630,
        0.0163916, 0.0880132, 0.8955952
    );
    float3 c2020 = mul(M709_2020, max(c, 0.0));

    // LMS matrix (Rec.2020 to LMS)
    static const float3x3 M_LMS = float3x3(
         1688.0/4096.0, 2146.0/4096.0,  262.0/4096.0,
          683.0/4096.0, 2951.0/4096.0,  462.0/4096.0,
           99.0/4096.0,  309.0/4096.0, 3688.0/4096.0
    );
    // Clamp to non-negative before the PQ encode below: pow() with a negative
    // base returns NaN in HLSL, and a single NaN propagates to a garbage pixel.
    // Rec.709 input is in-gamut for Rec.2020 so this is normally a no-op, but
    // it matches the guarding already used by the Oklab and dtUCS paths and
    // removes the dependency on upstream passes happening to clamp first.
    float3 lms = max(mul(M_LMS, c2020), 0.0);

    // PQ EOTF (simplified -- maps linear to 0-1 PQ range for ICtCp)
    float m1 = 0.1593017578125;
    float m2 = 78.84375;
    float c1 = 0.8359375;
    float c2 = 18.8515625;
    float c3 = 18.6875;
    float3 lms_pq;
    lms_pq.r = pow(max((c1 + c2*pow(lms.r/10000.0, m1)) / (1.0 + c3*pow(lms.r/10000.0, m1)), 0.0), m2);
    lms_pq.g = pow(max((c1 + c2*pow(lms.g/10000.0, m1)) / (1.0 + c3*pow(lms.g/10000.0, m1)), 0.0), m2);
    lms_pq.b = pow(max((c1 + c2*pow(lms.b/10000.0, m1)) / (1.0 + c3*pow(lms.b/10000.0, m1)), 0.0), m2);

    // ICtCp matrix
    static const float3x3 M_ICTCP = float3x3(
         0.5000,  0.5000,  0.0000,
         1.6138, -3.3235,  1.7097,
         4.3781, -4.2460, -0.1321
    );
    return mul(M_ICTCP, lms_pq);
}

float3 crt_ictcp_to_linear(float3 ictcp)
{
    static const float3x3 M_ICTCP_INV = float3x3(
        1.0000,  0.0086,  0.1111,
        1.0000, -0.0086, -0.1111,
        1.0000,  0.5600, -0.3206
    );
    float3 lms_pq = mul(M_ICTCP_INV, ictcp);
    lms_pq = saturate(lms_pq);

    // Inverse PQ
    float m1 = 0.1593017578125;
    float m2 = 78.84375;
    float c1 = 0.8359375;
    float c2 = 18.8515625;
    float c3 = 18.6875;
    float3 lms;
    lms.r = 10000.0 * pow(max(pow(lms_pq.r, 1.0/m2) - c1, 0.0) / (c2 - c3*pow(lms_pq.r, 1.0/m2)), 1.0/m1);
    lms.g = 10000.0 * pow(max(pow(lms_pq.g, 1.0/m2) - c1, 0.0) / (c2 - c3*pow(lms_pq.g, 1.0/m2)), 1.0/m1);
    lms.b = 10000.0 * pow(max(pow(lms_pq.b, 1.0/m2) - c1, 0.0) / (c2 - c3*pow(lms_pq.b, 1.0/m2)), 1.0/m1);

    // LMS back to Rec.2020
    static const float3x3 M_LMS_INV = float3x3(
         3.43661,  -2.50645,   0.06984,
        -0.79133,   1.98360,  -0.19227,
        -0.02594,  -0.09893,   1.12487
    );
    float3 c2020 = mul(M_LMS_INV, lms);

    // Rec.2020 back to Rec.709
    static const float3x3 M2020_709 = float3x3(
         1.6605,  -0.5876,  -0.0728,
        -0.1246,   1.1329,  -0.0083,
        -0.0182,  -0.1006,   1.1187
    );
    return max(mul(M2020_709, max(c2020, 0.0)), 0.0);
}

float3 crt_gamut_expand_ictcp(float3 lin, float strength, float neutral, float skin)
{
    // Normalise to nits for ICtCp. scRGB defines 1.0 = 80 nits (SDR reference
    // white), so 80 is the correct scale for Pipeline 1 and a reasonable
    // assumption for Pipeline 0/2 linearised signals.
    float3 ictcp = crt_linear_to_ictcp(lin * 80.0);
    float  I     = ictcp.x;
    float  ct    = ictcp.y;
    float  cp    = ictcp.z;
    float  chroma = sqrt(ct*ct + cp*cp);

    // Neutral protection
    float neutral_mask = saturate((chroma - neutral*0.005) / max(neutral*0.005+0.0001, 0.0001));
    neutral_mask = neutral_mask * neutral_mask;

    // Skin tone protection (ICtCp hue ~0.05-0.12 rad from Ct axis toward Cp)
    float hue = atan2(cp, ct);
    float skin_dist = saturate(1.0 - abs(hue - 0.5) / 0.35);
    float skin_mask = 1.0 - skin_dist * skin;

    // Luminance-weighted: bright content expands less (H-K correction)
    // I in ICtCp is ~0.5 at 100 nits. Scale boost inversely with I.
    float lum_weight = saturate(1.0 - I * 1.5);

    float expand_mask = neutral_mask * skin_mask * lum_weight;
    float boost = 1.0 + strength * expand_mask;
    float new_chroma = chroma * boost;

    float2 ctcp_dir = (chroma > 0.00001) ? float2(ct, cp) / chroma : float2(1.0, 0.0);
    float3 ictcp_exp = float3(I, ctcp_dir * new_chroma);
    return max(crt_ictcp_to_linear(ictcp_exp) / 80.0, 0.0);
}

// ---- Method 2: darktable UCS 2022 -----------------------------------
// Brightness-saturation space accounting for Helmholtz-Kohlrausch effect.
// Designed specifically for artistic saturation changes at constant brightness.
// Reference: Aurélien Pierre, "Color saturation control for the 21st century"
// https://eng.aurelienpierre.com/2022/02/color-saturation-control-for-the-21th-century/
// Source: darktable src/common/colorspaces_inline_conversions.h (GPL3)

float3 crt_linear_to_dtucs(float3 lin)
{
    // Step 1: linear RGB (Rec.709) -> XYZ D65
    static const float3x3 M_709_XYZ = float3x3(
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041
    );
    float3 XYZ = mul(M_709_XYZ, max(lin, 0.0));

    // Step 2: XYZ -> xyY
    float sum = XYZ.x + XYZ.y + XYZ.z + 1e-9;
    float x = XYZ.x / sum;
    float y = XYZ.y / sum;
    float Y = XYZ.y;

    // Step 3: dt UCS L* (brightness) -- Michaelis-Menten response
    // Fitted on Munsell dataset: L = Y^(1/2) with adjustment
    // Simplified form from darktable source
    float L = (Y > 0.0) ? pow(max(Y, 0.0), 0.4285714) : 0.0; // ~Y^(3/7)

    // Step 4: M (chroma in UCS) and h (hue)
    // dt UCS uses a custom opponent colour transform fitted to perceptual data
    // Linearised Munsell chroma: M = sqrt((x-xn)^2 + (y-yn)^2) * scale
    // xn, yn = D65 white point in xy
    float xn = 0.3127, yn = 0.3290;
    float u = (x - xn);
    float v = (y - yn);
    float M = sqrt(u*u + v*v) * 15.932; // fitted scale from darktable
    float h = atan2(v, u);

    return float3(L, M, h);
}

float3 crt_dtucs_to_linear(float3 LMh)
{
    float L = LMh.x;
    float M = LMh.y;
    float h = LMh.z;

    // Reconstruct xyY
    float xn = 0.3127, yn = 0.3290;
    float u = cos(h) * M / 15.932;
    float v = sin(h) * M / 15.932;
    float x = u + xn;
    float y = v + yn;

    // Reconstruct Y from L (inverse Michaelis-Menten simplified)
    float Y = (L > 0.0) ? pow(max(L, 0.0), 2.3333333) : 0.0; // ~L^(7/3)

    // xyY -> XYZ
    float3 XYZ;
    XYZ.y = Y;
    XYZ.x = (y > 0.0001) ? x * Y / y : 0.0;
    XYZ.z = (y > 0.0001) ? (1.0 - x - y) * Y / y : 0.0;

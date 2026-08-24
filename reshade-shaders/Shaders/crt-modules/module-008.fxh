
    // XYZ -> linear Rec.709
    static const float3x3 M_XYZ_709 = float3x3(
         3.2404542, -1.5371385, -0.4985314,
        -0.9692660,  1.8760108,  0.0415560,
         0.0556434, -0.2040259,  1.0572252
    );
    return max(mul(M_XYZ_709, max(XYZ, 0.0)), 0.0);
}

float3 crt_gamut_expand_dtucs(float3 lin, float strength, float neutral, float skin)
{
    float3 LMh = crt_linear_to_dtucs(lin);
    float  L   = LMh.x;
    float  M   = LMh.y;
    float  h   = LMh.z;

    // Neutral protection
    float neutral_mask = saturate((M - neutral*0.5) / max(neutral*0.5+0.01, 0.01));
    neutral_mask = neutral_mask * neutral_mask;

    // Skin tone protection -- in UCS hue space, skin is near orange (~-0.5 to 0.1 rad)
    float skin_dist = saturate(1.0 - abs(h + 0.2) / 0.5);
    float skin_mask = 1.0 - skin_dist * skin;

    // Helmholtz-Kohlrausch: colourful colours appear brighter, so reduce expansion
    // for very bright colours to avoid perceptual over-saturation
    float hk_weight = saturate(1.0 - L * L * 0.8);

    float expand_mask = neutral_mask * skin_mask * hk_weight;
    float new_M = M * (1.0 + strength * expand_mask);

    return max(crt_dtucs_to_linear(float3(L, new_M, h)), 0.0);
}

// ---- Main expand function -- dispatches to selected method ----------
// Apply chroma ceiling in Oklab space -- smooth exponential compressor.
// Colours below ceiling pass through unchanged; colours above are asymptotically
// compressed back toward ceiling without hard clipping or hue shifts.
// crt_apply_chroma_ceiling: limits how much expansion is applied,
// but NEVER reduces chroma below the original unexpanded value.
// linear_orig = original pre-expansion colour (floor)
// linear_expanded = post-expansion colour (to be clamped)
float3 crt_apply_chroma_ceiling(float3 linear_orig, float3 linear_expanded, float ceiling)
{
    if (ceiling < 0.001) return linear_expanded; // 0 = no ceiling, passthrough

    float3 lab_orig = crt_linear_to_oklab(linear_orig);
    float3 lab_exp  = crt_linear_to_oklab(linear_expanded);

    float chroma_orig = sqrt(lab_orig.y*lab_orig.y + lab_orig.z*lab_orig.z);
    float chroma_exp  = sqrt(lab_exp.y*lab_exp.y   + lab_exp.z*lab_exp.z);

    if (chroma_exp < 0.0001) return linear_expanded;

    // Map ceiling [0,1] to a chroma threshold above the original
    // At ceiling=0: threshold very high (no limiting)
    // At ceiling=1: threshold = original chroma (no expansion at all)
    // Range in between gives partial limiting
    float threshold = lerp(chroma_orig + 0.35, chroma_orig, ceiling);
    threshold = max(threshold, chroma_orig); // never below original

    // Smooth compressor: values below threshold pass through, above are compressed
    float chroma_limited = threshold * (1.0 - exp(-chroma_exp / max(threshold, 0.001)));
    // Ensure output chroma never falls below original
    chroma_limited = max(chroma_limited, chroma_orig);

    float scale = chroma_limited / chroma_exp;
    lab_exp.y *= scale;
    lab_exp.z *= scale;

    return max(crt_oklab_to_linear(lab_exp), 0.0);
}

float3 crt_gamut_expand(float3 linear_in)
{
    float3 result;
    if (crt_gamut_expand_method == 2)
        result = crt_gamut_expand_dtucs(linear_in,
                 crt_gamut_expand_strength,
                 crt_gamut_expand_neutral,
                 crt_gamut_expand_skin);
    else if (crt_gamut_expand_method == 1)
        result = crt_gamut_expand_ictcp(linear_in,
                 crt_gamut_expand_strength,
                 crt_gamut_expand_neutral,
                 crt_gamut_expand_skin);
    else
        result = crt_gamut_expand_oklab(linear_in,
                 crt_gamut_expand_strength,
                 crt_gamut_expand_neutral,
                 crt_gamut_expand_skin);

    return crt_apply_chroma_ceiling(linear_in, result, crt_gamut_expand_ceiling);
}

void crt_gamut_expand_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 c = tex2D(ReShade::BackBuffer, texcoord).rgb;

    if (crt_gamut_expand_strength < 0.001)
    {
        color = float4(c, 1.0);
        return;
    }

    float3 linear_c;

#if PIPELINE == 0
    linear_c = pow(max(c, 0.0), 2.2);
    linear_c = crt_gamut_expand(linear_c);
    c = pow(max(linear_c, 0.0), 1.0 / 2.2);
    c = saturate(c);

#elif PIPELINE == 1
    // scRGB: already linear, may exceed 1.0 -- preserve HDR headroom
    linear_c = crt_gamut_expand(c);
    c = max(linear_c, 0.0);

#elif PIPELINE == 2
    // HDR10: decode PQ, expand, re-encode PQ
    c = soop_pq_to_linear(c, crt_soop_hdr10_peak_nits);
    c = crt_gamut_expand(c);
    c = soop_linear_to_pq(max(c, 0.0), crt_soop_hdr10_peak_nits);
#endif

    color = float4(c, 1.0);
}

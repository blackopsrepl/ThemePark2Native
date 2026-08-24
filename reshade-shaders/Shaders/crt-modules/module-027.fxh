        // Per channel mode: each channel boosted by its own value independently
        float3 bb_gain3 = lerp(crt_bb_dark, crt_bb_bright, c);
        c = max(c * bb_gain3, 0.0);
    }

    // -- Vignette --
    #if ENABLE_VIGNETTE
    if (crt_vignette_strength > 0.001)
    {
        float2 uv_c = texcoord * 2.0 - 1.0; // [-1,1] on both axes

        float vig;
        if (crt_vignette_shape == 1)
        {
            // Circular/elliptical: original dot(uv,uv) radial falloff.
            // Produces an oval on 16:9 (touches top/bottom before sides).
            vig = pow(saturate(1.0 - dot(uv_c, uv_c) * 0.5), crt_vignette_power);
        }
        else
        {
            // Rectangular CRT-authentic: independent H and V power-curve falloffs.
            // Corners naturally darker as product of both falloffs.
            float vig_h = pow(saturate(1.0 - abs(uv_c.x)), crt_vignette_power);
            float vig_v = pow(saturate(1.0 - abs(uv_c.y)), crt_vignette_v_power);
            vig = vig_h * vig_v;
        }
        // Highlight protection: pixels above threshold are progressively lifted
        // toward no-vignette. Strength controls maximum protection at threshold.
        float vig_luma = dot(c, float3(0.2126, 0.7152, 0.0722));
        float protect  = saturate((vig_luma - crt_vignette_hdr_threshold) /
                                   max(1.0 - crt_vignette_hdr_threshold, 0.001));
        // protect=0 below threshold (full vig), =1 at peak brightness
        // Scale by strength so user controls maximum protection level
        float vig_gate = 1.0 - protect * crt_vignette_hdr_strength;
        vig = lerp(1.0, vig, vig_gate);
        vig = lerp(1.0, vig, crt_vignette_strength);
        c *= vig;
    }
    #endif // ENABLE_VIGNETTE

    // -- Corner shadow: bezel-cast darkening at screen extremes --
    #if ENABLE_CORNER_ROUND
    if (crt_corner_shadow > 0.001)
    {
        float2 edge  = abs(texcoord - 0.5) * 2.0; // 0=centre, 1=edge
        float  shadow = pow(max(edge.x, edge.y), 6.0);
        c *= 1.0 - shadow * crt_corner_shadow;
    }
    #endif

    // -- Halation (bright element glass scatter, localised) --
    #if ENABLE_HALATION
    if (crt_halation_strength > 0.001)
    {
        // Bilinear fetch from quarter-res texture -- hardware filtering gives
        // additional free smoothing on top of the blur
        // Use the V-blurred result (H then V) for true 2D anisotropic halation.
        // At anisotropy=1.0 both H and V sigma are equal -- isotropic, same as before.
        float3 halo = tex2D(crt_halation_v_sampler, texcoord).rgb;
        // Only add halation where the current pixel is darker than the halo
        // This prevents bright areas from blooming into themselves
        float cur_luma  = dot(c, float3(0.2126, 0.7152, 0.0722));
        float halo_luma = dot(halo, float3(0.2126, 0.7152, 0.0722));
        float gate      = saturate(halo_luma - cur_luma);
        c += halo * gate * crt_halation_strength;
    }
    #endif

    // -- Interference: rolling scanlines and animated chromatic ghosting --


    // -- Glow (tight + wide dual-scale bloom) --
    if (crt_glow_strength > 0.001 || crt_glow_wide_strength > 0.001)
    {
        float2 glow_uv = texcoord;
        if (crt_glow_strength > 0.001)
        {
            float3 glow = tex2D(crt_glow_v_sampler, glow_uv).rgb;
            c += crt_glow_strength * glow;
        }
        if (crt_glow_wide_strength > 0.001)
        {
            float3 wide_glow = tex2D(crt_glow_wide_v_sampler, glow_uv).rgb;
            c += crt_glow_wide_strength * wide_glow;
        }
    }

    color = float4(c, 1.0);
}

// ============================================================
// Edge blur pass: Radial optical defocus
// 8-tap Poisson disc scaled by distance from centre.
// Simulates CRT glass softening at beam edges.
// Centre is sharp, corners are defocused.
// Fixed 8 taps regardless of strength -- no quality slider needed.
// ============================================================

#if ENABLE_EDGE_BLUR
void crt_edge_blur_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    if (crt_edge_blur_strength < 0.001)
    {
        color = tex2D(ReShade::BackBuffer, texcoord);
        return;
    }

    // Distance from centre [0, ~0.707 at corner]
    float2 uv_c     = texcoord - 0.5;
    // Correct for aspect ratio so falloff is circular not elliptical
    uv_c.x         *= float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);
    float  dist     = length(uv_c);

    // Blur amount: zero at centre, grows as power of distance
    float  blur_amt = pow(dist * 2.0, crt_edge_blur_falloff) *
                      crt_edge_blur_strength * crt_edge_blur_radius;

    // 8-tap Poisson disc -- fixed quality, cheap
    // Offsets in pixel space, rotated for good coverage
    float2 px = ReShade::PixelSize * blur_amt;
    static const float2 kDisc[8] = {
        float2( 0.000,  1.000),
        float2( 0.707,  0.707),
        float2( 1.000,  0.000),
        float2( 0.707, -0.707),
        float2( 0.000, -1.000),
        float2(-0.707, -0.707),
        float2(-1.000,  0.000),
        float2(-0.707,  0.707)
    };

    float3 result = tex2D(ReShade::BackBuffer, texcoord).rgb;
    for (int i = 0; i < 8; i++)
        result += tex2D(ReShade::BackBuffer, texcoord + kDisc[i] * px).rgb;
    result /= 9.0;

    color = float4(result, 1.0);
}
#endif



// ============================================================
// Film Grain: Compute shader path (Poisson Analog Film Grain)
// Self-contained -- all required functions inlined, no external includes.
// ============================================================


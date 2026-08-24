// 2 = darktable UCS 2022 (Helmholtz-Kohlrausch aware, most accurate)
// Context: Rec.709 chrominance in HDR container -> expand toward Rec.2020.
// Luminance is already correct HDR. Only colour primaries are expanded.
// ============================================================
#include "module-009.fxh"


// ============================================================
// Technique
// ============================================================
// ============================================================
// Screen reflection pass -- faint blurred self-reflection at screen edges
// Simulates thick CRT glass internal reflection: bright content near edges
// bounces back faintly, fading toward screen centre.
// ============================================================
#if ENABLE_SCREEN_REFLECT
void crt_screen_reflect_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 c = tex2D(ReShade::BackBuffer, texcoord).rgb;
    if (crt_reflect_strength > 0.001)
    {
        // Edge mask: distance from screen centre, stronger at edges.
        // Uses distance from 0.5 in each axis, raised to power for falloff shape.
        float2 edge_dist = abs(texcoord - 0.5) * 2.0; // 0 at centre, 1 at edge
        float  edge_mask = pow(max(edge_dist.x, edge_dist.y), crt_reflect_fade);
        edge_mask = saturate(edge_mask);

        // Sample from wide glow texture as reflection source -- already blurred.
        // Gamma compresses to concentrate on bright content.
        float3 reflect_src = tex2D(crt_glow_wide_v_sampler, texcoord).rgb;
        reflect_src = pow(max(reflect_src, 0.0), crt_reflect_gamma);

        // Additive composite gated to screen edges
        c += reflect_src * crt_reflect_strength * edge_mask;
    }
    color = float4(c, 1.0);
}
#endif // ENABLE_SCREEN_REFLECT

// ============================================================
// Tube diffuse pass -- ambient phosphor scatter glow through CRT glass
// ============================================================
#if ENABLE_TUBE_DIFFUSE
void crt_tube_diffuse_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 c = tex2D(ReShade::BackBuffer, texcoord).rgb;
    if (crt_tube_diffuse_strength > 0.001)
    {
        // Sample from the wide glow texture -- already heavily blurred.
        // Apply gamma to concentrate the effect on brighter content,
        // then composite additively at low strength.
        float3 diffuse = tex2D(crt_glow_wide_v_sampler, texcoord).rgb;
        diffuse = pow(max(diffuse, 0.0), crt_tube_diffuse_gamma);
        c += diffuse * crt_tube_diffuse_strength;
    }
    color = float4(c, 1.0);
}
#endif // ENABLE_TUBE_DIFFUSE

// ============================================================
// Noise floor pass -- fixed-pattern thermal noise, independent of interference
// ============================================================
#if ENABLE_NOISE_FLOOR
void crt_noise_floor_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 c = tex2D(ReShade::BackBuffer, texcoord).rgb;
    if (crt_noise_floor > 0.001)
    {
        uint2 noise_px   = uint2(texcoord * float2(BUFFER_WIDTH, BUFFER_HEIGHT)
                           / max(crt_noise_floor_scale, 1.0));
        // Slow temporal variation: changes every 4 frames so it drifts
        // rather than being static, but slower than film grain (every frame)
        uint  frame_slow = (FRAMECOUNT / 4u) * 0x9E3779B9u;
        uint  noise_seed = noise_px.x * 1973u + noise_px.y * 9277u + frame_slow;
        float noise_val  = (grain_unorm1(grain_uhash(noise_seed)) - 0.5) * 2.0;
        float luma_n    = dot(c, float3(0.299, 0.587, 0.114));
        float dark_gate = saturate(1.0 - luma_n * 2.0); // fades above ~50% luma
        c = saturate(c + noise_val * crt_noise_floor * dark_gate);
    }
    color = float4(c, 1.0);
}
#endif // ENABLE_NOISE_FLOOR

// ============================================================
// Interference pass -- all signal-level effects as post-process
// Applied to the final image after all CRT rendering is complete.
// Effects compose in two phases so they all stack:
//   Phase 1 (UV displacement): H-sync, wiggle, scanline jitter -- offsets are
//            summed into disp_uv and applied in a single fetch.
//   Phase 2 (colour modification): accumulate, magnetic, dot crawl, hum bars,
//            rolling scanlines, ghost -- applied on top of the fetched colour.
// (Displacement effects previously each re-sampled the backbuffer and
// overwrote the working colour, so an active jitter wiped out the others.)
// ============================================================

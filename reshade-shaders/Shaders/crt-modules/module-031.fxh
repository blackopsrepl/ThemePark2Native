#if ENABLE_INTERFERENCE
void crt_accum_store_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    color = tex2D(ReShade::BackBuffer, texcoord);
}

void crt_interference_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    // ------------------------------------------------------------------
    // Phase 1: accumulate UV displacement from all geometry-shifting
    // effects (H-sync, wiggle, scanline jitter). These are pure UV shifts,
    // so summing their offsets and doing ONE fetch lets them compose instead
    // of each overwriting the previous by re-sampling the raw backbuffer.
    // (Previously each did its own tex2D(BackBuffer,...) and clobbered c,
    // which is why an active jitter appeared to disable the other effects.)
    // ------------------------------------------------------------------
    float2 disp_uv = 0.0;

    // -- H-sync instability: probabilistic per-row horizontal displacement --
    if (crt_hsync_strength > 0.001)
    {
        uint row        = uint(texcoord.y * float(BUFFER_HEIGHT));
        uint hsync_seed = row * 3761u + FRAMECOUNT * 0x45D9F3Bu;
        float rand_val  = grain_unorm1(grain_uhash(hsync_seed));
        if (rand_val < crt_hsync_rate)
        {
            uint  mag_seed  = row * 9277u + FRAMECOUNT * 0x1B873593u;
            float disp      = (grain_unorm1(grain_uhash(mag_seed)) - 0.5) * 2.0;
            float top_bias  = 1.0 + (1.0 - texcoord.y) * 0.5;
            float hs_scale  = 1080.0 / float(BUFFER_WIDTH);
            disp_uv.x += disp * crt_hsync_strength * top_bias * hs_scale;
        }
    }

    // -- Wiggle: horizontal UV displacement (NewPixie triple-sine) --
    // KNOWN INCONSISTENCY (deliberately not changed): this scales a horizontal
    // displacement by 1080/BUFFER_HEIGHT, whereas H-sync above uses
    // 1080/BUFFER_WIDTH. Both are resolution-independent within a given aspect
    // ratio, but only the H-sync form is aspect-independent -- wiggle (and the
    // ghost offsets further down, which scale both axes by the same
    // height-derived factor) displace ~31% further on 21:9 than on 16:9.
    // Left as-is because changing it would shift the feel of existing presets;
    // switch to BUFFER_WIDTH here if ultrawide consistency is ever wanted.
    if (crt_wiggle_strength > 0.0001)
    {
        float t_wig = (float(FRAMECOUNT) - 849.0*floor(float(FRAMECOUNT)/849.0)) * 36.0 * crt_wiggle_speed;
        float wig   = sin(0.1*t_wig  + texcoord.y*13.0)
                    * sin(0.23*t_wig + texcoord.y*19.0)
                    * sin(0.3 + 0.11*t_wig + texcoord.y*23.0);
        float wig_scale = 1080.0 / float(BUFFER_HEIGHT);
        disp_uv.x += wig * crt_wiggle_strength * wig_scale;
    }

    // -- Scanline jitter: per-scanline vertical displacement --
    if (crt_scanline_jitter > 0.001)
    {
        uint row      = uint(texcoord.y * float(BUFFER_HEIGHT));
        uint t_slow   = (FRAMECOUNT / 3u) * 0x9E3779B9u;
        uint jit_seed = row * 1447u + t_slow;
        float jitter  = (grain_unorm1(grain_uhash(jit_seed)) - 0.5) * 2.0;
        disp_uv.y += jitter * crt_scanline_jitter * ReShade::PixelSize.y;
    }

    float2 src_uv = texcoord + disp_uv;

    // ------------------------------------------------------------------
    // Phase 2: fetch the (possibly displaced) source, applying accumulate
    // modulation at the same displaced coordinate so afterglow follows the
    // shifted image.
    // ------------------------------------------------------------------
    if (crt_accum_modulate > 0.001)
    {
        float4 prev    = tex2D(crt_accum_samp, src_uv) * crt_accum_modulate;
        float4 current = tex2D(ReShade::BackBuffer, src_uv) * 0.96;
        color = max(prev, current);
    }
    else
    {
        color = tex2D(ReShade::BackBuffer, src_uv);
    }

    float3 c = color.rgb;

    // -- Magnetic interference: radial hue rotation around source point --
    if (crt_magnetic_strength > 0.001)
    {
        // Distance from magnetic source, aspect-corrected
        float ar = float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);
        float2 src = float2(crt_magnetic_x, crt_magnetic_y);
        float2 delta = (texcoord - src) * float2(ar, 1.0);
        float dist = length(delta);

        // Animated ring phase: slow outward drift
        float t_mag = CRT_TIMER * 0.001 * crt_magnetic_speed;
        // Ring pattern: sin of distance creates concentric rings,
        // phase offset by time makes them drift outward
        float ring_phase = dist / max(crt_magnetic_radius, 0.001) * 6.2832 - t_mag;
        float ring = sin(ring_phase);

        // Hue rotation amount: stronger near source, modulated by ring pattern
        float dist_gate = exp(-dist / max(crt_magnetic_radius, 0.001));
        float angle = ring * dist_gate * crt_magnetic_strength * 3.14159;

        c = hue_rotate(c, angle);
    }

    // -- Dot crawl: NTSC colour subcarrier interference at luma-chroma boundaries --
    // Animated diagonal pattern at colour edges, characteristic of composite video.
    if (crt_dot_crawl > 0.001)
    {
        // Phase advances ~3.58 cycles per frame (NTSC subcarrier relationship)
        float phase = float(FRAMECOUNT) * 0.279; // ~pi/2 * 3.58/4 approximation
        float2 fc_pos = texcoord * float2(BUFFER_WIDTH, BUFFER_HEIGHT);
        // Chequered subcarrier pattern: alternates sign with pixel position and time
        float subcarrier = sin(phase + (floor(fc_pos.x) + floor(fc_pos.y)) * 3.14159);
        // Gate to colour edges only -- measure local colour variation
        float2 px = ReShade::PixelSize;
        float3 left  = tex2D(ReShade::BackBuffer, src_uv - float2(px.x, 0)).rgb;
        float3 right = tex2D(ReShade::BackBuffer, src_uv + float2(px.x, 0)).rgb;
        float chroma_edge = length((left - right) - dot(left - right, float3(0.299,0.587,0.114)));
        float gate = saturate(chroma_edge * 8.0);
        // Add the subcarrier pattern modulated by the colour edge strength
        c += subcarrier * crt_dot_crawl * gate;
        c = max(c, 0.0);
    }

    // -- Hum bars: AC mains interference scrolling brightness gradient --
    if (abs(crt_hum_intensity) > 0.001)
    {
        float hum_scroll = frac(texcoord.y + float(FRAMECOUNT) / crt_hum_speed);
        float hum_mult = (crt_hum_intensity >= 0.0)
            ? (1.0 - crt_hum_intensity) + crt_hum_intensity * hum_scroll
            : (1.0 + crt_hum_intensity) + crt_hum_intensity * (hum_scroll - 1.0);
        c *= hum_mult;
    }

    // -- Rolling scanlines: sync instability at screen-resolution frequency --
    // Matches NewPixie scanroll. crt_flicker_strength = speed (0 = disabled/no movement).
    // When speed > 0, time advances and scanlines scroll. No darkening when disabled.
    if (crt_flicker_strength > 0.0001)
    {
        float t_sc  = (float(FRAMECOUNT) - 640.0*floor(float(FRAMECOUNT)/640.0))
                    * crt_flicker_strength;
        // sin oscillates around 0: at t=0, sin=0, scans=0.35+0=0.35 -> darkening.
        // Shift by pi/2 so at t=0 scans=0.35+0.18=0.53 -> minimal darkening at start.
        // Use abs() so scans never goes below 0.35 -- avoids systematic darkening.
        float scans = 0.35 + 0.18 * abs(sin(6.0*t_sc - texcoord.y * float(BUFFER_HEIGHT) * 1.5));
        c *= pow(scans / 0.53, 0.9); // normalise so peak = 1.0
    }

    // -- Ghost image: RF reflection/antenna delay --
    // Matches NewPixie exactly: fixed small displacement + tiny animated wobble.
    // Base offsets are small (~1-2%) so ghost appears close to source, not far away.
    // time uses mod(FRAMECOUNT,849)*36 same as wiggle -- slow enough to be visible.
    if (crt_ghost_strength > 0.0001)
    {
        float t_g = (float(FRAMECOUNT) - 849.0*floor(float(FRAMECOUNT)/849.0))
                  * 36.0 * crt_ghost_speed;
        // Fixed base offset (small, close to source) + tiny animated wobble
        // Scale offsets by resolution: NewPixie values tuned for 1080p.
        // At 4K the same UV offset covers twice as many pixels, so scale down.
        float ghost_res_scale = 1080.0 / float(BUFFER_HEIGHT);
        float2 r_uv = src_uv + (float2(-0.014, -0.027)*0.85
                    + 0.007*float2(0.35*sin(1.0/7.0 + 15.0*texcoord.y + 0.9*t_g),
                                   0.35*sin(2.0/7.0 + 10.0*texcoord.y + 1.37*t_g))
                    + float2(0.001, 0.001)) * ghost_res_scale;
        float2 g_uv = src_uv + (float2(-0.019, -0.020)*0.85
                    + 0.007*float2(0.35*cos(1.0/9.0 + 15.0*texcoord.y + 0.5*t_g),
                                   0.35*sin(2.0/9.0 + 10.0*texcoord.y + 1.50*t_g))
                    + float2(0.000, -0.002)) * ghost_res_scale;
        float2 b_uv = src_uv + (float2(-0.017, -0.003)*0.85
                    + 0.007*float2(0.35*sin(2.0/3.0 + 15.0*texcoord.y + 0.7*t_g),
                                   0.35*cos(2.0/3.0 + 10.0*texcoord.y + 1.63*t_g))
                    + float2(-0.002, 0.000)) * ghost_res_scale;
        float3 ghost_r = tex2D(ReShade::BackBuffer, r_uv).rgb * float3(0.5, 0.25, 0.25);
        float3 ghost_g = tex2D(ReShade::BackBuffer, g_uv).rgb * float3(0.25, 0.5, 0.25);
        float3 ghost_b = tex2D(ReShade::BackBuffer, b_uv).rgb * float3(0.25, 0.25, 0.5);
        float luma_i = dot(c, float3(0.299, 0.587, 0.114));
        float i = (1.0 - luma_i*luma_i) * 0.85 + 0.15;
        float ghs = crt_ghost_strength;
        c += (ghs*(1.0-0.299)) * pow(saturate(3.0*ghost_r), 2.0) * i;
        c += (ghs*(1.0-0.587)) * pow(saturate(3.0*ghost_g), 2.0) * i;
        c += (ghs*(1.0-0.114)) * pow(saturate(3.0*ghost_b), 2.0) * i;
    }

    color = float4(c, 1.0);
}
#endif // ENABLE_INTERFERENCE

// ============================================================
// Light Warp pass
// ============================================================
#if ENABLE_LIGHT_WARP
void crt_light_warp_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    if (abs(crt_warp_strength) < 0.001 && abs(crt_pin_phase) < 0.001 && abs(crt_pin_amp) < 0.001)
    {
        color = tex2D(ReShade::BackBuffer, texcoord);
        return;
    }
    float ar   = float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);
    float2 uv  = texcoord - 0.5;
    uv.x      *= ar;

    // Radial barrel/pincushion
    float  r2  = dot(uv, uv);
    uv        *= 1.0 + crt_warp_strength * r2;

    // Pin phase: horizontal linearity varies with vertical position (Megatron).
    uv.x      *= 1.0 + crt_pin_phase * (uv.y / max(0.5 * ar, 0.001));
    // Pin amp: vertical linearity varies with horizontal position (complement).
    uv.y      *= 1.0 + crt_pin_amp   * (uv.x / max(0.5, 0.001));

    uv.x      /= ar;
    uv        += 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        color = float4(crt_warp_border_colour, 1.0);
    else
        color = tex2D(ReShade::BackBuffer, uv);
}
#endif



// ============================================================
// Corner rounding pass
// Based on Guest Advanced corner() function -- multiplier approach
// that darkens edges/corners rather than filling with a flat colour.
// Three parameters: corner size, border shadow, intensity power curve.
// ============================================================
#if ENABLE_CORNER_ROUND
float crt_corner_mask(float2 texcoord)
{
    float ar  = float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);
    float2 aspect = float2(1.0, ar);

    // Remap texcoord to [0,1] centred, then take absolute value -> [0, 0.5]
    float2 pos = abs(2.0 * (texcoord - 0.5));

    // Border: adds uniform edge shadow on all four sides
    float b = crt_corner_border * 0.05 + 0.0005;
    // Aspect-correct the vertical border contribution
    pos.y = pos.y + b * (aspect.y - 1.0);

    // Corner radius: must be at least as large as border to avoid artefacts
    float2 crn = max(crt_corner_size.xx, 2.0 * b + 0.0015);

    // Distance into corner region (aspect corrected)
    float2 crp = max(pos - (1.0 - crn * aspect), 0.0) / aspect;
    float  cd  = sqrt(dot(crp, crp));

    // Blend the corner geometry into the position
    pos = max(pos, 1.0 - crn + cd);

    // Smooth mask: 1.0 inside, 0.0 outside, with border transition
    float res = lerp(1.0, 0.0, smoothstep(1.0 - b, 1.0, sqrt(max(pos.x, pos.y))));

    // Power curve controls sharpness of the edge/corner
    return pow(res, crt_corner_intensity);
}

void crt_corner_round_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 screen = tex2D(ReShade::BackBuffer, texcoord).rgb;

    if (crt_corner_size < 0.001 && crt_corner_border < 0.001)
    {
        color = float4(screen, 1.0);
        return;
    }

    float mask = crt_corner_mask(texcoord);
    // Multiply the image by the mask -- darkens edges/corners, black outside
    color = float4(screen * mask, 1.0);
}
#endif


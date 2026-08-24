
// ============================================================
// Fibonacci sequence for decay weighting
static const float kFib[8] = { 1.0, 1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 21.0 };

// Variable MPRT sRGB helpers (SDR path only)
// Uses hardcoded sRGB standard (gamma 2.4 / IEC 61966-2-1).
// No user-exposed gamma slider -- the sRGB transfer function is not a free parameter;
// changing it breaks the brightness-budget math.
static const float kDecayGamma = 2.4;
float bb_srgb2linear(float c)
{
    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, kDecayGamma);
}
float3 bb_srgb2linear(float3 c)
{
    return float3(bb_srgb2linear(c.r), bb_srgb2linear(c.g), bb_srgb2linear(c.b));
}
float bb_linear2srgb(float c)
{
    // Standard IEC 61966-2-1 sRGB encode.
    // Below threshold: linear segment. Above: power curve.
    return (c <= 0.0031308)
        ? c * 12.92
        : pow(max(c, 0.0), 1.0 / kDecayGamma) * 1.055 - 0.055;
}
float3 bb_linear2srgb(float3 c)
{
    return float3(bb_linear2srgb(c.r), bb_linear2srgb(c.g), bb_linear2srgb(c.b));
}

// Phase store: write raw cycle index as a normalised float in [0,1].
// Encoding: index / (MAX_FRAMES - 1) so R8 precision covers 2..8 frames cleanly.
// MAX_FRAMES must match the ui_max of crt_decay_frames (8).
#define DECAY_MAX_FRAMES 8
// Shared luma sampler for monitor -- samples post-decay backbuffer at 9 points.
float crt_decay_sample_luma()
{
    float luma = 0.0;
    [unroll] for (int sy = 0; sy < 3; sy++)
    [unroll] for (int sx = 0; sx < 3; sx++)
    {
        float3 s = tex2D(ReShade::BackBuffer, float2((sx + 0.5) / 3.0, (sy + 0.5) / 3.0)).rgb;
        luma += dot(s, float3(0.2126, 0.7152, 0.0722));
    }
    return luma / 9.0;
}

// Lit frame EMA monitor: only updates when frame_in_cycle == 0
void crt_decay_luma_lit_copy_PS(
    in  float4 pos : SV_Position, in float2 tc : TEXCOORD0,
    out float4 col : SV_Target) { col = tex2D(crt_decay_luma_lit_sampler, tc); }

void crt_decay_luma_dark_copy_PS(
    in  float4 pos : SV_Position, in float2 tc : TEXCOORD0,
    out float4 col : SV_Target) { col = tex2D(crt_decay_luma_dark_sampler, tc); }

void crt_decay_luma_lit_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    int frames        = max(crt_decay_frames, 2);
    float4 phase_data = tex2D(crt_decay_phase_sampler, float2(0.5, 0.5));
    int    fic        = int(round(phase_data.r * 255.0)) % frames;
    float  prev       = tex2D(crt_decay_luma_lit_prev_samp, float2(0.5, 0.5)).r;
    if (fic == 0)
        color = float4(lerp(prev, crt_decay_sample_luma(), 0.05), 0.0, 0.0, 1.0);
    else
        color = float4(prev, 0.0, 0.0, 1.0); // preserve
}

// Dark frame EMA monitor: only updates when frame_in_cycle != 0
void crt_decay_luma_dark_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    int frames        = max(crt_decay_frames, 2);
    float4 phase_data = tex2D(crt_decay_phase_sampler, float2(0.5, 0.5));
    int    fic        = int(round(phase_data.r * 255.0)) % frames;
    float  prev       = tex2D(crt_decay_luma_dark_prev_samp, float2(0.5, 0.5)).r;
    if (fic != 0)
        color = float4(lerp(prev, crt_decay_sample_luma(), 0.05), 0.0, 0.0, 1.0);
    else
        color = float4(prev, 0.0, 0.0, 1.0); // preserve
}

void crt_decay_phase_store_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    int frames = max(crt_decay_frames, 2);

    // Auto-resync: dark frame EMA should be near dark_floor, not near lit EMA.
    // If dark_avg > 40% of lit_avg the phase has flipped -- add 1 to correct.
    // Only meaningful for 2-frame BFI where lit/dark distinction is cleanest.
    int auto_offset = 0;
    if (crt_decay_auto_resync && frames == 2)
    {
        float lit_avg  = tex2D(crt_decay_luma_lit_sampler,  float2(0.5, 0.5)).r;
        float dark_avg = tex2D(crt_decay_luma_dark_sampler, float2(0.5, 0.5)).r;
        if (lit_avg > 0.01 && dark_avg > lit_avg * 0.40)
            auto_offset = 1;
    }

    int phase_offset = (crt_decay_fg_phase ? 1 : 0) + FRAMEGEN_PHASE_OFFSET + auto_offset;
    int idx          = (int(FRAMECOUNT) + phase_offset) % frames;

    // Duty-cycle skip flag, computed from the same counter as the phase so
    // cycle boundaries stay aligned with phase boundaries. Stored in G for the
    // decay PS to read.
    float duty_active = 1.0;
    if (crt_decay_duty_ratio > 0)
    {
        int cycle_idx = int(FRAMECOUNT) / frames;
        duty_active   = ((cycle_idx % (crt_decay_duty_ratio + 1)) == 0) ? 1.0 : 0.0;
    }

    color = float4(float(idx) / 255.0, duty_active, 0.0, 1.0);
}

// Raw game frame store: captures backbuffer before decay modifies it.
// Must run as the FIRST decay pass -- before prev1/prev2 stores and the decay PS.
// Merged decay history store: three full-res copies in one dual-output pass.
// Saves two full-resolution passes vs three separate ones.
//   Target0 = crt_decay_raw_tex   (current backbuffer -- pre-decay raw frame)
//   Target1 = crt_decay_prev1_tex (current backbuffer -- becomes prev1 next frame)
// prev2 is updated separately since it reads from prev1 (last frame), not BackBuffer.
#if DECAY_BB_INTEGRAL
// BB integral mode: capture raw + prev1 in one dual-output pass.
void crt_decay_store_PS(
    in  float4 position  : SV_Position,
    in  float2 texcoord  : TEXCOORD0,
    out float4 out_raw   : SV_Target0,
    out float4 out_prev1 : SV_Target1)
{
    float3 c  = tex2D(ReShade::BackBuffer, texcoord).rgb;
    out_raw   = float4(c, 1.0);
    out_prev1 = float4(c, 1.0);
}

// prev2 still needs a separate pass -- it reads from prev1 (previous frame's value)
// which is not available in the same pass as BackBuffer capture.
void crt_decay_prev2_store_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    color = float4(tex2D(crt_decay_prev1_sampler, texcoord).rgb, 1.0);
}
#else
// Standard mode: only prev1 is needed -- one full-res write per frame
// (saves two full-res RGBA writes vs BB-integral mode).
void crt_decay_store_PS(
    in  float4 position  : SV_Position,
    in  float2 texcoord  : TEXCOORD0,
    out float4 out_prev1 : SV_Target)
{
    out_prev1 = float4(tex2D(ReShade::BackBuffer, texcoord).rgb, 1.0);
}
#endif // DECAY_BB_INTEGRAL



// ============================================================
// Main decay pass
// Key design decisions:
//   - Phase index: FRAMECOUNT % frames, stored /255, decoded *255
//   - Standard BFI (tubePos off): frame 0 lit at gain, others black
//   - BB integral (tubePos on, 240Hz+): spatial overlap over 1-texcoord.y
//   - HDR mode: hard BFI only, no sRGB conversion, no history frames
//   - Oscillation: FRAMECOUNT-based, no frametime division (ReShade 6.x safe)
//   - 30-second startup passthrough
// ============================================================
void crt_decay_PS(
    in  float4 position : SV_Position,
    in  float2 texcoord : TEXCOORD0,
    out float4 color    : SV_Target)
{
    float3 c      = tex2D(ReShade::BackBuffer, texcoord).rgb;
    int    frames = max(crt_decay_frames, 2);

    // Decode phase index. Encoded as float(idx)/255.0 in phase store pass.
    float4 phase_data   = tex2D(crt_decay_phase_sampler, float2(0.5, 0.5));
    int    frame_in_cycle = int(round(phase_data.r * 255.0)) % frames;

    float3 out_color = float3(0.0, 0.0, 0.0);

    // BFI Duty Ratio: skip every N cycles, outputting passthrough instead.
    // Cycle index = FRAMECOUNT / frames (advances once per complete cycle).
    // When duty_ratio > 0: active on cycle % (duty_ratio+1) == 0, skip otherwise.
    // This is independent of frames-per-cycle -- the skip always spans one
    // complete cycle regardless of how many frames are in it.
    // Duty flag is computed in the phase-store pass from the same base counter
    // as the phase itself (FRAMECOUNT or addon refresh count), so cycle
    // boundaries always align with phase boundaries.
    bool cycle_active = (crt_decay_duty_ratio <= 0) || (phase_data.g > 0.5);

    // Frametime spike detection: if this frame took significantly longer than expected,
    // output passthrough instead of BFI. A spike frame held on-screen for 2-5x the
    // expected period causes a visible flash -- suppressing BFI for that frame
    // eliminates the flash entirely. The next frame resumes normal BFI.
    bool spike_frame = (CRT_FRAMETIME > CRT_FRAMETIME_EXPECTED * crt_decay_spike_threshold);

    // 30-second startup gate, duty ratio skip, and spike suppression all pass through.
    if (CRT_TIMER < 30000.0 || !cycle_active || spike_frame)
    {
        out_color = c;
    }
    else if (crt_decay_method == 0)
    {
        // ====================================================
        // Method 0: Fibonacci (uniform darkening)
        // ====================================================
        if (frame_in_cycle == 0)
        {
            out_color = c;
        }
        else
        {
            float t = float(frame_in_cycle) / float(frames - 1);

            float fib_sum = 0.0;
            float fib_w   = 0.0;
            int   stages  = max(crt_decay_stages, 1);
            [unroll]
            for (int s = 0; s < 8; s++)
            {
                if (s < stages)
                {
                    float w           = kFib[s];
                    float stage_decay = exp(-crt_decay_speed * kFib[s] * 0.1);
                    fib_sum += w * stage_decay;
                    fib_w   += w;
                }
            }
            float base_decay = (fib_w > 0.0) ? saturate(fib_sum / fib_w) : 0.0;

            const float PI_VAL  = 3.14159265;
            float sine_factor   = 0.5 + 0.5 * cos(PI_VAL * t);
            float hard_factor   = pow(base_decay, t);
            float smooth_factor = lerp(hard_factor, sine_factor, crt_decay_sine_blend);
            float floored       = max(smooth_factor, crt_decay_floor);

            float3 factor = float3(
                pow(max(floored, 0.001), crt_decay_r),
                pow(max(floored, 0.001), crt_decay_g),
                pow(max(floored, 0.001), crt_decay_b)
            );

            float luma     = dot(max(c, 0.0), float3(0.2126, 0.7152, 0.0722));
            float luma_mix = pow(saturate(luma), max(1.0 - crt_decay_luma_protect, 0.001));
            factor         = lerp(factor, float3(1.0, 1.0, 1.0), luma_mix * crt_decay_luma_protect);

            // Phosphor trail colour cast: tint the decayed trail component
            // trail = c*factor - c*1.0 (the "missing" brightness from decay)
            // Shift trail colour by adding a per-channel tint proportional to (1-factor)
            float3 trail_tint = float3(
                1.0 + crt_phosphor_trail_r * (1.0 - factor.r),
                1.0 + crt_phosphor_trail_g * (1.0 - factor.g),
                1.0 + crt_phosphor_trail_b * (1.0 - factor.b));
            out_color = c * factor * trail_tint;
        }
    }
    else if (crt_decay_method == 2)
    {
            // ====================================================
            // Method 2: BFI (Black Frame Insertion) -- HDR/linear path
            //
            // The BB overlap-integral algorithm requires input values
            // in bounded [0,1] linear space. In HDR (scRGB/PQ-decoded)
            // pipelines, values above 1.0 are legal -- a 1000-nit
            // highlight in an 80-nit reference is ~12.5 in scRGB linear.
            // Multiplying by (frames x gain) before the overlap math
            // inflates those values to 15-20+, and the final max(r,0)
            // clamp cannot rescue them. The result is catastrophically
            // blown highlights.
            //
            // Standard BFI is the correct HDR approach: on "lit" frames
            // the signal is boosted by (frames x gain) to compensate for
            // duty-cycle loss; on "dark" frames the output is black.
            // This is linear-safe at any signal magnitude.
            // ====================================================
            // Invert cycle: N-1 lit + 1 dark instead of 1 lit + N-1 dark.
            // Standard: frame 0 = lit, others = dark.
            // Inverted: frame 0 = dark, others = lit.
            // Duty cycle changes so adjust litGain accordingly.

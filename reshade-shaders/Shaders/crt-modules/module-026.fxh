    scan_width = max(round(scan_width), 1.0);

    // Interlace: shift scanline phase by half a scanline width every other frame.
    // Alternates which rows are bright/dark, simulating CRT interlaced mode.
    // Applied here (to the scanline period) not as a UV shift, so the actual
    // dark gaps between scanlines move position rather than the whole image shifting.
    // Snap to integer pixel coordinates before scanline calculation
    float scanline_y = floor(fc.y) + 0.5;
    float f  = frac(scanline_y / scan_width) - 0.5;
    // Analytical half-pixel width -- used by gauss_integral for step-free beam profile
    float hw = 0.5 / max(scan_width, 1.0);
    float da = abs(f - hw) * 2.0;
    float db = abs(f + hw) * 2.0;

    // Per-scanline variation: brightness AND sigma (beam width) vary per row.
    // On a real CRT, HV ripple affects both beam focus and brightness --
    // brighter rows are also slightly wider, dimmer rows slightly narrower.
    // roll_raw is in [-1,1]; roll scales brightness, sigma_roll scales width.
    float scanline_row = floor(scanline_y / scan_width);
    float roll_raw = (crt_scanline_roll_strength > 0.0001)
                   ? crt_scanline_roll(scanline_row
                       + floor(CRT_TIMER * 0.001 * crt_scanline_roll_drift))
                   : 0.0;
    float roll       = 1.0 + crt_scanline_roll_strength * roll_raw;
    // Sigma modulation: wider when brighter, narrower when dimmer
    // Scale is half of brightness variation so it doesn't dominate
    float sigma_roll = 1.0 + crt_scanline_roll_strength * roll_raw * 0.5;

    // Corner beam ellipticity: sigma grows with distance from screen centre.
    // On a real CRT the beam strikes phosphor at increasing angle toward edges,
    // making the spot elliptical. Modelled as sigma *= (1 + spread * r²)
    // where r is normalised distance from centre in [0,1].
    float corner_r2 = 0.0;
    if (crt_beam_corner_spread > 0.001)
    {
        float2 tc_c  = texcoord - 0.5; // [-0.5, 0.5]
        float  ar    = float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);
        // Weight x more heavily since horizontal deflection causes vertical spread
        corner_r2 = tc_c.x * tc_c.x * ar * ar + tc_c.y * tc_c.y;
        corner_r2 = saturate(corner_r2 * 4.0); // normalise so corner = ~1.0
    }
    float corner_sigma_scale = 1.0 + crt_beam_corner_spread * corner_r2;

    #if ENABLE_BEAM_MODULATION
        float sigma_scale = 1.0 / max(scan_width, 1.0);
        float r_sigma = lerp(crt_beam_min_sigma, crt_beam_max_sigma, saturate(c_lin.r)) * sigma_scale * sigma_roll * corner_sigma_scale;
        float g_sigma = lerp(crt_beam_min_sigma, crt_beam_max_sigma, saturate(c_lin.g)) * sigma_scale * sigma_roll * corner_sigma_scale;
        float b_sigma = lerp(crt_beam_min_sigma, crt_beam_max_sigma, saturate(c_lin.b)) * sigma_scale * sigma_roll * corner_sigma_scale;
        // Analytical Gaussian integral -- no stairstepping
        // crt_beam_shape=2 uses fast erf path; higher values use generalized Gaussian
        float beam_r = gen_gauss_integral(f, hw, r_sigma, crt_beam_shape) * roll;
        float beam_g = gen_gauss_integral(f, hw, g_sigma, crt_beam_shape) * roll;
        float beam_b = gen_gauss_integral(f, hw, b_sigma, crt_beam_shape) * roll;
    #else
        // Analytical integral with megatron scanline shaping
        float gi_s   = gen_gauss_integral(f, hw, crt_scanline_sigma * sigma_roll * corner_sigma_scale, crt_beam_shape) * roll;
        float bd     = abs(f) * 2.0;
        float beam_r = megatron_scanline(c_lin.r,bd,crt_r_scanline_min,crt_r_scanline_max,crt_r_scanline_attack) * gi_s;
        float beam_g = megatron_scanline(c_lin.g,bd,crt_g_scanline_min,crt_g_scanline_max,crt_g_scanline_attack) * gi_s;
        float beam_b = megatron_scanline(c_lin.b,bd,crt_b_scanline_min,crt_b_scanline_max,crt_b_scanline_attack) * gi_s;
    #endif

    #if ENABLE_SCANLINE_SS
    // -- Rotated-grid supersampling of the scanline image (RGSS 4x) --
    // True supersampling: each tap contributes its own COLOUR weighted by the
    // beam at its subpixel position. This softens the content edge itself
    // across the pixel footprint, which is where the diagonal staircase lives
    // (averaging beam weights alone does not move the colour edge).
    // Taps replicate the grading chain (colour temp -> BCS -> linear) and the
    // centre's mask factor is applied to the averaged result, matching the
    // single-sample path.
    // Effective SS amount, optionally gated by local gradient coherence so
    // texture detail is left single-sampled while diagonal edges get full AA.
    //
    // Base sampling coordinate must match the main fetch path: with geometry
    // warp on, the single-sample colour comes from geom_warp(texcoord), so the
    // SS taps must read from the same warped position or the blend produces a
    // double image that grows toward the corners (max warp displacement).
    // With preblur on, the preblur texture is already warped so texcoord maps
    // directly. Offsets are applied post-warp; the warp Jacobian is ~identity
    // at subpixel scale so this is accurate for the RGSS jitter.
    #if (ENABLE_PREBLUR == 0) && ENABLE_GEOMETRY
        float2 ss_base = geom_warp(texcoord); // match warped main fetch
    #else
        float2 ss_base = texcoord;            // preblur tex already warped, or no warp
    #endif

    float ss_amount = crt_scanline_ss_strength;
    if (crt_scanline_ss_strength > 0.001 && crt_scanline_ss_coherence > 0.001)
    {
        float2 spx = ReShade::PixelSize;
        #if ENABLE_PREBLUR
        #define CRT_SSL(dx, dy) dot(max(tex2D(crt_preblur_v_sampler, ss_base + float2(dx, dy) * spx).rgb, 0.0), float3(0.2126, 0.7152, 0.0722))
        #else
        #define CRT_SSL(dx, dy) dot(max(tex2D(ReShade::BackBuffer, ss_base + float2(dx, dy) * spx).rgb, 0.0), float3(0.2126, 0.7152, 0.0722))
        #endif
        float sl00 = CRT_SSL(-1.0,-1.0); float sl10 = CRT_SSL(0.0,-1.0); float sl20 = CRT_SSL(1.0,-1.0);
        float sl01 = CRT_SSL(-1.0, 0.0);                                 float sl21 = CRT_SSL(1.0, 0.0);
        float sl02 = CRT_SSL(-1.0, 1.0); float sl12 = CRT_SSL(0.0, 1.0); float sl22 = CRT_SSL(1.0, 1.0);
        #undef CRT_SSL
        // Four sub-gradients feed the structure tensor
        float4 ssgx = float4(sl10-sl00, sl20-sl10, sl12-sl02, sl22-sl12);
        float4 ssgy = float4(sl01-sl00, sl21-sl20, sl02-sl01, sl22-sl21);
        float Jxx = dot(ssgx, ssgx);
        float Jyy = dot(ssgy, ssgy);
        float Jxy = dot(ssgx, ssgy);
        float tr  = Jxx + Jyy;
        float aniso = (tr > 1e-6)
                    ? sqrt((Jxx - Jyy)*(Jxx - Jyy) + 4.0*Jxy*Jxy) / tr
                    : 0.0;
        // Coherent edge -> keep full SS; incoherent texture -> pull SS toward 0.
        float edge = smoothstep(0.35, 0.75, aniso);
        ss_amount = lerp(crt_scanline_ss_strength,
                         crt_scanline_ss_strength * edge,
                         crt_scanline_ss_coherence);
    }

    if (ss_amount > 0.001 && crt_scanline_strength > 0.001)
    {
        // Classic RGSS pattern: rotated so no two samples share a row/column
        static const float2 rgss[4] = {
            float2( 0.125,  0.375), float2( 0.375, -0.125),
            float2(-0.125, -0.375), float2(-0.375,  0.125)
        };

        float3 ss_acc = 0.0;
        [unroll] for (int si = 0; si < 4; si++)
        {
            // Source tap at subpixel offset, in the same (warped) space as the
            // main fetch so the supersampled result aligns with the single sample.
            float2 ss_uv = ss_base + rgss[si] * ReShade::PixelSize;
            #if ENABLE_PREBLUR
            float3 ss_c  = tex2D(crt_preblur_v_sampler, ss_uv).rgb;
            #else
            float3 ss_c  = tex2D(ReShade::BackBuffer, ss_uv).rgb;
            #endif
            ss_c = max(ss_c, 0.0);

            // Replicate grading chain so taps match the centre signal
            if (abs(crt_colour_temp) > 0.001)
                ss_c = apply_colour_temp(ss_c, crt_colour_temp);
            if (abs(crt_brightness)>0.001 || abs(crt_contrast)>0.001 || abs(crt_saturation)>0.001)
            {
                #if PIPELINE >= 1
                float3 ss_bcs = to_linear(ss_c);
                ss_bcs = apply_bcs(ss_bcs, crt_brightness, crt_contrast, crt_saturation);
                ss_c   = from_linear(max(ss_bcs, 0.0));
                #else
                ss_c   = apply_bcs(ss_c, crt_brightness, crt_contrast, crt_saturation);
                #endif
            }
            float3 ss_lin = crt_to_linear(ss_c);

            // Vertical beam position at this sample's y offset
            float ss_y  = floor(fc.y) + 0.5 + rgss[si].y;
            float ss_f  = frac(ss_y / scan_width) - 0.5;

            float3 ss_beam;
            #if ENABLE_BEAM_MODULATION
            float ss_rs = lerp(crt_beam_min_sigma, crt_beam_max_sigma, saturate(ss_lin.r)) * sigma_scale * sigma_roll * corner_sigma_scale;
            float ss_gs = lerp(crt_beam_min_sigma, crt_beam_max_sigma, saturate(ss_lin.g)) * sigma_scale * sigma_roll * corner_sigma_scale;
            float ss_bs = lerp(crt_beam_min_sigma, crt_beam_max_sigma, saturate(ss_lin.b)) * sigma_scale * sigma_roll * corner_sigma_scale;
            ss_beam.r = gen_gauss_integral(ss_f, hw, ss_rs, crt_beam_shape) * roll;
            ss_beam.g = gen_gauss_integral(ss_f, hw, ss_gs, crt_beam_shape) * roll;
            ss_beam.b = gen_gauss_integral(ss_f, hw, ss_bs, crt_beam_shape) * roll;
            #else
            float ss_gi = gen_gauss_integral(ss_f, hw, crt_scanline_sigma * sigma_roll * corner_sigma_scale, crt_beam_shape) * roll;
            float ss_bd = abs(ss_f) * 2.0;
            ss_beam.r = megatron_scanline(ss_lin.r, ss_bd, crt_r_scanline_min, crt_r_scanline_max, crt_r_scanline_attack) * ss_gi;
            ss_beam.g = megatron_scanline(ss_lin.g, ss_bd, crt_g_scanline_min, crt_g_scanline_max, crt_g_scanline_attack) * ss_gi;
            ss_beam.b = megatron_scanline(ss_lin.b, ss_bd, crt_b_scanline_min, crt_b_scanline_max, crt_b_scanline_attack) * ss_gi;
            #endif

            // Colour x beam, with scanline strength applied per tap
            ss_acc += ss_lin * lerp(1.0, ss_beam, crt_scanline_strength);
        }
        ss_acc *= 0.25;

        // Apply the centre pixel's mask factor (matches single-sample path,
        // where mask multiplies c_lin before the scanline block)
        #if ENABLE_MASK
        ss_acc = ss_acc * mask * crt_mask_boost;
        #endif

        // Blend: single-sample scanline result vs supersampled result
        float3 c_single = c_lin * lerp(1.0, float3(beam_r, beam_g, beam_b), crt_scanline_strength);
        c_lin = lerp(c_single, ss_acc, ss_amount);
    }
    else
    {
        c_lin *= lerp(1.0, float3(beam_r, beam_g, beam_b), crt_scanline_strength);
    }
    #else
    c_lin *= lerp(1.0, float3(beam_r, beam_g, beam_b), crt_scanline_strength);
    #endif // ENABLE_SCANLINE_SS

    // -- Interlaced field blanking --
    // Alternate between odd and even scanline fields each frame, matching
    // how real CRT interlacing works: one field of scanlines is bright,
    // the other is dark, alternating every frame to create field-rate flicker.
    //
    // Blanking operates on scanline periods (not pixels) so it works correctly
    // at any scanline width. Uses the same scan_width as the scanline calculation.
    #if ENABLE_INTERLACE
    if (crt_interlace_strength > 0.001)
    {
        // Which field is this frame: 0 or 1, alternates every frame.
        // When BFI/decay is active, FRAMECOUNT increments every frame including
        // dark frames -- so lit frames may always land on even or odd FRAMECOUNT.
        // Divide by BFI cycle length so the field alternates per lit frame pair.
        #if ENABLE_DECAY
        uint  frame_field  = (FRAMECOUNT / uint(max(crt_decay_frames, 2))) & 1u;
        #else
        uint  frame_field  = FRAMECOUNT & 1u;
        #endif

        // Which scanline period does this pixel belong to: even or odd.
        // Snap scan_width to nearest integer so periods are whole pixels --
        // non-integer widths cause drift in the alternating pattern.
        float snap_width   = max(round(scan_width), 1.0);
        uint  scanline_idx = uint(fc.y / snap_width);
        uint  scan_field   = scanline_idx & 1u;

        // gate=1: full brightness (this field's scanline). gate=0: dimmed.
        float gate = (scan_field == frame_field) ? 1.0 : 0.0;
        float dim  = lerp(1.0, gate, crt_interlace_strength);
        c_lin *= dim;
    }
    #endif

    // -- Spot size / overbrightness --
    // Luminance-squared boost: dark pixels unaffected, bright pixels boosted.
    // Applied directly to c_lin before gamma re-encoding.
    // Debug: at spot_size=3.0 with full-white input, output is 4x brightness.
    if (crt_spot_size > 0.001)
    {
        float luma_s    = dot(c_lin, float3(0.2126, 0.7152, 0.0722));
        float luma_norm = saturate(luma_s); // clamp for gate
        float boost     = 1.0 + crt_spot_size * luma_norm * luma_norm;
        c_lin *= boost;
    }

    // -- Electron beam horizontal bloom --
    // On real CRTs, high-current beams (bright content) spread horizontally
    // due to space charge repulsion between electrons. Simulated as a
    // luminance-gated 3-tap horizontal blur on the post-scanline signal.
    if (crt_beam_h_bloom > 0.001)
    {
        float  luma_bl  = dot(c_lin, float3(0.2126, 0.7152, 0.0722));
        // Gate: only active above 70% luma, full effect above 90%
        float  gate_bl  = smoothstep(0.7, 0.9, luma_bl);
        if (gate_bl > 0.001)
        {
            float  bpx  = ReShade::PixelSize.x;
            float3 cl   = tex2D(ReShade::BackBuffer, texcoord - float2(bpx, 0.0)).rgb;
            float3 cr   = tex2D(ReShade::BackBuffer, texcoord + float2(bpx, 0.0)).rgb;
            // Convert neighbours to linear
            cl = glin(cl); cr = glin(cr);
            // Gaussian 3-tap: weights 0.25, 0.5, 0.25
            float3 bloomed = cl * 0.25 + c_lin * 0.5 + cr * 0.25;
            c_lin = lerp(c_lin, bloomed, gate_bl * crt_beam_h_bloom);
        }
    }

    // -- Re-encode --
    c = crt_from_linear(c_lin);

    // -- Brightboost (hue-preserving) --
    if (crt_bb_mode == 0)
    {
        // Peak channel mode: colour-agnostic, correct for CRT phosphor physics
        float bb_ref    = max(max(c.r, c.g), c.b);
        float bb_gain   = lerp(crt_bb_dark, crt_bb_bright, bb_ref);
        float bb_out    = bb_ref * bb_gain;
        float bb_ratio0 = (bb_ref > 0.0001) ? max(bb_out / bb_ref, 0.0) : 1.0;
        c = max(c * bb_ratio0, 0.0);
    }
    else if (crt_bb_mode == 1)
    {
        // Luma mode: perceptually weighted (Rec.709), may under-represent blue
        float bb_luma   = dot(max(c, 0.0), float3(0.2126, 0.7152, 0.0722));
        float bb_ref    = max(max(c.r, c.g), c.b);
        float bb_gain   = lerp(crt_bb_dark, crt_bb_bright, bb_ref);
        float bb_out    = bb_luma * bb_gain;
        float bb_ratio  = (bb_luma > 0.0001) ? max(bb_out / bb_luma, 0.0) : 1.0;
        c = max(c * bb_ratio, 0.0);
    }
    else
    {

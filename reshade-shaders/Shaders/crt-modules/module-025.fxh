    #if ENABLE_PREBLUR
    c = float3(
        tex2D(crt_preblur_v_sampler, uv_r).r,
        tex2D(crt_preblur_v_sampler, uv_g).g,
        tex2D(crt_preblur_v_sampler, uv_b).b);

    // -- Vertical per-channel spread (ENABLE_PREBLUR + ENABLE_CONVERGENCE path) --
    #if ENABLE_CONVERGENCE
    if (crt_convergence_v_spread > 0.001)
    {
        float py = ReShade::PixelSize.y * crt_convergence_v_spread;
        float r_above = tex2D(crt_preblur_v_sampler, float2(uv_r.x, uv_r.y - py*0.5)).r;
        float r_below = tex2D(crt_preblur_v_sampler, float2(uv_r.x, uv_r.y + py*0.5)).r;
        float b_above = tex2D(crt_preblur_v_sampler, float2(uv_b.x, uv_b.y - py*0.3)).b;
        float b_below = tex2D(crt_preblur_v_sampler, float2(uv_b.x, uv_b.y + py*0.3)).b;
        c.r = (c.r + r_above + r_below) / 3.0;
        c.b = (c.b + b_above + b_below) / 3.0;
    }
    #endif // ENABLE_CONVERGENCE
    #elif ENABLE_GEOMETRY
    {
        // Geometry: one Lanczos reconstruction at warped centre position,
        // then cheap bilinear reads for CA/convergence channel offsets.
        // This avoids 3x Lanczos cost -- the CA/convergence offsets are
        // sub-pixel and bilinear is sufficient for them.
        float2 tc_w = geom_warp(texcoord);
        float3 c_warp = geom_sample_lanczos2(ReShade::BackBuffer, tc_w);
        // For CA/convergence: read neighbours bilinearly and extract channels
        c = c_warp; // start with Lanczos centre
        #if ENABLE_CA || ENABLE_CONVERGENCE
        float  py_off = ReShade::PixelSize.y;
        float2 wuv_r  = tc_w + ca_r + float2(0.0,
            #if ENABLE_CONVERGENCE
            (crt_convergence_r - radial_err) * py_off
            #else
            0.0
            #endif
            );
        float2 wuv_b  = tc_w + ca_b + float2(0.0,
            #if ENABLE_CONVERGENCE
            (crt_convergence_b + radial_err) * py_off
            #else
            0.0
            #endif
            );
        c.r = tex2D(ReShade::BackBuffer, wuv_r).r;
        c.b = tex2D(ReShade::BackBuffer, wuv_b).b;
        #endif
    }
    #else
    // No geometry, no preblur: plain bilinear -- fast path
    c = float3(
        tex2D(ReShade::BackBuffer, uv_r).r,
        tex2D(ReShade::BackBuffer, uv_g).g,
        tex2D(ReShade::BackBuffer, uv_b).b);
    #endif

    // -- Horizontal beam reconstruction --
    // Analytic generalized-Gaussian integral of the electron spot along the
    // horizontal axis. Each neighbour tap is weighted by the integral of the
    // beam profile over that tap's one-pixel footprint -- the same model as the
    // vertical scanline beam (gen_gauss_integral), applied horizontally.
    // Operates on the source signal in the same space as the main fetch.
    #if ENABLE_BEAM_H
    if (crt_beam_h_strength > 0.001)
    {
        float  hpx = ReShade::PixelSize.x;
        // Base coordinate matches the main fetch path (warp/preblur aware)
        #if (ENABLE_PREBLUR == 0) && ENABLE_GEOMETRY
            float2 hb_base = geom_warp(texcoord);
        #else
            float2 hb_base = texcoord;
        #endif

        // Half-footprint of one pixel in the same units gen_gauss_integral uses
        // (it integrates the profile over [f-hw, f+hw] with hw = 0.5 = half a
        // pixel). Position f is measured in pixels from the centre tap.
        const float hb_hw = 0.5;

        float3 hb_acc = 0.0;
        float  hb_wsum = 0.0;
        [unroll] for (int hi = -HBEAM_TAPS; hi <= HBEAM_TAPS; hi++)
        {
            float fpos = float(hi); // pixels from centre
            // Beam weight = integral of generalized Gaussian over this pixel
            float w = gen_gauss_integral(fpos, hb_hw, crt_beam_h_sigma, crt_beam_shape);

            #if ENABLE_PREBLUR
            float3 s = tex2D(crt_preblur_v_sampler, hb_base + float2(fpos * hpx, 0.0)).rgb;
            #else
            float3 s = tex2D(ReShade::BackBuffer, hb_base + float2(fpos * hpx, 0.0)).rgb;
            #endif
            hb_acc  += max(s, 0.0) * w;
            hb_wsum += w;
        }
        float3 hb_result = (hb_wsum > 1e-6) ? hb_acc / hb_wsum : c;
        c = lerp(c, hb_result, crt_beam_h_strength);
    }
    #endif // ENABLE_BEAM_H

    // -- Composite video: chroma blur + luma sharpen on correct source --
    // Runs after source sampling so it operates on the actual current frame
    // with correct UV mapping (preblur/geometry/plain as appropriate).
    #if ENABLE_COMPOSITE
    if (crt_composite_chroma_blur > 0.001 || crt_composite_luma_sharpen > 0.001)
    {
        float luma = dot(c, float3(0.299, 0.587, 0.114));
        float px_c = ReShade::PixelSize.x;

        if (crt_composite_chroma_blur > 0.001)
        {
            int    taps      = int(ceil(crt_composite_chroma_blur * 2.0));
            float3 chroma_sum = 0.0;
            for (int ci = -taps; ci <= taps; ci++)
            {
                float  offs = (float(ci) + crt_composite_chroma_phase) * px_c;
                #if ENABLE_PREBLUR
                chroma_sum += float3(
                    tex2D(crt_preblur_v_sampler, uv_r + float2(offs, 0.0)).r,
                    tex2D(crt_preblur_v_sampler, uv_g + float2(offs, 0.0)).g,
                    tex2D(crt_preblur_v_sampler, uv_b + float2(offs, 0.0)).b);
                #else
                chroma_sum += float3(
                    tex2D(ReShade::BackBuffer, uv_r + float2(offs, 0.0)).r,
                    tex2D(ReShade::BackBuffer, uv_g + float2(offs, 0.0)).g,
                    tex2D(ReShade::BackBuffer, uv_b + float2(offs, 0.0)).b);
                #endif
            }
            float3 c_blurred    = chroma_sum / float(2*taps + 1);
            float  luma_blurred = dot(c_blurred, float3(0.299, 0.587, 0.114));
            float  luma_ratio   = (luma_blurred > 0.0001) ? luma / luma_blurred : 1.0;
            c = c_blurred * luma_ratio;
        }

        if (crt_composite_luma_sharpen > 0.001)
        {
            #if ENABLE_PREBLUR
            float3 left  = tex2D(crt_preblur_v_sampler, uv_g - float2(px_c * 2.0, 0.0));
            float3 right = tex2D(crt_preblur_v_sampler, uv_g + float2(px_c * 2.0, 0.0));
            #else
            float3 left  = tex2D(ReShade::BackBuffer, uv_g - float2(px_c * 2.0, 0.0));
            float3 right = tex2D(ReShade::BackBuffer, uv_g + float2(px_c * 2.0, 0.0));
            #endif
            float luma_l    = dot(left,  float3(0.299, 0.587, 0.114));
            float luma_r    = dot(right, float3(0.299, 0.587, 0.114));
            float edge      = luma - 0.5*(luma_l + luma_r);
            float luma_sharp = max(luma + edge * crt_composite_luma_sharpen, 0.0001);
            c *= luma_sharp / max(luma, 0.0001);
            c  = max(c, 0.0);
        }
    }
    #endif // ENABLE_COMPOSITE

    // -- Phosphor profile correction (before BCS) --
    #if ENABLE_PHOSPHOR
    if (crt_phosphor_strength > 0.001)
        c = apply_phosphor(c);

    // -- White point: chromatic adaptation D65 toward D55 (warm) or D93 (cool) --
    if (abs(crt_white_point) > 0.001)
    {
        float3 c_lin = pow(max(c, 0.0), 2.2);
        float m = abs(crt_white_point);
        float3 xyz;
        if (crt_white_point < 0.0)
            xyz = mul(c_lin, kD65_to_D55);
        else
            xyz = mul(c_lin, kD65_to_D93);
        // Back to sRGB via standard XYZ->sRGB
        float3 adapted = mul(xyz, kXYZ_to_sRGB);
        adapted = pow(max(adapted, 0.0), 1.0/2.2);
        c = lerp(c, adapted, m);
    }

    // -- Colour temperature (simple warm/cool shift in Gamma & Contrast) --
    if (abs(crt_colour_temp) > 0.001)
        c = apply_colour_temp(c, crt_colour_temp);
    #endif

    // -- Pre-emphasis / bandwidth limiting --
    // Applied to source signal before any CRT processing, matching the
    // signal chain position of real broadcast pre/de-emphasis.
    #if ENABLE_EDGE_FEEDBACK
    if (crt_edge_feedback_luma > 0.001 || crt_edge_feedback_chroma > 0.001)
    {
        // Cross-frame edge feedback: compare current pixel against previous
        // frame neighbours. Difference captures accumulated CRT processing
        // (mask, scanlines, vignette, warp) and feeds it back as enhancement.
        float2 px    = ReShade::PixelSize;
        float3 left  = tex2D(ReShade::BackBuffer, float2(texcoord.x - px.x, texcoord.y)).rgb;
        float3 right = tex2D(ReShade::BackBuffer, float2(texcoord.x + px.x, texcoord.y)).rgb;
        if (crt_edge_feedback_luma > 0.001)
        {
            float luma_c = dot(c,     float3(0.299, 0.587, 0.114));
            float luma_l = dot(left,  float3(0.299, 0.587, 0.114));
            float luma_r = dot(right, float3(0.299, 0.587, 0.114));
            float edge   = luma_c - 0.5*(luma_l + luma_r);
            c += edge * crt_edge_feedback_luma;
        }
        if (crt_edge_feedback_chroma > 0.001)
        {
            float luma         = dot(c, float3(0.299, 0.587, 0.114));
            float3 chroma_blur = (left + c + right) / 3.0;
            float luma_blur    = dot(chroma_blur, float3(0.299, 0.587, 0.114));
            c = chroma_blur + (luma - luma_blur);
            c = lerp(c, chroma_blur, crt_edge_feedback_chroma);
        }
        c = max(c, 0.0);
    }
    #endif // ENABLE_EDGE_FEEDBACK



    // -- BCS (Megatron Bezier in Yxy, no washout) --
    // In PIPELINE >= 1 the soop sandwich re-encodes to sRGB before this point.
    // apply_bcs expects a linear-ish input -- decode to linear first, then
    // re-encode after so the Bezier curve operates in the correct domain.
    if (abs(crt_brightness)>0.001 || abs(crt_contrast)>0.001 || abs(crt_saturation)>0.001)
    {
        #if PIPELINE >= 1
        float3 c_bcs_lin = to_linear(max(c, 0.0));
        c_bcs_lin = apply_bcs(c_bcs_lin, crt_brightness, crt_contrast, crt_saturation);
        c = from_linear(max(c_bcs_lin, 0.0));
        #else
        c = apply_bcs(c, crt_brightness, crt_contrast, crt_saturation);
        #endif
    }

    // -- CRT gamma decode --
    float3 c_lin = crt_to_linear(c);
    // Source colour and luma stored before any CRT processing.
    // Post-scanline c_lin is near-zero in dark gaps -- cannot use for detail work.
    float  c_src_luma = dot(max(c_lin, 0.0), float3(0.2126, 0.7152, 0.0722));

    // -- Aperture grille mask --
    #if ENABLE_MASK
        // Moiré dither: small random sub-pixel phase offset per 16x16 tile.
        // Breaks strict mask periodicity that causes moiré with certain image
        // frequencies (Haeberli & Segal 1990).
        float2 tile_id  = floor(fc / 16.0);
        uint   tile_rng = grain_uhash(grain_uhash(uint(tile_id.y)) + uint(tile_id.x));
        float  dither_x = (float(tile_rng & 0xFFu) / 255.0 - 0.5) * crt_mask_dither;
        float2 fc_mask = fc + float2(phase_h + orbit_offs.x + dither_x, orbit_offs.y);
        float  mask_pixel_luma = dot(max(c, 0.0), float3(0.2126, 0.7152, 0.0722));
        float3 mask = crt_mask_apply(fc_mask, crt_triad_width, crt_mask_strength,
                                    crt_phosphor_sharpness, crt_phosphor_colour,
                                    crt_mask_type, crt_slot_mask_strength,
                                    crt_mask_offset_x, crt_mask_offset_y, fc,
                                    mask_pixel_luma);
        // Phosphor dot structure: subtle per-dot luminance variation
        if (crt_phosphor_dot > 0.001)
        {
            // Spatially-correlated noise: average hash over a 3x3 neighbourhood
            // in mask-cell space so adjacent phosphors vary smoothly.
            // Slow temporal drift every 10 minutes for burn-in protection.
            uint  drift    = uint(CRT_TIMER / 600000.0);
            uint2 mc       = uint2(uint(fc_mask.x), uint(fc_mask.y));
            float dot_acc  = 0.0;
            for (int ddy = -1; ddy <= 1; ddy++)
            for (int ddx = -1; ddx <= 1; ddx++)
            {
                uint2 nb   = mc + uint2(ddx, ddy);
                uint  seed = nb.x * 2333u + nb.y * 3571u + drift * 0xB5297A4Du;
                dot_acc   += grain_unorm1(grain_uhash(seed));
            }
            float dot_var  = (dot_acc / 9.0 - 0.5) * 2.0; // normalise to [-1,+1]
            mask *= 1.0 + dot_var * crt_phosphor_dot;
            mask  = max(mask, 0.0);
        }
        c_lin = c_lin * mask * crt_mask_boost;
    #endif

    // -- Scanlines with sub-pixel AA --
    // No vertical burn-in offset applied -- any vertical shift changes brightness
    // because frac() maps non-linearly to the gaussian beam profile.
    // Horizontal mask shift (phase_h + orbit_h) handles burn-in protection instead.
    // Resolution-independent scanline width.
    // When SCANLINE_REFERENCE_HEIGHT > 0, scale width proportionally so
    // the same crt_scanline_width value produces identical-looking scanlines
    // at any render resolution.
    #if SCANLINE_REFERENCE_HEIGHT > 0
    float scan_width = crt_scanline_width *
                       (float(BUFFER_HEIGHT) / float(SCANLINE_REFERENCE_HEIGHT));
    #else
    float scan_width = crt_scanline_width;
    #endif
    // Snap to nearest integer: non-integer scan_width causes some rows to
    // get f near 0 (bright) and others near ±0.5 (dark), producing oscillating
    // scanline sizes and inconsistent mask darkness as width increases.

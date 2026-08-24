            bool is_lit;
            float litGain;
            if (crt_decay_invert_cycle && frames > 2)
            {
                is_lit  = (frame_in_cycle != 0);
                // duty cycle = (frames-1)/frames, compensate: gain * frames/(frames-1)
                litGain = float(frames) * crt_decay_gain / max(float(frames - 1), 1.0);
            }
            else
            {
                is_lit  = (frame_in_cycle == 0);
                litGain = float(frames) * crt_decay_gain;
            }

            if (crt_decay_sine_bfi)
            {
                // Sine BFI: cosine phase. Invert shifts the peak to dark frame.
                float phase = (float(frame_in_cycle) / float(frames)) * 2.0 * 3.14159265;
                if (crt_decay_invert_cycle && frames > 2) phase += 3.14159265; // shift peak
                float sine_gain = lerp(crt_decay_dark_floor, litGain, 0.5 + 0.5 * cos(phase));
                #if PIPELINE >= 1
                    float3 lin = soop_inv_reinhard(c, crt_soop_shadow_gamma);
                    lin *= sine_gain;
                    out_color = soop_reinhard(lin, crt_soop_peak_nits, crt_soop_shadow_gamma);
                #else
                    float3 lin = bb_srgb2linear(c);
                    lin *= sine_gain;
                    out_color = clamp(bb_linear2srgb(lin), 0.0, 1.0);
                #endif
            }
            else if (is_lit)
            {
                // Lit frame: gain applied in linear space.
                #if PIPELINE >= 1
                    float3 lin = soop_inv_reinhard(c, crt_soop_shadow_gamma);
                    lin *= litGain;
                    out_color = soop_reinhard(lin, crt_soop_peak_nits, crt_soop_shadow_gamma);
                #else
                    float3 lin = bb_srgb2linear(c);
                    lin *= litGain;
                    out_color = clamp(bb_linear2srgb(lin), 0.0, 1.0);
                #endif
            }
            else
            {
                // Dark frame: flat floor or blended floor.
                if (crt_decay_dark_blend && crt_decay_dark_floor > 0.0)
                {
                    float3 prev = tex2D(crt_decay_prev1_sampler, texcoord).rgb;
                    out_color = lerp(prev, c, 0.5) * crt_decay_dark_floor;
                }
                else
                {
                    out_color = float3(crt_decay_dark_floor, crt_decay_dark_floor, crt_decay_dark_floor);
                }
            }
    }
    else
    {
            // ====================================================
            // Method 1: Variable MPRT (Blur Busters - SDR only)
            //
            // WARNING: This method uses the sRGB transfer function
            // (bb_srgb2linear / bb_linear2srgb) internally. It assumes
            // the backbuffer is standard gamma-encoded sRGB (PIPELINE 0).
            // On PIPELINE 1/2 the backbuffer holds Reinhard-compressed
            // scRGB -- decoding it with sRGB gamma produces wrong values
            // and remaps highlights incorrectly. Use BFI (method 2) for
            // PIPELINE 1/2.
            //
            // tubePos OFF: standard BFI in linear space. Default, 120Hz safe.
            // tubePos ON:  BB spatial overlap integral. 240Hz+ only.
            // ====================================================
            #if PIPELINE >= 1
            // Pipeline mismatch: output a red tint as a visible warning.
            // Switch to Decay Method = BFI to fix this.
            out_color = float3(c.r * 0.5 + 0.5, c.g * 0.3, c.b * 0.3);
            #else
            float3 pixelCurr      = bb_srgb2linear(c);
            float  brightnessScale = float(frames) * crt_decay_gain;

            if (!crt_decay_tube_pos)
            {
                // Apply same invert logic as method 2.
                bool m1_is_lit;
                float m1_scale;
                if (crt_decay_invert_cycle && frames > 2)
                {
                    m1_is_lit = (frame_in_cycle != 0);
                    m1_scale  = brightnessScale / max(float(frames - 1), 1.0);
                }
                else
                {
                    m1_is_lit = (frame_in_cycle == 0);
                    m1_scale  = brightnessScale;
                }

                if (crt_decay_sine_bfi)
                {
                    float phase = (float(frame_in_cycle) / float(frames)) * 2.0 * 3.14159265;
                    if (crt_decay_invert_cycle && frames > 2) phase += 3.14159265;
                    float sine_gain = lerp(crt_decay_dark_floor, m1_scale, 0.5 + 0.5 * cos(phase));
                    out_color = clamp(bb_linear2srgb(pixelCurr * sine_gain), 0.0, 1.0);
                }
                else if (m1_is_lit)
                    out_color = clamp(bb_linear2srgb(pixelCurr * m1_scale), 0.0, 1.0);
                else
                {
                    if (crt_decay_dark_blend && crt_decay_dark_floor > 0.0)
                    {
                        float3 prev = tex2D(crt_decay_prev1_sampler, texcoord).rgb;
                        out_color = lerp(prev, c, 0.5) * crt_decay_dark_floor;
                    }
                    else
                        out_color = float3(crt_decay_dark_floor, crt_decay_dark_floor, crt_decay_dark_floor);
                }
            }
            else
            {
                #if !DECAY_BB_INTEGRAL
                // Tube Position mode requires DECAY_BB_INTEGRAL=1 (extra history
                // textures). Fall back to standard lit/dark BFI so output stays
                // sensible; set the preprocessor to enable the overlap integral.
                if (frame_in_cycle == 0)
                    out_color = clamp(bb_linear2srgb(pixelCurr * brightnessScale), 0.0, 1.0);
                else
                    out_color = float3(crt_decay_dark_floor, crt_decay_dark_floor, crt_decay_dark_floor);
                #else
                // BB overlap integral -- only valid with spatially-varying tubePos.
                float3 pixelPrev1 = bb_srgb2linear(tex2D(crt_decay_prev1_sampler, texcoord).rgb);
                float3 pixelPrev2 = bb_srgb2linear(tex2D(crt_decay_prev2_sampler, texcoord).rgb);

                float3 colorCurr  = pixelCurr  * brightnessScale;
                float3 colorPrev1 = pixelPrev1 * brightnessScale;
                float3 colorPrev2 = pixelPrev2 * brightnessScale;

                float crtRasterPos = float(frame_in_cycle) / float(frames);
                float tubePos      = 1.0 - texcoord.y;
                float tubeFrame    = tubePos * float(frames);
                float fStart       = crtRasterPos * float(frames);
                float fEnd         = fStart + 1.0;

                #define BB_CH_FUNC(Lc, Lp1, Lp2) \
                    max(0.0, min((tubeFrame - float(frames)) + (Lp2), fEnd) - max(tubeFrame - float(frames), fStart)) + \
                    max(0.0, min(tubeFrame + (Lp1), fEnd) - max(tubeFrame, fStart)) + \
                    max(0.0, min(tubeFrame + float(frames) + (Lc), fEnd) - max(tubeFrame + float(frames), fStart))

                // Scene-change: compare against the raw pre-decay game frame,
                // NOT prev1 (which holds post-decay output -- alternating lit/black --
                // and would fire the detector on every dark frame in the cycle).
                float3 rawPrev = bb_srgb2linear(tex2D(crt_decay_raw_sampler, texcoord).rgb);
                float lumaC    = dot(pixelCurr, float3(0.2126, 0.7152, 0.0722));
                float lumaP1   = dot(rawPrev,   float3(0.2126, 0.7152, 0.0722));

                float3 result;
                if (abs(lumaC - lumaP1) > crt_decay_scene_threshold)
                {
                    result = pixelCurr * brightnessScale;
                }
                else
                {
                    result = float3(
                        BB_CH_FUNC(colorCurr.r, colorPrev1.r, colorPrev2.r),
                        BB_CH_FUNC(colorCurr.g, colorPrev1.g, colorPrev2.g),
                        BB_CH_FUNC(colorCurr.b, colorPrev1.b, colorPrev2.b)
                    );
                }
                #undef BB_CH_FUNC

                out_color = clamp(bb_linear2srgb(result), 0.0, 1.0);
                #endif // DECAY_BB_INTEGRAL
            }
            #endif // PIPELINE >= 1 mismatch guard
    }

    color = float4(out_color, 1.0);
}


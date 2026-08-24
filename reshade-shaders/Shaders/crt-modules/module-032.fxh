// ============================================================

technique CRT_Standalone <
    ui_label = "CRT Standalone";
    ui_tooltip = "Pre-blur (H+V) + mask + Megatron beam + gamma + brightboost + glow + grain.";
>
{
    #if PIPELINE >= 1
    pass SoopBefore
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_soop_before_PS;
    }
    #endif
    #if ENABLE_PREBLUR
    pass PreBlurH
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_preblur_h_PS;
        RenderTarget = crt_preblur_h_tex;
    }
    pass PreBlurV
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_preblur_v_PS;
        RenderTarget = crt_preblur_v_tex;
    }
    #endif
    #if ENABLE_HALATION
    pass HalationH
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_halation_PS;
        RenderTarget = crt_halation_tex;
    }
    pass HalationV
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_halation_v_PS;
        RenderTarget = crt_halation_v_tex;
    }
    #endif
    pass GlowH
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_glow_h_PS;
        RenderTarget = crt_glow_tex;
    }
    pass GlowV
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_glow_v_PS;
        RenderTarget = crt_glow_v_tex;
    }
    pass GlowWideH
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_glow_wide_h_PS;
        RenderTarget = crt_glow_wide_tex;
    }
    pass GlowWideV
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_glow_wide_v_PS;
        RenderTarget = crt_glow_wide_v_tex;
    }
    pass MainCRT
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_main_PS;
    }
    #if ENABLE_SHARPEN
    pass Sharpen
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_sharpen_PS;
    }
    #endif
    #if ENABLE_SCANLINE_SOFTEN
    pass ScanlineSoften
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_soften_PS;
    }
    #endif
    #if ENABLE_MOTION_SHARPEN
    pass MotionSharpen
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_motion_sharpen_PS;
    }
    #endif
    #if ENABLE_PERSISTENCE
    pass Persistence
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_persistence_PS;
    }
    #endif
    #if ENABLE_EDGE_BLUR
    pass EdgeBlur
    {
        // Writes directly to backbuffer -- no intermediate texture
        VertexShader = PostProcessVS;
        PixelShader  = crt_edge_blur_PS;
    }
    #endif
    #if ENABLE_GRAIN
    pass GrainMerged
    {
        // Dual output: clean snapshot + grain delta
        VertexShader  = PostProcessVS;
        PixelShader   = crt_grain_merged_PS;
        RenderTarget0 = crt_pregrain_tex;
        RenderTarget1 = crt_grain_raw_tex;
    }
    pass GrainDiffuse
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_grain_diffuse_PS;
    }
    #endif // ENABLE_GRAIN
    #if ENABLE_NOISE_FLOOR
    pass NoiseFloor
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_noise_floor_PS;
    }
    #endif
    #if ENABLE_DECAY
    // History store. BB-integral mode: raw+prev1 dual-output plus a prev2
    // copy (3 full-res writes). Standard mode: prev1 only (1 write).
    #if DECAY_BB_INTEGRAL
    pass PhosphorDecayStoreRawPrev1
    {
        VertexShader  = PostProcessVS;
        PixelShader   = crt_decay_store_PS;
        RenderTarget0 = crt_decay_raw_tex;
        RenderTarget1 = crt_decay_prev1_tex;
    }
    pass PhosphorDecayPrev2Store
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_decay_prev2_store_PS;
        RenderTarget = crt_decay_prev2_tex;
    }
    #else
    // Standard mode: single prev1 write -- two fewer full-res writes per frame
    pass PhosphorDecayStorePrev1
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_decay_store_PS;
        RenderTarget = crt_decay_prev1_tex;
    }
    #endif
    pass PhosphorDecayPhaseStore
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_decay_phase_store_PS;
        RenderTarget = crt_decay_phase_tex;
    }
    pass PhosphorDecay
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_decay_PS;
    }
    // Auto-resync luminance monitors (run after decay, before next phase store)
    pass LumaMonitorLitCopy
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_decay_luma_lit_copy_PS;
        RenderTarget = crt_decay_luma_lit_prev_tex;
    }
    pass LumaMonitorDarkCopy
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_decay_luma_dark_copy_PS;
        RenderTarget = crt_decay_luma_dark_prev_tex;
    }
    pass LumaMonitorLit
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_decay_luma_lit_PS;
        RenderTarget = crt_decay_luma_lit_tex;
    }
    pass LumaMonitorDark
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_decay_luma_dark_PS;
        RenderTarget = crt_decay_luma_dark_tex;
    }
    #endif
    #if PIPELINE >= 1
    pass SoopAfter
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_soop_after_PS;
    }
    #endif
    #if ENABLE_GAMUT_EXPAND
    pass GamutExpand
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_gamut_expand_PS;
    }
    #endif
    #if ENABLE_SCREEN_REFLECT
    pass ScreenReflect
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_screen_reflect_PS;
    }
    #endif
    #if ENABLE_TUBE_DIFFUSE
    pass TubeDiffuse
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_tube_diffuse_PS;
    }
    #endif
    #if ENABLE_INTERFERENCE
    pass Interference
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_interference_PS;
    }
    pass AccumStore
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_accum_store_PS;
        RenderTarget = crt_accum_tex;
    }
    #endif
    #if ENABLE_LIGHT_WARP
    pass LightWarp
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_light_warp_PS;
    }
    #endif

    #if ENABLE_CORNER_ROUND
    pass CornerRound
    {
        VertexShader = PostProcessVS;
        PixelShader  = crt_corner_round_PS;
    }
    #endif
}

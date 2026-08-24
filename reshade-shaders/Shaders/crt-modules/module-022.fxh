
    float3 result = 0.0;
    float  wsum   = 0.0;

    for (int j = -r + 1; j <= r; j++)
    {
        float wy = recon_weight(tc_px.y - (tc_base.y + float(j)));
        for (int i = -r + 1; i <= r; i++)
        {
            float wx = recon_weight(tc_px.x - (tc_base.x + float(i)));
            float  w = wx * wy;
            float2 sample_tc = (tc_base + float2(float(i), float(j))) * px;
            result += tex2D(tex, clamp(sample_tc, 0.0, 1.0)).rgb * w;
            wsum   += w;
        }
    }
    return result / max(wsum, 1e-5);
}

// ============================================================
// Aperture grille mask (resolution-aware, analytically AA'd)
// ============================================================

#define CRT_REFERENCE_WIDTH 3840.0

// ============================================================
// Multi-type CRT mask
// 0: Aperture Grille (horizontal RGB stripes)
// 1: Diagonal Aperture Grille (staggered rows, better for QD-OLED)
// 2: Slot Mask (aperture grille + alternating dark rows)
// 3: Trinitron (wider green, narrower R/B -- real Trinitron proportions)
// ============================================================

float3 crt_mask_apply(float2 fc, float tw_ref, float strength, float sharp,
                      float3 phcol, int mask_type, float slot_dark,
                      int offset_x, int offset_y, float2 fc_clean, float pixel_luma)
{
    float tw     = tw_ref * (float(BUFFER_WIDTH) / CRT_REFERENCE_WIDTH);
    // Use fc_clean (without burn-in step offsets) for fwidth to prevent
    // discontinuities from integer triad steps from widening the AA edge
    float fw     = fwidth(fc_clean.x / tw);
    float edge   = max(fw, 1.0 / max(sharp, 0.01));

    float3 mask  = 1.0;

    if (mask_type == 0)
    {
        // -- Aperture Grille: standard horizontal RGB stripes --
        float t = frac(fc.x / tw);
        float r = smoothstep(0.0,   edge, t) * smoothstep(0.333, 0.333-edge, t);
        float g = smoothstep(0.333, 0.333+edge, t) * smoothstep(0.667, 0.667-edge, t);
        float b = smoothstep(0.667, 0.667+edge, t) * smoothstep(1.0,   1.0-edge, t);
        mask = float3(r, g, b) * phcol;
    }
    else if (mask_type == 1)
    {
        // -- Diagonal Aperture Grille: rows offset by 1 triad/2 --
        // Each row is shifted by half a triad relative to its neighbour.
        // This distributes the phosphor structure diagonally, reducing
        // sensitivity to QD-OLED triangular subpixel alignment.
        float row_offset = floor(fc.y) * (tw * 0.5);
        float t = frac((fc.x + row_offset) / tw);
        float r = smoothstep(0.0,   edge, t) * smoothstep(0.333, 0.333-edge, t);
        float g = smoothstep(0.333, 0.333+edge, t) * smoothstep(0.667, 0.667-edge, t);
        float b = smoothstep(0.667, 0.667+edge, t) * smoothstep(1.0,   1.0-edge, t);
        mask = float3(r, g, b) * phcol;
    }
    else if (mask_type == 2)
    {
        // -- Slot Mask: aperture grille + alternating dark rows --
        // Mimics shadow mask CRTs where horizontal slots separate scanlines.
        float t = frac(fc.x / tw);
        float r = smoothstep(0.0,   edge, t) * smoothstep(0.333, 0.333-edge, t);
        float g = smoothstep(0.333, 0.333+edge, t) * smoothstep(0.667, 0.667-edge, t);
        float b = smoothstep(0.667, 0.667+edge, t) * smoothstep(1.0,   1.0-edge, t);
        mask = float3(r, g, b) * phcol;
        // Slot rows: fwidth-based AA on the vertical row boundary.
        // Smoothstep replaces the hard binary step for anti-aliased slot edges.
        float  fw_y    = fwidth(fc.y * 0.5);
        float  row_t   = frac(floor(fc.y * 0.5) * 0.5); // 0 or 0.5
        float  slot_aa = smoothstep(0.0, fw_y, row_t) * smoothstep(0.5, 0.5 - fw_y, row_t);
        float  lane    = 1.0 - slot_dark * (1.0 - slot_aa);
        mask *= lane;
    }
    else if (mask_type == 3)
    {
        // -- Trinitron: wider green, narrower R/B --
        // Real Sony Trinitron tubes had green phosphors ~40% wider than R/B.
        // Proportions: R=0-0.25, G=0.25-0.75, B=0.75-1.0 (green gets 50% of triad)
        float t    = frac(fc.x / tw);
        float fedge = edge * 0.7; // sharper edges for Trinitron-style
        float r = smoothstep(0.0,  fedge, t) * smoothstep(0.25, 0.25-fedge, t);
        float g = smoothstep(0.25, 0.25+fedge, t) * smoothstep(0.75, 0.75-fedge, t);
        float b = smoothstep(0.75, 0.75+fedge, t) * smoothstep(1.0,  1.0-fedge,  t);
        mask = float3(r, g, b) * phcol;
    }
    else if (mask_type == 4)
    {
        // -- QD-OLED Delta: scaled checkerboard based on physical A95L subpixel layout --
        // triad_width=2.0 = 1:1 physical pixel mapping (native subpixel size)
        // triad_width=4.0 = each virtual phosphor covers 2 physical pixels (coarser, more visible)
        // triad_width=6.0 = 3 physical pixels per phosphor, very visible structure
        // The 2x2 checkerboard tile scales with tw so triad width is meaningful.
        // Tile pattern:
        //   [G][R]   (even virtual row)
        //   [B][G]   (odd virtual row)

        // Scale fc by tw/2 so the 2x2 tile covers tw pixels
        // At tw=2: 1 pixel per cell. At tw=4: 2 pixels per cell.
        float  cell_size = tw * 0.5; // pixels per subpixel cell
        float2 fc_off    = float2(floor(abs(fc))) + float2(float(crt_mask_offset_x),
                                                            float(crt_mask_offset_y));

        // Determine which 2x2 virtual tile position we're in using uint arithmetic
        // Converting to uint before modulo guarantees exact 0/1 with no float error
        // at any resolution or cell size
        // Small epsilon prevents boundary rounding errors at non-integer cell sizes
        // (e.g. triad 4.0 at 4K with DSR where fc coordinates may fall just below
        // an integer boundary due to floating point precision)
        uint2 tile_idx = uint2(floor(fc_off / cell_size + 0.001));
        float cx       = float(tile_idx.x & 1u); // exactly 0 or 1
        float cy       = float(tile_idx.y & 1u);

        // Subpixel identity:
        // (cx=0, cy=0)=Green  (cx=1, cy=0)=Red
        // (cx=0, cy=1)=Blue   (cx=1, cy=1)=Green
        float is_green = (1.0 - cx) * (1.0 - cy) + cx * cy;
        float is_red   = cx * (1.0 - cy);
        float is_blue  = (1.0 - cx) * cy;

        // Position within the current cell, -1..1
        // Used for the rounded square phosphor shape
        float2 cell_pos = (frac(fc_off / cell_size) * 2.0 - 1.0);

        // Phosphor sizes scale with cell_size to maintain consistent fill ratio
        float fill_scale = 1.0 - 0.08 / max(cell_size, 0.5);

        // Green phosphor: larger rounded square (~60% of cell at native size)
        float g_size   = 0.72 + (0.88 - 0.72) * saturate((cell_size - 1.0) / 3.0);
        g_size        *= fill_scale;
        float g_soft   = max(sharp * 0.1, 0.15) / max(cell_size * 0.5, 1.0);
        float g_shape  = smoothstep(g_size, g_size - g_soft,
                         max(abs(cell_pos.x), abs(cell_pos.y)));

        // Red/Blue phosphors: smaller rounded square (~40% of cell at native size)
        float rb_size  = 0.52 + (0.76 - 0.52) * saturate((cell_size - 1.0) / 3.0);
        rb_size       *= fill_scale;
        float rb_soft  = max(sharp * 0.1, 0.15) / max(cell_size * 0.5, 1.0);
        float rb_shape = smoothstep(rb_size, rb_size - rb_soft,
                         max(abs(cell_pos.x), abs(cell_pos.y)));

        mask = float3(is_red * rb_shape,
                      is_green * g_shape,
                      is_blue * rb_shape) * phcol;
    }
    else if (mask_type == 5)
    {
        // -- QD-OLED Luminance Gate: mask strength inversely proportional to pixel luminance --
        // The QD-OLED colour pattern is applied at full strength in dark areas and
        // reduced toward passthrough in bright areas. Bright pixels (highlights) are
        // barely affected; dark pixels and midtones get the full phosphor texture.
        // No global darkening because bright areas compensate -- they pass through cleanly.
        // This matches real CRT physics: phosphor gaps are only visible in darker areas
        // because bright phosphors bleed light that fills adjacent gaps.

        float  cell_size = max(tw * 0.5, 0.5);
        float2 fc_off    = float2(floor(abs(fc))) +
                           float2(float(crt_mask_offset_x), float(crt_mask_offset_y));

        // Compute QD-OLED subpixel identity and shape (same as type 4)
        uint2 tile_idx = uint2(floor(fc_off / cell_size + 0.001));
        float cx       = float(tile_idx.x & 1u);
        float cy       = float(tile_idx.y & 1u);

        float is_green = (1.0 - cx) * (1.0 - cy) + cx * cy;
        float is_red   = cx * (1.0 - cy);
        float is_blue  = (1.0 - cx) * cy;

        float2 cell_pos = (frac(fc_off / cell_size) * 2.0 - 1.0);

        float fill_scale = 1.0 - 0.08 / max(cell_size, 0.5);

        float g_size   = 0.72 + (0.88 - 0.72) * saturate((cell_size - 1.0) / 3.0);
        g_size        *= fill_scale;
        float g_soft   = max(sharp * 0.1, 0.15) / max(cell_size * 0.5, 1.0);
        float g_shape  = smoothstep(g_size, g_size - g_soft,
                         max(abs(cell_pos.x), abs(cell_pos.y)));

        float rb_size  = 0.52 + (0.76 - 0.52) * saturate((cell_size - 1.0) / 3.0);
        rb_size       *= fill_scale;
        float rb_soft  = max(sharp * 0.1, 0.15) / max(cell_size * 0.5, 1.0);
        float rb_shape = smoothstep(rb_size, rb_size - rb_soft,
                         max(abs(cell_pos.x), abs(cell_pos.y)));

        float3 qdoled_mask = float3(is_red * rb_shape,
                                    is_green * g_shape,
                                    is_blue * rb_shape) * phcol;

        // Luminance gate: use actual image pixel luminance to scale mask application.
        // High luma -> gate near 0 -> mask approaches 1.0 (bright pixels pass through clean)
        // Low luma  -> gate near 1 -> mask applies fully (dark areas get phosphor texture)
        // Power curve 0.5 means midtones get ~70% of full mask strength.
        // Gate: remap pixel_luma against threshold then apply curve
        float gate_input = saturate((pixel_luma - crt_luma_gate_threshold) /
                           max(1.0 - crt_luma_gate_threshold, 0.001));
        float gate = 1.0 - pow(gate_input, crt_luma_gate_curve);
        mask = lerp(1.0, qdoled_mask, gate);
    }

    return saturate(lerp(1.0, mask, strength));
}

// Legacy name kept for any internal references
float3 aperture_grille(float2 fc, float tw_ref, float strength, float sharp, float3 phcol)
{
    return crt_mask_apply(fc, tw_ref, strength, sharp, phcol, 0, 0.5, 0, 0, fc, 0.5);
}

// ============================================================
// Megatron Bezier scanline beam
// ============================================================

float megatron_scanline(float ch, float beam_dist, float scan_min, float scan_max, float attack)
{
    float dist = clamp(beam_dist / ((ch*(scan_max-scan_min)) + scan_min), 0.0, 1.0);
    return Bezier(dist, float4(1.0, 1.0, ch*attack, 0.0));
}

// ============================================================
// Glow helpers
// ============================================================

float3 balance_glow(float3 g, float balance)
{
    float luma = dot(g, float3(0.2126, 0.7152, 0.0722));
    float peak = max(max(g.r, g.g), g.b);
    float3 norm = (peak > 0.0001) ? (g*(luma/peak)) : g;
    return lerp(norm, g, balance);
}


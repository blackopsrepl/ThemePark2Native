               "1:3 -- active every 3rd cycle\0"
               "1:4 -- active every 4th cycle\0";
    ui_tooltip = "Skips BFI every N cycles, replacing skipped cycles with\n"
                 "unmodified passthrough. Reduces flicker at the cost of clarity.\n"
                 "\n"
                 "1:1 (default): continuous BFI, every cycle active.\n"
                 "1:2: BFI runs one cycle, skips the next. Effective dark rate\n"
                 "     is halved. Flicker amplitude reduced, clarity reduced.\n"
                 "1:3: BFI active 1 in 3 cycles. Even lighter effect.\n"
                 "1:4: BFI active 1 in 4 cycles. Barely noticeable clarity gain.\n"
                 "\n"
                 "The skip counter advances every 'frames' rendered frames,\n"
                 "so the ratio is consistent across all frames-per-cycle settings.\n"
                 "\n"
                 "Works for BFI and Variable MPRT (tubePos off).\n"
                 "Also works with Fibonacci: skipped cycles output unmodified\n"
                 "passthrough instead of decay trails -- intermittent phosphor effect.\n"
                 "For Sine BFI, skipped cycles hard-cut to full brightness.";
> = 0;

uniform bool crt_decay_fg_phase <
    ui_label = "Frame Gen Phase Flip";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_tooltip = "For DLSS Frame Generation (or any frame gen where FRAMECOUNT\n"
                 "increments for generated frames).\n"
                 "\n"
                 "With 2-frame BFI, FRAMECOUNT already naturally alternates\n"
                 "real/generated frames between lit and dark phases -- no\n"
                 "multiplier needed.\n"
                 "\n"
                 "If the image appears darker than expected (real frames landing\n"
                 "on the dark phase), enable this to flip the phase by 1 frame.\n"
                 "\n"
                 "LSFG / Nvidia Smooth Motion: leave off -- these run outside\n"
                 "ReShade and FRAMECOUNT does not see their generated frames.";
> = false;

uniform float crt_decay_spike_threshold <
    ui_type = "drag"; ui_label = "Frametime Spike Suppress";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_tooltip = "Suppresses BFI output on frames where frametime exceeds this\n"
                 "multiple of the expected frame period, outputting unmodified\n"
                 "passthrough instead.\n"
                 "\n"
                 "Frametime spikes (hitches) cause the display to hold a lit or\n"
                 "dark frame for much longer than expected -- the eye sees a\n"
                 "sudden very bright or very dark flash.\n"
                 "\n"
                 "1.5 = suppress if frame took > 1.5x the expected period.\n"
                 "2.0 = only suppress severe spikes (default).\n"
                 "10.0 = effectively disabled.\n"
                 "\n"
                 "Expected period = 1000ms / display Hz. At 120Hz = 8.33ms,\n"
                 "so threshold 2.0 suppresses frames > 16.67ms.\n"
                 "Set CRT_FRAMETIME_EXPECTED to your target frametime in ms\n"
                 "via the preprocessor (default 8.33 = 120Hz).";
    ui_min = 1.0; ui_max = 10.0; ui_step = 0.1;
> = 10.0;

uniform bool crt_decay_auto_resync <
    ui_label = "BFI Auto-Resync";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_tooltip = "Monitors average luminance of lit vs dark frames.\n"
                 "If the dark frame becomes significantly brighter than expected\n"
                 "(indicating the BFI phase has flipped due to a dropped frame\n"
                 "or VSync hitch), automatically corrects the phase by 1 frame.\n"
                 "\n"
                 "Fixes the permanent insane flicker that occurs in some games\n"
                 "(e.g. Riven at 120Hz with VSync) after a frame timing anomaly.\n"
                 "\n"
                 "Leave off if your game has stable frame delivery -- the monitor\n"
                 "adds a small per-frame luminance sample and comparison.\n"
                 "Enable if you experience sudden unrecoverable BFI flicker.";
> = false;

uniform float crt_decay_scene_threshold <
    ui_type = "drag"; ui_label = "Scene Change Threshold (MPRT only)";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_tooltip = "Variable MPRT only. Luminance delta that triggers a scene-change bypass.\n"
                 "On a hard cut to a much brighter scene (e.g. ground to clouds),\n"
                 "history frames hold stale dark values, diluting the bright current\n"
                 "frame and causing a 2-3 frame grey flash.\n"
                 "When per-pixel luma difference between current and prev1 exceeds\n"
                 "this threshold, the overlap integral is skipped and the current\n"
                 "frame passes through at full gain for that pixel.\n"
                 "1.0 = disabled (default). 0.20 = catches most hard cuts.\n"
                 "Lower = more aggressive bypass. Has no effect in BFI or Fibonacci.";
    ui_min = 0.05; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

uniform bool crt_decay_tube_pos <
    ui_label = "Raster Sweep - TubePos (MPRT only)";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_tooltip = "Variable MPRT only. Spatially-varying phase simulating the CRT beam\n"
                 "sweeping top-to-bottom.\n"
                 "120Hz: KEEP DISABLED. The sweep period equals the frame period so the\n"
                 "gradient band appears frozen on screen -- a static bright or\n"
                 "semi-transparent band. This is not a bug; it is physics.\n"
                 "240Hz+: enable for a subtle authentic rolling gradient.\n"
                 "When disabled, tubePos is fixed at 0.5 (uniform, no artifact).\n"
                 "Has no effect in BFI or Fibonacci.\n"
                 "\n"
                 "REQUIRES the DECAY_BB_INTEGRAL=1 preprocessor definition, which\n"
                 "allocates two extra full-resolution history textures. Without it\n"
                 "this toggle falls back to standard lit/dark BFI.";
> = false;

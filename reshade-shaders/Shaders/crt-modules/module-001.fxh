
uniform float crt_phosphor_trail_r <
    ui_type = "drag"; ui_label = "Phosphor Trail Red Tint";
    ui_category = "Phosphor Decay";
    ui_tooltip = "Colour tint on the red channel of the persistence trail.\n"
                 "Real phosphors shift hue as they decay -- P22 red drifts\n"
                 "slightly orange. 0.0 = no tint (default).";
    ui_min = -0.5; ui_max = 0.5; ui_step = 0.01;
> = 0.0;

uniform float crt_phosphor_trail_g <
    ui_type = "drag"; ui_label = "Phosphor Trail Green Tint";
    ui_category = "Phosphor Decay";
    ui_tooltip = "Colour tint on the green channel of the persistence trail.\n"
                 "P22 green shifts slightly yellow-green as it decays.\n"
                 "0.0 = no tint (default).";
    ui_min = -0.5; ui_max = 0.5; ui_step = 0.01;
> = 0.0;

uniform float crt_phosphor_trail_b <
    ui_type = "drag"; ui_label = "Phosphor Trail Blue Tint";
    ui_category = "Phosphor Decay";
    ui_tooltip = "Colour tint on the blue channel of the persistence trail.\n"
                 "Blue phosphors shift toward cyan as they cool.\n"
                 "0.0 = no tint (default).";
    ui_min = -0.5; ui_max = 0.5; ui_step = 0.01;
> = 0.0;

// -- Shared --------------------------------------------------
uniform int crt_decay_method <
    ui_type = "combo";
    ui_label = "Decay Method";
    ui_category = "Phosphor Decay";
    ui_items = "Fibonacci (uniform darkening)\0"
               "Variable MPRT (Blur Busters - SDR only)\0"
               "BFI - Black Frame Insertion\0";
    ui_tooltip = "Fibonacci: uniform per-frame darkening. Works at any fps, any pipeline.\n"
                 "No history frames, no pipeline dependency.\n"
                 "\n"
                 "Variable MPRT (SDR only): Blur Busters brightness-budget algorithm.\n"
                 "Dark pixels decay fast, bright pixels preserve energy across frames.\n"
                 "PIPELINE 0 only -- uses sRGB transfer function internally.\n"
                 "On PIPELINE 1/2 highlights will be remapped incorrectly (use BFI instead).\n"
                 "Enable Raster Sweep for 240Hz+ spatial variation (experimental).\n"
                 "\n"
                 "BFI: Hard black frame insertion, correct for any pipeline.\n"
                 "PIPELINE 0: gain applied in sRGB->linear->sRGB space.\n"
                 "PIPELINE 1/2: gain applied via InvReinhard->scale->Reinhard.\n"
                 "No history frames. Recommended for PIPELINE 1/2.";
> = 0;

uniform int crt_decay_frames <
    ui_type = "drag"; ui_label = "Frames per Decay Cycle";
    ui_category = "Phosphor Decay";
    ui_tooltip = "Number of frames in one full decay cycle (all methods).\n"
                 "At 120fps: 2 = 60 bright/sec (recommended).\n"
                 "Higher = more motion clarity, less perceived brightness.";
    ui_min = 2; ui_max = 8; ui_step = 1;
> = 2;

// -- Phosphor Decay - Fibonacci ------------------------------
uniform int crt_decay_stages <
    ui_type = "drag"; ui_label = "Decay Stages";
    ui_category = "Phosphor Decay - Fibonacci";
    ui_tooltip = "Number of Fibonacci-weighted exponential decay stages.\n"
                 "More stages = richer decay curve, darker later frames.\n"
                 "2-3 = subtle, 5-7 = strong phosphor trail effect.";
    ui_min = 1; ui_max = 8; ui_step = 1;
> = 5;

uniform float crt_decay_speed <
    ui_type = "drag"; ui_label = "Global Decay Speed";
    ui_category = "Phosphor Decay - Fibonacci";
    ui_tooltip = "How quickly phosphor brightness fades across the cycle.\n"
                 "Higher = darker decay frames, more motion clarity.";
    ui_min = 0.1; ui_max = 20.0; ui_step = 0.1;
> = 5.0;

uniform float crt_decay_r <
    ui_type = "drag"; ui_label = "Red Phosphor Decay";
    ui_category = "Phosphor Decay - Fibonacci";
    ui_tooltip = "Relative decay speed for red channel.\n"
                 "Lower = longer red trail (P22 red decays slowest).";
    ui_min = 0.1; ui_max = 3.0; ui_step = 0.05;
> = 0.5;

uniform float crt_decay_g <
    ui_type = "drag"; ui_label = "Green Phosphor Decay";
    ui_category = "Phosphor Decay - Fibonacci";
    ui_tooltip = "Relative decay speed for green channel.";
    ui_min = 0.1; ui_max = 3.0; ui_step = 0.05;
> = 0.6;

uniform float crt_decay_b <
    ui_type = "drag"; ui_label = "Blue Phosphor Decay";
    ui_category = "Phosphor Decay - Fibonacci";
    ui_tooltip = "Relative decay speed for blue channel. Blue decays fastest.";
    ui_min = 0.1; ui_max = 3.0; ui_step = 0.05;
> = 0.8;

uniform float crt_decay_floor <
    ui_type = "drag"; ui_label = "Decay Floor";
    ui_category = "Phosphor Decay - Fibonacci";
    ui_tooltip = "Minimum brightness decay frames can reach.\n"
                 "0.0 = fully dark. 0.5 = stays 50% bright. 1.0 = no darkening.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_decay_sine_blend <
    ui_type = "drag"; ui_label = "Sine Smoothing";
    ui_category = "Phosphor Decay - Fibonacci";
    ui_tooltip = "Blends decay curve toward smooth cosine wave.\n"
                 "0.0 = hard step. 1.0 = full sine. 0.5-0.8 recommended.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.7;

uniform float crt_decay_luma_protect <
    ui_type = "drag"; ui_label = "Highlight Protection";
    ui_category = "Phosphor Decay - Fibonacci";
    ui_tooltip = "Reduces decay on bright pixels.\n"
                 "0.0 = all pixels equal. 1.0 = highlights barely decay.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.20;

// -- Phosphor Decay - BFI / Variable MPRT --------------------
// Gain: shared by BFI (method 2) and Variable MPRT (method 1).
// Hidden when Fibonacci is selected.
uniform float crt_decay_gain <
    ui_type = "drag"; ui_label = "Gain vs Blur";
    ui_category = "Phosphor Decay - BFI / Variable MPRT";
    ui_tooltip = "Lit frame brightness multiplier.\n"
                 "litGain = frames x gain. With frames=2:\n"
                 "  0.5 (default): litGain=1.0, lit frame = signal unchanged.\n"
                 "    No clipping on any content. Sky/bloom look correct.\n"
                 "  > 0.5: lit frame is boosted to partially recover average\n"
                 "    brightness, but bright content clips to grey/white.\n"
                 "If you see flicker or highlights greying out, reduce below 0.5.";
    ui_min = 0.3; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float crt_decay_dark_floor <
    ui_type = "drag"; ui_label = "VRR Dark Frame Floor";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_tooltip = "Minimum brightness of dark frames. 0.0 = pure black (default).\n"
                 "\n"
                 "Under VRR, frame display times are irregular -- a lit frame\n"
                 "may show for 6ms and the next dark frame for 14ms, or vice\n"
                 "versa. The eye integrates varying lit/dark ratios each cycle,\n"
                 "producing irregular brightness fluctuation (VRR flicker).\n"
                 "\n"
                 "Raising this floor reduces the brightness swing between lit\n"
                 "and dark frames, directly reducing flicker amplitude at the\n"
                 "cost of some motion clarity (dark frames are no longer black).\n"
                 "\n"
                 "0.00 = maximum clarity, maximum VRR flicker (locked Hz only).\n"
                 "0.10 = good balance, flicker mostly eliminated on VRR displays.\n"
                 "0.20 = very stable, noticeable clarity reduction.\n"
                 "Start at 0.0 and raise until VRR flicker becomes acceptable.";
    ui_min = 0.0; ui_max = 0.5; ui_step = 0.01;
> = 0.0;

uniform bool crt_decay_dark_blend <
    ui_label = "VRR Dark Frame Blend";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_tooltip = "Only active when VRR Dark Frame Floor > 0.\n"
                 "\n"
                 "OFF (default): dark frames output a flat grey at the floor\n"
                 "level. Clean, no ghosting, but the transition lit->grey->lit\n"
                 "is an abrupt cut which may be more visible as flicker.\n"
                 "\n"
                 "ON: dark frames output lerp(prev_frame, curr_frame, 0.5)\n"
                 "scaled to the floor level. The dark frame contains a 50/50\n"
                 "blend of the previous and current rendered frames, giving\n"
                 "the eye a mid-point image to integrate rather than a hard\n"
                 "grey cut. May further reduce perceived flicker.\n"
                 "\n"
                 "Risk: on fast motion, prev and curr frames are spatially\n"
                 "misaligned -- the blend produces a double-image ghost at\n"
                 "floor brightness. At floor=0.10 this is ~10pct brightness\n"
                 "and usually invisible. At floor=0.20+ it may be noticeable\n"
                 "on fast camera pans. Test with both settings.";
> = false;

uniform bool crt_decay_sine_bfi <
    ui_label = "Sine BFI (VRR Smooth)";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_tooltip = "Replaces the hard lit/dark square wave with a smooth cosine\n"
                 "gain curve that rides between litGain and Dark Frame Floor.\n"
                 "\n"
                 "Square wave (off): frame 0 = litGain, frame 1 = darkFloor.\n"
                 "Hard transition every cycle. At 120Hz with frames=2 this is\n"
                 "a 60Hz square wave -- fuses cleanly at locked Hz but under\n"
                 "VRR the irregular cycle boundaries produce visible flicker.\n"
                 "\n"
                 "Sine BFI (on): gain = lerp(darkFloor, litGain, 0.5+0.5*cos(phase)).\n"
                 "All frames output signal -- no hard black cut. The gain rises\n"
                 "and falls smoothly each cycle. Irregular VRR timing shifts the\n"
                 "phase slightly but the eye integrates a smooth waveform rather\n"
                 "than an abrupt cut, making the irregularity much less visible.\n"
                 "\n"
                 "Works best with frames=4: gives 2 frames of ramp-up and\n"
                 "2 frames of ramp-down, creating a clear sine shape.\n"
                 "With frames=2 the endpoints are the same as square wave\n"
                 "but adjacent cycles connect smoothly.\n"
                 "\n"
                 "Trade-off: peak motion clarity is slightly reduced since\n"
                 "the dark frames are never fully at the floor -- they are\n"
                 "on a smooth curve between floor and litGain.\n"
                 "Dark Frame Floor sets the minimum of the sine trough.";
> = false;

uniform bool crt_decay_invert_cycle <
    ui_label = "Invert Cycle (Multi-Lit)";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_tooltip = "Inverts the lit/dark ratio: instead of 1 lit + (frames-1) dark,\n"
                 "uses (frames-1) lit + 1 dark.\n"
                 "\n"
                 "Standard (off):  1 lit, N-1 dark. Low duty cycle, maximum clarity.\n"
                 "Inverted (on):   N-1 lit, 1 dark. High duty cycle, brighter image,\n"
                 "                 motion clarity from the single dark frame.\n"
                 "\n"
                 "Only useful at 240Hz+ with frames=3 or 4:\n"
                 "  240Hz frames=3 inverted: 2 lit + 1 dark, 80Hz dark rate, 66pct duty.\n"
                 "  360Hz frames=4 inverted: 3 lit + 1 dark, 90Hz dark rate, 75pct duty.\n"
                 "\n"
                 "At 120Hz with frames=2: no effect -- 1 lit + 1 dark is symmetric.\n"
                 "At 120Hz with frames=3: the 40Hz dark rate causes visible pulsing\n"
                 "regardless of inversion -- do not use at 120Hz with frames > 2.\n"
                 "\n"
                 "Gain is automatically adjusted for the higher duty cycle:\n"
                 "litGain = frames * gain / (frames - 1) so average brightness\n"
                 "is maintained relative to the standard non-inverted calculation.\n"
                 "Has no effect on Fibonacci or Variable MPRT (BB integral).";
> = false;

uniform int crt_decay_duty_ratio <
    ui_type = "combo"; ui_label = "BFI Duty Ratio";
    ui_category = "Phosphor Decay - BFI / Variable MPRT (Experimental)";
    ui_items = "1:1 -- every cycle active (default)\0"
               "1:2 -- active every 2nd cycle\0"

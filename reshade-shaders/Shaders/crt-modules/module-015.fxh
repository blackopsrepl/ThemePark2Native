                 "0.5+ = strong area fill, good for bright outdoor scenes.\n"
                 "\n"
                 "Runs at quarter resolution -- very cheap additional pass.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_glow_wide_radius <
    ui_type = "drag"; ui_label = "Wide Glow Radius";
    ui_category = "Brightness & Glow";
    ui_tooltip = "Radius of the wide bloom pass in pixels at half-resolution.\n"
                 "Higher = larger soft area halo. Keep well above tight glow radius.";
    ui_min = 1.0; ui_max = 16.0; ui_step = 0.5;
> = 8.0;

uniform float crt_glow_wide_threshold <
    ui_type = "drag"; ui_label = "Wide Glow Threshold";
    ui_category = "Brightness & Glow";
    ui_tooltip = "Luminance threshold for the wide bloom pass.\n"
                 "Typically set lower than tight glow threshold so the wide pass\n"
                 "captures more of the scene rather than just peak highlights.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_glow_spectral <
    ui_type = "drag"; ui_label = "Spectral Bloom";
    ui_category = "Brightness & Glow";
    ui_tooltip = "Physically based chromatic bloom: blue light diffracts more\n"
                 "than red through a lens, so the blue channel blooms wider.\n"
                 "\n"
                 "0.0 = uniform bloom, all channels same width (default).\n"
                 "0.5 = subtle coloured fringe on bright elements.\n"
                 "1.0 = full separation: R=0.75x, G=1.0x, B=1.35x sigma.\n"
                 "\n"
                 "Based on wavelength-dependent diffraction -- shorter wavelengths\n"
                 "spread more than longer ones through optical glass.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 0.0;

uniform float crt_glow_threshold <
    ui_type = "drag"; ui_label = "Glow Threshold";
    ui_category = "Brightness & Glow";
    ui_tooltip = "Luminance level below which glow is suppressed.\n"
                 "0.0 = all pixels contribute to glow.\n"
                 "0.3+ = only bright elements bloom.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_glow_knee <
    ui_type = "drag"; ui_label = "Glow Knee";
    ui_category = "Brightness & Glow";
    ui_tooltip = "Controls how selectively glow is applied across luminance levels.\n"
                 "\n"
                 "0.0 = original behaviour: hard threshold, all pixels above it\n"
                 "      contribute equally (weighted by luma).\n"
                 "\n"
                 "Above 0: dark pixels contribute progressively less to glow,\n"
                 "bright pixels contribute fully. Creates better contrast between\n"
                 "lit and unlit areas -- glow feels more localised to bright\n"
                 "elements rather than bleeding into dark regions of the scene.\n"
                 "\n"
                 "Works even at Threshold=0: the knee creates a natural luminance\n"
                 "ramp from 0 to the knee width, suppressing dark pixel glow\n"
                 "contribution without cutting it off entirely.\n"
                 "\n"
                 "Suggested starting point: 0.1-0.3. Higher values (0.4-0.5)\n"
                 "are more aggressive -- useful for scenes with strong contrast\n"
                 "between bright elements and dark backgrounds. The ideal value\n"
                 "varies by game brightness distribution.";
    ui_min = 0.0; ui_max = 0.5; ui_step = 0.01;
> = 0.0;

uniform float crt_glow_h_mix <
    ui_type = "drag"; ui_label = "Horizontal vs Vertical Glow Mix";
    ui_category = "Brightness & Glow";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 0.7;

uniform float crt_glow_balance <
    ui_type = "drag"; ui_label = "Glow Colour Balance";
    ui_category = "Brightness & Glow";
    ui_tooltip = "0.0 = neutral white glow, 1.0 = raw colour.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 0.0;

// ============================================================
// Uniforms -- Halation
// ============================================================

#if ENABLE_HALATION
uniform float crt_halation_strength <
    ui_type = "drag"; ui_label = "Halation Strength";
    ui_category = "Halation";
    ui_tooltip = "Strength of the phosphor glass scatter bloom.\nOnly affects bright elements against dark backgrounds -- not a global haze.\nSet ENABLE_HALATION=0 in preprocessor to remove the pass entirely.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float crt_halation_threshold <
    ui_type = "drag"; ui_label = "Halation Threshold";
    ui_category = "Halation";
    ui_tooltip = "Only pixels brighter than this feed into the halation bloom.\nHigher = only extreme highlights scatter.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.6;

uniform float crt_halation_radius <
    ui_type = "drag"; ui_label = "Halation Radius";
    ui_category = "Halation";
    ui_tooltip = "Spread of the glass scatter in pixels (at quarter resolution).\nHigher = wider bloom around bright elements.";
    ui_min = 1.0; ui_max = 16.0; ui_step = 0.5;
> = 6.0;

uniform float crt_halation_sigma <
    ui_type = "drag"; ui_label = "Halation Sigma";
    ui_category = "Halation";
    ui_min = 0.1; ui_max = 8.0; ui_step = 0.1;
> = 3.0;

uniform float crt_halation_anisotropy <
    ui_type = "drag"; ui_label = "Halation Anisotropy";
    ui_category = "Halation";
    ui_tooltip = "Controls the horizontal vs vertical spread ratio of halation.\n"
                 "1.0 (default) = isotropic -- same spread in both directions.\n"
                 "2.0 = horizontal spread is 2x wider than vertical (realistic CRT:\n"
                 "      shadow mask stripes run vertically, so light bleeds more\n"
                 "      horizontally along the stripe direction).\n"
                 "0.5 = vertical spread wider than horizontal.\n"
                 "Does not affect your existing radius/sigma/strength settings.";
    ui_min = 0.25; ui_max = 4.0; ui_step = 0.05;
> = 1.0;

uniform float crt_halation_saturation <
    ui_type = "drag"; ui_label = "Halation Desaturation";
    ui_category = "Halation";
    ui_tooltip = "How much the scattered light desaturates toward warm white.\n0.0 = full colour scatter, 1.0 = fully desaturated (warm white glow).\nResolution: set HALATION_RESOLUTION=4 (quarter), 2 (half), 1 (full) in preprocessor.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.6;

uniform float crt_halation_warmth <
    ui_type = "drag"; ui_label = "Halation Warmth";
    ui_category = "Halation";
    ui_tooltip = "Colour temperature of the halation glow.\n"
                 "0.0 = pure white scatter (neutral).\n"
                 "1.0 = warm orange-red tint (realistic phosphor backscatter).\n"
                 "Real CRT halation is slightly warm due to phosphor spectral\n"
                 "emission bleeding through the glass.\n"
                 "Works alongside Desaturation: desaturation removes colour,\n"
                 "warmth tints what remains.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;


#endif // ENABLE_HALATION

// ============================================================
#if ENABLE_CA
// Uniforms -- Chromatic Aberration
// ============================================================

uniform float crt_ca_strength <
    ui_type = "drag"; ui_label = "CA Strength";
    ui_category = "Chromatic Aberration";
    ui_tooltip = "Radial chromatic aberration strength.\n"
                 "Simulates glass lens dispersion: short wavelengths (blue) refract\n"
                 "more than long wavelengths (red), causing colour fringing that\n"
                 "increases with distance from screen centre.\n"
                 "Zero at centre, maximum at corners.\n"
                 "0.0 = disabled. 0.002-0.005 = subtle. 0.01+ = strong.\n"
                 "Integrates with geometry curvature -- CA follows the warp.";
    ui_min = 0.0; ui_max = 0.02; ui_step = 0.0005;
> = 0.0;

uniform float crt_ca_falloff <
    ui_type = "drag"; ui_label = "CA Falloff";
    ui_category = "Chromatic Aberration";
    ui_tooltip = "Controls how quickly CA builds up from centre to edge.\n"
                 "1.0 = linear -- CA scales linearly with distance from centre.\n"
                 "2.0 = quadratic -- CA is subtle near centre, strong at corners.\n"
                 "     More physically accurate for simple lens models.\n"
                 "3.0+ = cubic -- very concentrated at corners only.";
    ui_min = 1.0; ui_max = 4.0; ui_step = 0.1;
> = 2.0;
#endif // ENABLE_CA

// ============================================================
#if ENABLE_CONVERGENCE
// Uniforms -- Convergence
// ============================================================

uniform float crt_convergence_r <
    ui_type = "drag"; ui_label = "Red Vertical Convergence";
    ui_category = "Convergence";
    ui_tooltip = "Vertical offset of the red channel in pixels.\nNegative = shift up, positive = shift down.\nPVM-2730 uses -0.14. Safe with ENABLE_MASK=0.";
    ui_min = -4.0; ui_max = 4.0; ui_step = 0.01;
> = 0.0;

uniform float crt_convergence_g <
    ui_type = "drag"; ui_label = "Green Vertical Convergence";
    ui_category = "Convergence";
    ui_min = -4.0; ui_max = 4.0; ui_step = 0.01;
> = 0.0;

uniform float crt_convergence_b <
    ui_type = "drag"; ui_label = "Blue Vertical Convergence";
    ui_category = "Convergence";
    ui_min = -4.0; ui_max = 4.0; ui_step = 0.01;
> = 0.0;

uniform float crt_convergence_h_r <
    ui_type = "drag"; ui_label = "Red Horizontal Convergence";
    ui_category = "Convergence";
    ui_tooltip = "Horizontal offset of the red channel in pixels.\n"
                 "Negative = left, positive = right.\n"
                 "Complements vertical convergence and radial CA.";
    ui_min = -3.0; ui_max = 3.0; ui_step = 0.1;
> = 0.0;

uniform float crt_convergence_h_b <
    ui_type = "drag"; ui_label = "Blue Horizontal Convergence";
    ui_category = "Convergence";
    ui_tooltip = "Horizontal offset of the blue channel in pixels.\n"
                 "Negative = left, positive = right.";
    ui_min = -3.0; ui_max = 3.0; ui_step = 0.1;
> = 0.0;

uniform float crt_convergence_v_spread <
    ui_type = "drag"; ui_label = "Vertical Beam Spread";
    ui_category = "Convergence";
    ui_tooltip = "Slightly blurs each channel vertically by a different amount,\n"
                 "simulating the physical offset of the three electron guns in a\n"
                 "colour CRT. Adds organic softness independent of convergence.\n"
                 "0.0 = disabled (default). 0.3-0.7 = subtle per-channel spread.";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 0.0;

uniform float crt_convergence_radial <
    ui_type = "drag"; ui_label = "Radial Misconvergence";
    ui_category = "Convergence";
    ui_tooltip = "Physically based pincushion misconvergence model.\n"
                 "Real CRT electron guns have convergence errors that grow\n"
                 "toward the screen edges: delta_y = k * x^2\n"
                 "where x is normalised horizontal distance from centre.\n"
                 "\n"
                 "Added ON TOP of the uniform convergence offsets above.\n"
                 "At screen centre: no additional error. At edges: maximum.\n"
                 "Red diverges up, Blue diverges down at the edges.\n"
                 "\n"
                 "0.0 = disabled (default). 0.5-1.0 = subtle authentic\n"
                 "misconvergence. 2.0+ = strong edge colour fringing.";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.1;
> = 0.0;
#endif // ENABLE_CONVERGENCE

// ============================================================

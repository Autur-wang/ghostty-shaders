// transparent background
const bool transparent = false;

// terminal contents luminance threshold to be considered background (0.0 to 1.0)
const float threshold = 0.30;

// divisions of grid
const float repeats = 30.;

// number of layers
const float layers = 32.;

// static base field: grid divisions for the uniform, non-zooming star layer
// that keeps the WHOLE screen covered regardless of the warp animation phase
const float baseRepeats = 56.;

// star colors
const vec3 white = vec3(1.0); // Set star color to pure white

float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float N21(vec2 p) {
    p = fract(p * vec2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

vec2 N22(vec2 p) {
    float n = N21(p);
    return vec2(n, N21(p + n));
}

mat2 scale(vec2 _scale) {
    return mat2(_scale.x, 0.0,
        0.0, _scale.y);
}

// 2D Noise based on Morgan McGuire
float noise(in vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);

    // Four corners in 2D of a tile
    float a = N21(i);
    float b = N21(i + vec2(1.0, 0.0));
    float c = N21(i + vec2(0.0, 1.0));
    float d = N21(i + vec2(1.0, 1.0));

    // Smooth Interpolation
    vec2 u = f * f * (3.0 - 2.0 * f); // Cubic Hermite Curve

    // Mix 4 corners percentages
    return mix(a, b, u.x) +
        (c - a) * u.y * (1.0 - u.x) +
        (d - b) * u.x * u.y;
}

float perlin2(vec2 uv, int octaves, float pscale) {
    float col = 1.;
    float initScale = 4.;
    for (int l; l < octaves; l++) {
        float val = noise(uv * initScale);
        if (col <= 0.01) {
            col = 0.;
            break;
        }
        val -= 0.01;
        val *= 0.5;
        col *= val;
        initScale *= pscale;
    }
    return col;
}

vec3 stars(vec2 uv, float offset) {
    float timeScale = -(iTime + offset) / layers;
    float trans = fract(timeScale);
    float newRnd = floor(timeScale);
    vec3 col = vec3(0.);

    // Translate uv then scale for center
    uv -= vec2(0.5);
    uv = scale(vec2(trans)) * uv;
    uv += vec2(0.5);

    // Create square aspect ratio
    uv.x *= iResolution.x / iResolution.y;

    // Create boxes
    uv *= repeats;

    // Get position
    vec2 ipos = floor(uv);

    // Return uv as 0 to 1
    uv = fract(uv);

    // Calculate random xy and size
    vec2 rndXY = N22(newRnd + ipos * (offset + 1.)) * 0.9 + 0.05;
    float rndSize = N21(ipos) * 100. + 200.;

    vec2 j = (rndXY - uv) * rndSize;
    float sparkle = 1. / dot(j, j);

    // Set stars to be pure white
    col += white * sparkle;

    col *= smoothstep(1., 0.8, trans);
    return col; // Return pure white stars only
}

// Uniform star layer with no zoom: one candidate star per grid cell across the
// entire screen, twinkling on independent phases. The warp layers above stream
// from the center, so edge/corner coverage comes from this layer.
vec3 staticStars(vec2 uv) {
    uv.x *= iResolution.x / iResolution.y;
    uv *= baseRepeats;

    vec2 ipos = floor(uv);
    uv = fract(uv);

    // Drop ~30% of cells so the field reads as scattered, not a lattice
    if (N21(ipos + 13.7) < 0.3) return vec3(0.);

    vec2 rndXY = N22(ipos) * 0.9 + 0.05;
    float rndSize = N21(ipos + 5.) * 150. + 150.;

    vec2 j = (rndXY - uv) * rndSize;
    float sparkle = 1. / dot(j, j);

    // Independent twinkle phase + rate per star
    float tw = 0.55 + 0.45 * sin(iTime * (N21(ipos) * 2. + 0.4) + N21(ipos + 1.) * 6.2831);

    return white * sparkle * tw;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fragCoord / iResolution.xy;

    vec3 col = vec3(0.);

    for (float i = 0.; i < layers; i++) {
        col += stars(uv, i);
    }

    // Always-on uniform coverage across the full screen (edges included)
    col += staticStars(uv);

    // Sample the terminal screen texture including alpha channel
    vec4 terminalColor = texture(iChannel0, uv);

    // FULL-SCREEN starfield: additive composite instead of the background-only mask.
    // Stars are drawn over the ENTIRE screen (including tmux panes / content areas),
    // added on top of the terminal pixels. Text stays readable because bright text
    // pixels dominate the small added star brightness; dark gaps light up with stars.
    // (The old `mask` only painted stars where luminance < threshold, so a full tmux
    // layout covered nearly all of them — that's what made the field look empty.)
    vec3 blendedColor = terminalColor.rgb + col;

    // Apply terminal's alpha to control overall opacity
    fragColor = vec4(blendedColor, terminalColor.a);
}

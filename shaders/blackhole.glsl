// blackhole.glsl — a floating black hole for Ghostty
//
// Inspired by Eric Bruneton's "Real-time High-Quality Rendering of
// Non-Rotating Black Holes" (https://ebruneton.github.io/black_hole_shader/).
// His implementation beam-traces Schwarzschild geodesics against precomputed
// lookup tables; a Ghostty custom shader is a single screen-space pass, so the
// same visual ingredients are approximated here instead:
//
//   * gravitational lensing  — weak-field deflection (Einstein-ring mapping)
//     applied to the terminal texture, so text bends, magnifies and flips
//     around the hole
//   * event horizon          — pure shadow disc
//   * photon ring            — thin bright ring just outside the horizon
//   * accretion disk         — Keplerian streaks, doppler beaming (approaching
//     side blue-white and bright, receding side dim orange-red), plus a faint
//     circular "lensed image" of the disk's far side
//
// Ghostty setup (~/.config/ghostty/config):
//   custom-shader = /path/to/blackhole_ghostty/blackhole.glsl
//   custom-shader-animation = true

// ---------------------------------------------------------------- tunables --
const float HOLE_RADIUS   = 0.0850; // event horizon at FULL intensity (fraction of screen height)
const float LENS_STRENGTH = 0.2600;  // Einstein radius at full intensity — how far text bends
const float DISK_GAIN     = 1.0000;  // accretion disk brightness
const float DRIFT_SPEED   = 1.0000;   // how fast the hole floats around
const float DISK_TILT     = 0.5000; // disk tilt, radians
const float WORK_AREA     = 0.3400; // bottom screen fraction kept undistorted
const float DILATION_MIN  = 0.1000; // animation time rate when the hole is fully grown (gravitational time dilation)

// ------------------------------------------------------ pomodoro, self-contained --
// Shaders have no memory between frames, so the schedule is anchored to the
// wall clock (iDate.w): the hole grows over each WORK_PERIOD_MIN, collapses
// as break time arrives, and stays gone for BREAK_MIN. With 55+5 the break
// is the last five minutes of every hour. Independently, iTimeCursorChange
// acts as a live typing detector: stop using the terminal and the hole
// shrinks away; it never shows while you are not actually working.
const float WORK_PERIOD_MIN = 55.0000; // work minutes per cycle (growth phase)
const float BREAK_MIN       = 5.0000; // break minutes per cycle (hole gone)
const float IDLE_FADE_SEC   = 90.0000; // typing pause at which fading starts
const float TIME_SCALE      = 1.0000; // TESTING: 1 = real wall-clock schedule; >1 fast-forwards growth via iTime (100 -> a full cycle in ~36 s). Set back to 1 for normal use.

// ------------------------------------------------------------------- noise --
float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i),               hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
               f.y);
}

// mirrored repeat keeps lensed samples on-screen without edge smearing
vec2 mirrorUV(vec2 u) { return 1.0 - abs(1.0 - mod(u, 2.0)); }

vec2 rot(vec2 v, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// doppler beaming: q.x < 0 side orbits toward the viewer
float beaming(vec2 q, float r) {
    return smoothstep(1.0, -1.0, q.x / max(r, 1e-5));
}

// blackbody-ish disk palette: receding/outer = orange-red, approaching/inner = blue-white
vec3 diskPalette(float heat) {
    vec3 cool = vec3(1.00, 0.38, 0.08);
    vec3 mid  = vec3(1.00, 0.80, 0.45);
    vec3 hot  = vec3(0.85, 0.90, 1.00);
    return heat < 0.5 ? mix(cool, mid, heat * 2.0) : mix(mid, hot, heat * 2.0 - 1.0);
}

// ------------------------------------------------------------------- image --
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  res    = iResolution.xy;
    vec2  uv     = fragCoord / res;
    float aspect = res.x / res.y;

    // Ghostty's fragCoord y runs top-down; work in height-from-bottom
    float yUp = 1.0 - uv.y;

    // ---- pomodoro state, computed live from Ghostty uniforms ----
    // wall-clock cycle: grow through the work phase, collapse fast in the
    // last minute, stay gone through the break phase
    float workSec  = WORK_PERIOD_MIN * 60.0;
    float cycleSec = workSec + BREAK_MIN * 60.0;
    // schedule rides the wall clock; for testing, TIME_SCALE adds extra
    // progress via iTime (which always advances per frame), so e.g. 100 runs
    // a full cycle in seconds without depending on how Ghostty steps iDate.w
    float wall     = iDate.w + iTime * (TIME_SCALE - 1.0);
    float phase    = mod(wall, cycleSec);
    float collapse = min(60.0, workSec * 0.15);  // scales down for short debug cycles
    float grow = clamp(phase / workSec, 0.0, 1.0)
               * (1.0 - smoothstep(workSec - collapse, workSec, phase));
    // always-present floor: never gone while you work — small and slow at
    // cycle start, back to small when the break window arrives
    float I = mix(0.12, 1.0, grow);
    // typing detector: cursor quiet -> you're pausing; the hole shrinks live
    // and is gone by the time the pause becomes a real break
    float idle = max(0.0, iTime - iTimeCursorChange);
    I *= 1.0 - smoothstep(IDLE_FADE_SEC, max(BREAK_MIN * 60.0, IDLE_FADE_SEC + 1.0), idle);
    float vis = smoothstep(0.0, 0.10, I);  // hole vanishes entirely when rested
    if (vis <= 0.0) {
        fragColor = texture(iChannel0, uv);
        return;
    }
    float sz     = mix(0.22, 1.0, I);      // starts small, grows toward break time
    float rh     = HOLE_RADIUS * sz;
    float thetaE = LENS_STRENGTH * sz;

    // smooth animation runs off iTime (advances every frame); the wall clock
    // above only drives the slow pomodoro envelope
    float t = iTime * DRIFT_SPEED;

    // ---- gravitational time dilation ----
    // A heavier hole slows the clock locally: the accretion disk visibly winds
    // down as the hole grows. dil multiplies the disk's orbital rate, falling
    // from 1 toward DILATION_MIN as the hole reaches full mass. (Applied to the
    // disk swirl below, not to the drift — scaling the drift frequency by a
    // slowly-varying mass over an unbounded iTime would eventually stall it.)
    float dil = mix(1.0, DILATION_MIN, I);

    // lazy Lissajous drift, vertically confined so the hole and its disk
    // stay above the work area at the bottom of the screen; bounds adapt to
    // the current size (disk half-extent ~2.4*rh after the tilt rotation)
    float ext = 2.4 * rh;
    float yLo = WORK_AREA + 0.12 + ext;      // clears shield band + wobble
    float yHi = max(yLo, 0.90 - ext);        // clears the screen top
    // drift follows size: a small calm hole hovers near its spot, a big one
    // roams wide and fast (amplitude scaling, not frequency — intensity
    // varies over time and frequency modulation would jerk the phase)
    float spd = mix(0.35, 1.0, I);
    vec2 center = vec2(
        0.5 + (0.24 * sin(t * 0.21) + 0.05 * sin(t * 0.083)) * spd,
        1.0 - mix(yLo, yHi, 0.5 + (0.42 * sin(t * 0.157 + 2.0) + 0.08 * sin(t * 0.117)) * spd));
    // restlessness: extra wobble grows with intensity; frequencies stay
    // constant so the position is continuous as intensity evolves
    center += I * vec2(0.040 * sin(t * 0.83) + 0.020 * sin(t * 1.31),
                       0.030 * sin(t * 1.03 + 1.0));

    // aspect-corrected frame centered on the hole (y in units of screen height)
    vec2  p  = (uv - center) * vec2(aspect, 1.0);
    float r  = length(p);

    // ---- gravitational lensing of the terminal contents ----
    // weak-field deflection alpha = thetaE^2 / r, windowed so the far field
    // stays readable; inside the Einstein radius the mapping flips, producing
    // the mirrored secondary image a real lens makes
    float defl   = (thetaE * thetaE / max(r, 1e-4)) * exp(-r * r * 4.0);
    // fade the warp field itself to zero toward the work area — a continuous
    // displacement leaves no visible seam, unlike blending warped/unwarped colors
    defl *= vis * smoothstep(WORK_AREA, WORK_AREA + 0.18, yUp);
    vec2  dir    = p / max(r, 1e-5);
    vec3  term;
    // mild chromatic aberration: blue bends a touch more than red
    for (int i = 0; i < 3; i++) {
        float k   = 1.0 + (float(i) - 1.0) * 0.035;
        vec2  sp  = p - dir * defl * k;
        vec2  suv = mirrorUV(center + sp / vec2(aspect, 1.0));
        term[i]   = texture(iChannel0, suv)[i];
    }

    // shadow: hard black inside the horizon, text fades as it falls in
    float shadow = smoothstep(rh, rh * 1.03, r);
    term *= shadow * smoothstep(rh, rh * 1.5, r);

    vec3 col = term;

    // ---- accretion disk (tilted, flattened ellipse) ----
    vec2  pd = rot(p, DISK_TILT);
    vec2  q  = vec2(pd.x, pd.y / 0.30);        // squash -> disk seen near edge-on
    float rd = length(q);
    float rin  = rh * 1.45;
    float rout = rh * 4.30;

    float band = smoothstep(rin, rin * 1.30, rd) *
                 (1.0 - smoothstep(rout * 0.55, rout, rd));
    if (band > 0.001) {
        float ang = atan(q.y, q.x);
        float kep = pow(rin / rd, 1.5);        // Keplerian: inner orbits faster
        // gravitational time dilation: clocks slow near the horizon, so the
        // inner orbits appear to freeze (Schwarzschild-ish redshift), and the
        // whole disk winds down via dil as the hole grows
        float redshift = sqrt(clamp(1.0 - rh / rd, 0.04, 1.0));
        float swirlA = ang + rd * 22.0 - t * kep * 2.6 * redshift * dil;
        float streaks = vnoise(vec2(rd * 70.0, swirlA * 3.0)) * 0.65 +
                        vnoise(vec2(rd * 24.0, swirlA * 1.5 + 7.0)) * 0.35;
        streaks = 0.35 + 0.9 * streaks * streaks;

        float dop  = beaming(q, rd);                       // 0 receding, 1 approaching
        float emit = pow(rin / rd, 2.2);                   // hotter toward the inner edge
        float heat = clamp(0.85 * dop + 0.45 * (rin / rd) - 0.15, 0.0, 1.0);
        float gain = mix(0.18, 2.4, dop * dop);            // relativistic beaming

        // the half nearer the viewer (lower on screen, +y in this top-down
        // frame) passes in front of the shadow
        float front = smoothstep(-0.004, 0.004, pd.y);
        float occl  = mix(shadow, 1.0, front);

        col += diskPalette(heat) * (DISK_GAIN * band * streaks * emit * gain * occl) * vis;
    }

    // ---- lensed image of the disk's far side: a faint circular halo ----
    float halo = exp(-pow((r - rh * 1.75) / (rh * 0.55), 2.0));
    float hdop = beaming(rot(p, DISK_TILT), r);
    col += diskPalette(0.45 + 0.4 * hdop) * halo * mix(0.06, 0.55, hdop) * shadow * vis;

    // ---- photon ring: thin, hot, just outside the horizon ----
    float ring = exp(-pow((r - rh * 1.16) / (rh * 0.10), 2.0));
    col += vec3(1.0, 0.88, 0.70) * ring * 1.4 * shadow * vis;

    // faint warm ambient glow so the hole reads as an object, not a cutout
    col += vec3(1.0, 0.55, 0.25) * 0.030 * exp(-pow(r / (rh * 3.5), 2.0)) * shadow * vis;

    fragColor = vec4(col, 1.0);
}

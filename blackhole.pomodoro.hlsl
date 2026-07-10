// blackhole.hlsl -- a geodesic-traced black hole for Windows Terminal
//
// Port of https://github.com/s0xDk/ghostty-blackhole for Windows Terminal.
// After Eric Bruneton's "Real-time High-Quality Rendering of Non-Rotating
// Black Holes" (https://ebruneton.github.io/black_hole_shader/). Bruneton
// precomputes Schwarzschild geodesics into lookup textures; a Windows Terminal
// pixel shader is a single fragment pass, so here each pixel's null geodesic
// is integrated numerically instead -- the Binet-form photon acceleration
// a = -(3/2) h^2 x / r^5  reproduces the exact Schwarzschild bending.
//
// Differences from the Ghostty original:
//   * MODE_TOKENS (cursor-color data channel) removed -- Windows Terminal
//     pixel shaders have no access to cursor color uniforms
//   * iDate.w  -> Time  (Windows Terminal has no wall-clock uniform)
//   * iTimeCursorChange  removed (no cursor-activity uniform)
//   * GLSL -> HLSL type / function translation
//
// Windows Terminal setup (settings.json):
//   "experimental.pixelShaderPath": "path\\to\\blackhole.hlsl"
// Then Ctrl+Shift+P -> "Toggle terminal visual effects"

// ---------------------------------------------------------------- tunables --
// hole & lensing
static const float HOLE_RADIUS   = 0.0200;
static const float LENS_DEPTH    = 13.0000;
static const float STAR_GAIN     = 0.0000;
// accretion disk geometry (radii in Schwarzschild radii)
static const float DISK_INNER    = 1.8000;
static const float DISK_OUTER    = 8.0000;
static const float DISK_INCL     = 1.5000;
static const float DISK_ROLL     = 0.3500;
// accretion disk matter & light
static const float DISK_GAIN     = 2.2000;
static const float DISK_OPACITY  = 0.9000;
static const float DISK_TEMP     = 5500.0000;
static const float DOPPLER_MIX   = 0.6000;
static const float DISK_BEAM     = 2.5000;
static const float DISK_SPEED    = 5.0000;
static const float DISK_WIND     = 7.0000;
static const float DISK_CONTRAST = 1.6000;
// light & screen
static const float EXPOSURE      = 1.4000;
static const float DRIFT_SPEED   = 1.0000;
static const float WORK_AREA     = 0.3300;
static const float DILATION_MIN  = 0.2000;
static const float POMODORO_MAX_SCALE = 1.3000;
static const float POMODORO_GROW_EASE = 0.4500;
static const bool  POMODORO_DEBUG_BAR = true;

// geodesic integration steps per pixel
#define N_STEPS 48

// ---------------------------------------------------------------- size mode --
#define MODE_POMODORO 0
#define MODE_DEMO     1
#define SIZE_MODE MODE_POMODORO

// ------------------------------------------------------ pomodoro, self-contained --
// Windows Terminal currently exposes custom shader Time modulo 1000 seconds.
// The shader-only timer therefore uses a 1000-second cycle: 15:00 work,
// 1:40 rest. The rest window is centered on the WT wrap point so the wrap
// cannot interrupt a visible growth segment.
#define POMODORO_TIMER_SHADER_SHORT 0
#define POMODORO_TIMER_EXTERNAL     1
static const int   POMODORO_TIMER_MODE = POMODORO_TIMER_SHADER_SHORT;
static const float POMODORO_WT_WRAP_SEC = 1000.0000;
static const float POMODORO_SHADER_WORK_SEC = 900.0000;
static const float POMODORO_SHADER_BREAK_SEC = 100.0000;
static const float POMODORO_EXTERNAL_WORK_SEC = 2700.0000;
static const float POMODORO_EXTERNAL_BREAK_SEC = 300.0000;
static const float POMODORO_EXTERNAL_PHASE_SEC = 0.0000;
static const float POMODORO_EXTERNAL_WT_TIME_SEC = 0.0000;
static const float POMODORO_EXTERNAL_UPDATE_INTERVAL_SEC = 30.0000;

// --------------------------------------------------------------- physics --
#define B_CRIT 2.5980762
static const float TAU = 6.2831853;

// ------------------------------------------------------------- demo mode --
static const float DEMO_SEC      = 42.0000;
static const float DEMO_GROW_SEC = 40.0000;
static const float DEMO_XFADE    = 0.1800;

struct DiskLook {
    float temp, incl, roll, inner, outer, opac, dopp, beam,
          gain, contr, wind, speed, expo, star;
};

static const DiskLook LOOK_DEFAULT = {
    DISK_TEMP, DISK_INCL, DISK_ROLL, DISK_INNER, DISK_OUTER, DISK_OPACITY,
    DOPPLER_MIX, DISK_BEAM, DISK_GAIN, DISK_CONTRAST, DISK_WIND, DISK_SPEED,
    EXPOSURE, STAR_GAIN
};

#define DEMO_N 8
static const DiskLook DEMO_TOUR[DEMO_N] = {
    { 5500.0, 1.50, 0.35, 1.8, 8.0, 0.90, 0.60, 2.5, 2.2, 1.6, 7.0, 5.0, 1.40, 0.0 },
    { 4500.0, 1.52, 0.10, 2.2, 7.0, 0.85, 0.35, 2.0, 1.4, 0.5, 7.0, 5.0, 1.20, 0.0 },
    { 3800.0, 0.55, -0.30, 2.2, 6.0, 0.45, 0.90, 3.5, 1.6, 0.4, 3.0, 2.5, 1.10, 0.0 },
    { 6500.0, 0.30, 0.00, 3.0, 10.0, 0.50, 0.80, 2.5, 1.0, 1.1, 7.0, 5.0, 1.00, 0.0 },
    {15000.0, 1.30, 0.35, 3.0, 14.0, 0.35, 1.00, 4.0, 1.2, 1.3, 8.0, 5.0, 0.80, 0.0 },
    {18000.0, 1.05, 0.55, 3.0, 16.0, 0.30, 1.00, 5.0, 1.0, 1.5, 9.0, 6.0, 0.75, 0.0 },
    { 5500.0, 1.50, 0.35, 1.8, 8.0, 0.00, 1.00, 2.5, 0.0, 1.6, 7.0, 5.0, 1.00, 0.6 },
    { 5500.0, 1.50, 0.35, 1.8, 8.0, 0.90, 0.60, 2.5, 2.2, 1.6, 7.0, 5.0, 1.40, 0.0 }
};

DiskLook mixLook(DiskLook a, DiskLook b, float f) {
    DiskLook r;
    r.temp  = lerp(a.temp,  b.temp,  f);
    r.incl  = lerp(a.incl,  b.incl,  f);
    r.roll  = lerp(a.roll,  b.roll,  f);
    r.inner = lerp(a.inner, b.inner, f);
    r.outer = lerp(a.outer, b.outer, f);
    r.opac  = lerp(a.opac,  b.opac,  f);
    r.dopp  = lerp(a.dopp,  b.dopp,  f);
    r.beam  = lerp(a.beam,  b.beam,  f);
    r.gain  = lerp(a.gain,  b.gain,  f);
    r.contr = lerp(a.contr, b.contr, f);
    r.wind  = lerp(a.wind,  b.wind,  f);
    r.speed = lerp(a.speed, b.speed, f);
    r.expo  = lerp(a.expo,  b.expo,  f);
    r.star  = lerp(a.star,  b.star,  f);
    return r;
}

DiskLook demoLook(float t) {
    float u = fmod(t, DEMO_SEC) / DEMO_SEC * DEMO_N;
    int   i = (int)min(u, DEMO_N - 0.001);
    float f = smoothstep(1.0 - DEMO_XFADE, 1.0, frac(u));
    return mixLook(DEMO_TOUR[i], DEMO_TOUR[(i + 1) % DEMO_N], f);
}

// ------------------------------------------------------------------- noise --
float hash21(float2 p) {
    p = frac(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return frac(p.x * p.y);
}

float vnoiseWrapY(float2 p, float perY) {
    float2 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float y0 = i.y - perY * floor(i.y / perY);
    float y1 = (i.y + 1.0) - perY * floor((i.y + 1.0) / perY);
    return lerp(lerp(hash21(float2(i.x, y0)), hash21(float2(i.x + 1.0, y0)), f.x),
                lerp(hash21(float2(i.x, y1)), hash21(float2(i.x + 1.0, y1)), f.x),
                f.y);
}

float2 mirrorUV(float2 u) { return 1.0 - abs(1.0 - fmod(u, 2.0)); }

float2 rot(float2 v, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float2 lissa(float t) {
    return float2(0.75 * sin(t * 0.37) + 0.25 * sin(t * 0.83 + 1.0),
                  0.70 * sin(t * 0.54 + 2.1) + 0.30 * sin(t * 1.07));
}

float3 blackbody(float T) {
    float t = clamp(T, 1500.0, 40000.0) / 100.0;
    float r, g, b;
    if (t <= 66.0) {
        r = 1.0;
        g = clamp(0.3900816 * log(t) - 0.6318414, 0.0, 1.0);
    } else {
        float warm = max(t - 60.0, 1e-4);
        r = clamp(1.292936 * pow(warm, -0.1332047), 0.0, 1.0);
        g = clamp(1.1298909 * pow(warm, -0.0755148), 0.0, 1.0);
    }
    if (t >= 66.0) {
        b = 1.0;
    } else if (t <= 19.0) {
        b = 0.0;
    } else {
        b = clamp(0.5432068 * log(max(t - 10.0, 1e-4)) - 1.1962540, 0.0, 1.0);
    }
    return float3(r, g, b);
}

float3 stars(float3 d, float t) {
    float2 sph = float2(atan2(d.x, -d.z), asin(clamp(d.y, -1.0, 1.0)));
    float2 g   = sph * 40.0;
    float2 id  = floor(g);
    float  h   = hash21(id);
    if (h < 0.92) return float3(0.0, 0.0, 0.0);
    float2 f   = frac(g) - 0.5;
    float2 off = (float2(hash21(id + 17.3), hash21(id + 31.7)) - 0.5) * 0.7;
    float spark = smoothstep(0.10, 0.0, length(f - off));
    float tw    = 0.7 + 0.3 * sin(t * (0.5 + 2.0 * hash21(id + 5.1)) + 40.0 * h);
    float3 tint = lerp(float3(1.0, 0.82, 0.60), float3(0.75, 0.85, 1.0), hash21(id + 2.9));
    return tint * spark * tw * ((h - 0.92) / 0.08);
}

float periodicSin(float t, float cycles, float phase) {
    return sin(TAU * cycles * t / POMODORO_WT_WRAP_SEC + phase);
}

float wrappedDelta(float nowSec, float baseSec, float wrapSec) {
    return wrapSec * frac((nowSec - baseSec) / wrapSec);
}

struct PomodoroTimer {
    float cyclePhaseSec;
    float workPhaseSec;
    float workSec;
    float breakSec;
    float cycleSec;
    float reloadAgeSec;
};

PomodoroTimer pomodoroTimer(float wtTimeSec) {
    PomodoroTimer timer;
    if (POMODORO_TIMER_MODE == POMODORO_TIMER_EXTERNAL) {
        timer.workSec = POMODORO_EXTERNAL_WORK_SEC;
        timer.breakSec = POMODORO_EXTERNAL_BREAK_SEC;
        timer.cycleSec = timer.workSec + timer.breakSec;
        timer.reloadAgeSec = wrappedDelta(wtTimeSec, POMODORO_EXTERNAL_WT_TIME_SEC, POMODORO_WT_WRAP_SEC);
        timer.cyclePhaseSec = timer.cycleSec * frac((POMODORO_EXTERNAL_PHASE_SEC + timer.reloadAgeSec) / timer.cycleSec);
        timer.workPhaseSec = (timer.cyclePhaseSec < timer.workSec) ? timer.cyclePhaseSec : -1.0;
    } else {
        timer.workSec = POMODORO_SHADER_WORK_SEC;
        timer.breakSec = POMODORO_SHADER_BREAK_SEC;
        timer.cycleSec = timer.workSec + timer.breakSec;
        timer.reloadAgeSec = fmod(wtTimeSec, 60.0);
        timer.cyclePhaseSec = fmod(wtTimeSec + timer.workSec, timer.cycleSec);
        timer.workPhaseSec = (timer.cyclePhaseSec < timer.workSec) ? timer.cyclePhaseSec : -1.0;
    }
    return timer;
}

float4 pomodoroDebugBar(float4 color, float2 uv, float cycleNorm, float grow,
                        float wtWrapNorm, float minuteNorm) {
    if (!POMODORO_DEBUG_BAR || uv.y > 0.066) return color;

    float3 bar = float3(0.04, 0.04, 0.04);
    if (uv.y <= 0.018) {
        if (uv.x <= saturate(grow)) bar = float3(0.20, 0.85, 0.30);
    } else if (uv.y >= 0.024 && uv.y <= 0.042) {
        if (uv.x <= saturate(cycleNorm)) bar = float3(0.15, 0.35, 0.95);
    } else if (uv.y >= 0.048) {
        if (uv.x <= saturate(wtWrapNorm)) bar = float3(0.95, 0.18, 0.12);
        if (uv.x <= saturate(minuteNorm)) bar = float3(0.10, 0.85, 0.95);
    }
    return float4(lerp(color.rgb, bar, 0.85), color.a);
}

// -------------------------------------------------------------- main pass --
Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings {
    float  Time;
    float  Scale;
    float2 Resolution;
    float4 Background;
};

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET {
    float2 res    = Resolution.xy;
    float2 uv     = tex;
    float  aspect = res.x / res.y;

    float yUp = 1.0 - uv.y;

    float wtTime = POMODORO_WT_WRAP_SEC * frac(Time / POMODORO_WT_WRAP_SEC);
    float shaderTime = wtTime;
    float t = wtTime * DRIFT_SPEED;

    DiskLook L = LOOK_DEFAULT;
    if (SIZE_MODE == MODE_DEMO) L = demoLook(shaderTime);

    float rin  = max(L.inner, 1.6);
    float rout = max(L.outer, rin + 0.5);

    float I, sz;
    float2 center;
    float debugPhaseNorm = 0.0;
    float debugGrow = 0.0;
    float debugWtWrapNorm = wtTime / POMODORO_WT_WRAP_SEC;
    float debugReloadNorm = frac(wtTime / 60.0);

    if (SIZE_MODE == MODE_POMODORO) {
        PomodoroTimer timer = pomodoroTimer(wtTime);
        float workSec  = max(timer.workSec, 1.0);
        float cycleSec = max(timer.cycleSec, workSec + 1.0);

        float phase = timer.workPhaseSec;
        float collapse = min(60.0, workSec * 0.15);
        float growEnd = max(workSec - collapse, 1.0);
        float growUp = saturate(phase / growEnd);
        float shrink = 1.0 - smoothstep(growEnd, workSec, phase);
        float grow = (phase >= 0.0) ? growUp * shrink : 0.0;
        debugPhaseNorm = timer.cyclePhaseSec / cycleSec;
        debugGrow = grow;
        debugReloadNorm = (POMODORO_TIMER_MODE == POMODORO_TIMER_EXTERNAL)
            ? saturate(timer.reloadAgeSec / max(POMODORO_EXTERNAL_UPDATE_INTERVAL_SEC, 1.0))
            : frac(wtTime / 60.0);

        I = lerp(0.12, 1.0, grow);
        float visualGrow = pow(saturate(grow), POMODORO_GROW_EASE);
        float baseSz = lerp(0.22, 1.0, lerp(0.12, 1.0, visualGrow));
        sz = baseSz * lerp(1.0, POMODORO_MAX_SCALE, grow * grow);

        float ext = (rout / B_CRIT) * HOLE_RADIUS * sz;
        float yLo = WORK_AREA + 0.12 + ext;
        float yHi = max(yLo, 0.90 - ext);
        float spd = lerp(0.35, 1.0, I);
        float yDrift = clamp(0.5 + (0.42 * periodicSin(wtTime, 25.0, 2.0) + 0.08 * periodicSin(wtTime, 19.0, 0.0)) * spd,
                             0.0, 1.0);
        center = float2(
            0.5 + (0.24 * periodicSin(wtTime, 33.0, 0.0) + 0.05 * periodicSin(wtTime, 13.0, 0.0)) * spd,
            1.0 - lerp(yLo, yHi, yDrift));
        center += I * float2(0.040 * periodicSin(wtTime, 132.0, 0.0) + 0.020 * periodicSin(wtTime, 209.0, 0.0),
                             0.030 * periodicSin(wtTime, 164.0, 1.0));
        float xMargin = min(ext / max(aspect, 1e-4), 0.45);
        center = clamp(center, float2(xMargin, 1.0 - yHi), float2(1.0 - xMargin, 1.0 - yLo));
    } else {
        float lvl = min(fmod(shaderTime, DEMO_SEC) / DEMO_GROW_SEC, 1.0);
        if (lvl < 0.0) { return pomodoroDebugBar(shaderTexture.Sample(samplerState, uv), uv, debugPhaseNorm, debugGrow, debugWtWrapNorm, debugReloadNorm); }
        float g = pow(clamp(lvl, 0.0, 1.0), 1.0);
        I = lerp(0.10, 1.0, g);

        float rhMin = sqrt(0.0006 * aspect / 3.1415927);
        float rhMax = sqrt(0.50 * aspect / 3.1415927);
        float rhT = lerp(rhMin, rhMax, g) * (HOLE_RADIUS / 0.08);
        sz = rhT / max(HOLE_RADIUS, 1e-4);

        float marg = min(rhT * lerp(1.45, 0.90, g), 0.5 * (1.0 - WORK_AREA - 0.03));
        float xPad = marg / aspect;
        float2 fullLo = float2(min(xPad, 0.5), marg);
        float2 fullHi = float2(max(0.5, 1.0 - xPad),
                                max(marg, 1.0 - (WORK_AREA + 0.03 + marg)));
        float2 corner = clamp(float2(0.96, 0.04), fullLo, fullHi);
        float  reach  = lerp(0.06, max(1.0, 0.06), g);
        float2 lo = float2(lerp(corner.x, fullLo.x, reach), fullLo.y);
        float2 hi = float2(fullHi.x, lerp(corner.y, fullHi.y, reach));
        float2 room   = max((hi - lo) * 0.5, float2(0.0, 0.0));
        float2 wobAmp = min(float2(0.010 + 0.030 * g, 0.010 + 0.030 * g), max(room * 0.35, float2(0.006, 0.006)));
        float2 ampEff = max(room - wobAmp, float2(0.0, 0.0));
        float2 wander = lerp(lissa(t * 0.04), lissa(t * 1.1), g);
        center = (lo + hi) * 0.5 + wander * ampEff
               + wobAmp * float2(cos(t * 0.8), sin(t * 1.0));
    }

    float vis = smoothstep(0.0, 0.10, I);
    if (vis <= 0.0) {
        return pomodoroDebugBar(shaderTexture.Sample(samplerState, uv), uv, debugPhaseNorm, debugGrow, debugWtWrapNorm, debugReloadNorm);
    }

    float rh = HOLE_RADIUS * sz;

    float dil = lerp(1.0, DILATION_MIN, I);

    float shield = vis * smoothstep(WORK_AREA, WORK_AREA + 0.18, yUp);

    float2  p    = (uv - center) * float2(aspect, 1.0);
    float plen = length(p);

    float W  = B_CRIT / max(rh, 1e-4);
    float2 pr = rot(float2(p.x, -p.y), L.roll) * W;
    float b  = length(pr);

    float window = exp(-pow(plen / (7.0 * rh), 2.0));

    float bmax = rout + 3.0;
    float Z0   = max(14.0, rout + 5.0);

    // ================= far field: analytic weak deflection ==================
    if (b >= bmax) {
        float u    = Z0 * rsqrt(Z0 * Z0 + b * b);
        float defl = (2.0 / (W * W)) / max(plen, 1e-4)
                   * (1.29 * u + 0.07) * max(LENS_DEPTH - 2.14 * u + 0.75, 0.0)
                   * window * shield;
        float2 dir  = p / max(plen, 1e-5);
        float ab = 0.035 * smoothstep(1.0, 2.0, b / bmax);
        float2 suvR = mirrorUV(center + (p - dir * defl * (1.0 - ab)) / float2(aspect, 1.0));
        float2 suvG = mirrorUV(center + (p - dir * defl) / float2(aspect, 1.0));
        float2 suvB = mirrorUV(center + (p - dir * defl * (1.0 + ab)) / float2(aspect, 1.0));
        float3 term = float3(
            shaderTexture.Sample(samplerState, suvR).r,
            shaderTexture.Sample(samplerState, suvG).g,
            shaderTexture.Sample(samplerState, suvB).b);
        float3 d = normalize(float3(-(pr / b) * (2.0 / b), -1.0));
        return pomodoroDebugBar(float4(term + stars(d, shaderTime) * L.star * window * shield, 1.0), uv, debugPhaseNorm, debugGrow, debugWtWrapNorm, debugReloadNorm);
    }

    // ====================== near field: trace the geodesic ==================
    float3  x  = float3(pr, Z0);
    float3  v  = float3(0.0, 0.0, -1.0);
    float h2 = dot(pr, pr);

    float ci = cos(L.incl), si = sin(L.incl);
    float3  n  = float3(0.0, si, ci);
    float3  e2 = float3(0.0, ci, -si);
    float sdir = L.speed < 0.0 ? -1.0 : 1.0;
    float spd  = abs(L.speed);

    float3 emitc = float3(0.0, 0.0, 0.0);
    float trans = 1.0;
    bool  captured = false;
    float sPrev = dot(x, n);
    float3 xPrev = x;

    for (int i = 0; i < N_STEPS; i++) {
        float r2 = dot(x, x);
        if (r2 < 1.0) { captured = true; break; }
        if (x.z < -Z0 && v.z < 0.0) break;
        if (r2 > 4.0 * Z0 * Z0) break;
        float r  = sqrt(r2);
        float dt = clamp(0.16 * r, 0.03, 1.5);
        float3 a = -1.5 * h2 * x / (r2 * r2 * r);
        v += a * (0.5 * dt);
        x += v * dt;
        r2 = dot(x, x);
        r  = sqrt(r2);
        a  = -1.5 * h2 * x / (r2 * r2 * r);
        v += a * (0.5 * dt);

        float s = dot(x, n);
        if (s * sPrev < 0.0 && trans > 0.02) {
            float tc = sPrev / (sPrev - s);
            float3 xc = lerp(xPrev, x, tc);
            float rc = length(xc);
            if (rc > rin && rc < rout) {
                float band = smoothstep(rin, rin * 1.25, rc)
                           * (1.0 - smoothstep(rout * 0.70, rout, rc));

                float phi   = atan2(dot(xc, e2), xc.x);
                float turns = phi / 6.2831853;
                float kep   = pow(rin / rc, 1.5);
                float gloc  = sqrt(max(1.0 - 1.5 / rc, 0.02));
                float swirl = rc * L.wind * 0.12 - t * kep * spd * gloc * dil * sdir;
                float streaks = vnoiseWrapY(float2(rc * 2.8, turns * 19.0 + swirl * 3.0), 19.0) * 0.65 +
                                vnoiseWrapY(float2(rc * 1.0, turns * 9.0  + swirl * 1.5 + 7.0), 9.0) * 0.35;
                streaks = 0.35 + L.contr * streaks * streaks;

                float3  gasdir = normalize(cross(n, xc)) * sdir;
                float   beta   = clamp(rsqrt(max(2.0 * (rc - 1.0), 0.2)), 0.0, 0.99);
                float   g      = gloc / max(1.0 + beta * dot(gasdir, normalize(v)), 0.05);
                g = lerp(1.0, g, L.dopp);

                float xpr   = max(1.0 - sqrt(rin / rc), 0.0);
                float tprof = pow(rin / rc, 0.75) * pow(xpr, 0.25) / 0.488;
                float3 cbb   = blackbody(L.temp * tprof * g);
                float boost = pow(g, L.beam);

                float density = band * streaks;
                emitc += trans * cbb * (L.gain * 2.2 * density * tprof * tprof * boost);
                trans *= 1.0 - clamp(L.opac * density, 0.0, 1.0);
            }
        }
        sPrev = s;
        xPrev = x;
    }
    if (!captured && dot(x, x) < 4.0) captured = true;

    float3 bg = float3(0.0, 0.0, 0.0);
    if (!captured) {
        float3 d = normalize(v);
        bg += stars(d, shaderTime) * L.star * window * shield;
        if (d.z < -0.05) {
            float tpl = (-LENS_DEPTH - x.z) / d.z;
            float3 hp  = x + d * tpl;
            float2 q   = rot(hp.xy, -L.roll) / W;
            float2 sp  = float2(q.x, -q.y);
            float2 suv = mirrorUV(center + (p + (sp - p) * window * shield) / float2(aspect, 1.0));
            float toward = smoothstep(0.05, 0.35, -d.z);
            bg += shaderTexture.Sample(samplerState, suv).rgb * toward;
        }
    }

    float3 col = bg * trans + (float3(1.0, 1.0, 1.0) - exp(-emitc * L.expo));
    return pomodoroDebugBar(float4(col, 1.0), uv, debugPhaseNorm, debugGrow, debugWtWrapNorm, debugReloadNorm);
}

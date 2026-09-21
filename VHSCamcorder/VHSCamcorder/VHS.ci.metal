#include <CoreImage/CoreImage.h>
using namespace metal;

// ponytail: hand-tuned constants, tune here by eye. A settings UI is out of scope.
constant float kHorizontalRes  = 380.0;  // effective luma resolution across the frame (real VHS ~240-320)
constant float kChromaBlur     = 12.0;   // px of horizontal chroma smear
constant float kChromaShift    = 3.0;    // px chroma lags luma to the right
constant float kSaturation     = 1.15;
constant float kWobble         = 1.2;    // px baseline horizontal jitter
constant float kNoise          = 0.07;
constant float kScanline       = 0.08;

static float hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

static float3 rgb2yiq(float3 c) {
    return float3(dot(c, float3(0.299,  0.587,  0.114)),
                  dot(c, float3(0.596, -0.274, -0.322)),
                  dot(c, float3(0.211, -0.523,  0.312)));
}

static float3 yiq2rgb(float3 c) {
    return float3(c.x + 0.956 * c.y + 0.621 * c.z,
                  c.x - 0.272 * c.y - 0.647 * c.z,
                  c.x - 1.106 * c.y + 1.703 * c.z);
}

extern "C" {
namespace coreimage {

// All coordinate math happens in destination pixel space; src.transform maps into sampler space.
static float3 tap(sampler src, float x, float y) {
    return src.sample(src.transform(float2(x, y))).rgb;
}

float4 vhs(sampler src, float time, float width, float height, destination dest) {
    float2 p = dest.coord();          // pixel coords, origin bottom-left
    float y = p.y;

    // Tracking: gentle constant horizontal jitter.
    float wobble = sin(y * 0.02 + time * 3.0) * kWobble + sin(y * 0.13 - time * 9.0) * 0.4;

    float x = p.x + wobble;

    // Horizontal resolution loss: quantize x, then a soft 3-tap blur.
    float stepPx = width / kHorizontalRes;
    float qx = floor(x / stepPx) * stepPx + stepPx * 0.5;
    float3 l0 = tap(src, qx - stepPx, y);
    float3 l1 = tap(src, qx,          y);
    float3 l2 = tap(src, qx + stepPx, y);
    float luma = rgb2yiq((l0 + 2.0 * l1 + l2) * 0.25).x;

    // Chroma: much wider blur, shifted right so colors bleed past edges.
    float3 chroma = 0.0;
    for (int i = -4; i <= 4; i++) {
        float cx = qx + kChromaShift + float(i) * (kChromaBlur / 4.0);
        chroma += rgb2yiq(tap(src, cx, y));
    }
    chroma /= 9.0;

    float3 yiq = float3(luma, chroma.y * kSaturation, chroma.z * kSaturation);

    // Grain, heavier in the shadows.
    float n = hash(float2(floor(p.x * 0.5), floor(y)) + fract(time) * 97.0);
    yiq.x += (n - 0.5) * kNoise * (1.3 - yiq.x);

    // Scanlines on alternate rows.
    yiq.x *= 1.0 - kScanline * fmod(floor(y), 2.0);

    // Lifted blacks, softened whites.
    float3 rgb = yiq2rgb(yiq) * 0.92 + 0.04;
    return float4(clamp(rgb, 0.0, 1.0), 1.0);
}

}
}

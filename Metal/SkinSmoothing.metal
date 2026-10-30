#include <CoreImage/CoreImage.h>
using namespace metal;

// Frequency separation: variance-guided blend to a blur keeps edges, fine grain returns, a YCbCr mask limits it to skin.

constant float3 bt601 = float3(0.299, 0.587, 0.114);

// Squared luma detail against the blur; blurring it gives the local texture variance.
extern "C" float4 skinDetailEnergy(coreimage::sample_t s, coreimage::sample_t base) {
    float d = dot(s.rgb - base.rgb, bt601);
    return float4(d * d, d * d, d * d, 1.0);
}

static float3 toYCbCr(float3 c) {
    return float3(dot(c, bt601),
                  0.5 - 0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b,
                  0.5 + 0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b);
}

static float3 toRGB(float3 ycc) {
    float cb = ycc.y - 0.5, cr = ycc.z - 0.5;
    return float3(ycc.x + 1.402 * cr, ycc.x - 0.344136 * cb - 0.714136 * cr, ycc.x + 1.772 * cb);
}

static float skinLikelihood(float3 c) {
    float3 ycc = toYCbCr(c);
    return smoothstep(0.27, 0.31, ycc.y) * (1.0 - smoothstep(0.49, 0.53, ycc.y))
         * smoothstep(0.51, 0.54, ycc.z) * (1.0 - smoothstep(0.67, 0.71, ycc.z))
         * smoothstep(0.08, 0.18, ycc.x) * (1.0 - smoothstep(0.93, 0.99, ycc.x));
}

// Skin pixels weighted by how skin-like they are; blurred and divided by alpha, it gives the tone of the skin nearby.
extern "C" float4 skinWeighted(coreimage::sample_t s) {
    float w = skinLikelihood(s.rgb);
    return float4(s.rgb * w, w);
}

extern "C" float4 smoothSkin(coreimage::sample_t s, coreimage::sample_t base, coreimage::sample_t fine,
                             coreimage::sample_t energy, coreimage::sample_t skinAround, float amount, float blemishes) {
    float3 d = s.rgb - base.rgb;
    float variance = energy.r;
    float keep = variance / (variance + 0.0024);
    // Returning fine grain and capping the strength keep skin from looking waxy and pale.
    float3 smoothed = mix(s.rgb, base.rgb + keep * d + (1.0 - keep) * 0.45 * (s.rgb - fine.rgb), amount * 0.85);

    // Blemishes: small spots redder than the skin around them take its tone; large red areas (lips) differ too much to count.
    float3 ycc = toYCbCr(smoothed);
    float3 around = toYCbCr(skinAround.rgb / max(skinAround.a, 0.001));
    float fineCr = toYCbCr(fine.rgb).z;
    float redder = min(fineCr - around.z, fineCr - toYCbCr(base.rgb).z);
    float spot = blemishes * smoothstep(0.05, 0.2, skinAround.a)
               * smoothstep(0.005, 0.016, redder) * (1.0 - smoothstep(0.045, 0.075, redder));
    float3 healed = float3(ycc.x, around.y, around.z);
    float3 retouched = toRGB(mix(ycc, healed, spot));

    return float4(mix(s.rgb, saturate(retouched), skinLikelihood(base.rgb)), s.a);
}

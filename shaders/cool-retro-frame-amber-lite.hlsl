// cool-retro-frame-amber-lite.hlsl
//
// Performance variant of cool-retro-frame-amber.hlsl — the NERV-monochrome look,
// with the same 20-tap budget as cool-retro-frame-lite.hlsl.
//
// Original: Chael-Chael/awesome-hermes-eva-skins (MIT, © 2026 Chenyu Zhu),
// itself based on Microsoft Terminal samples/PixelShaders/Retro.hlsl.
//
// Differences from cool-retro-frame-lite.hlsl:
//   * no chroma preservation — everything converges on the amber phosphor
//   * wider glow rings (the amber shader used sigma 2.0 instead of 1.2)
//   * stronger chromatic aberration (0.35 instead of 0.12)
//
// Texture taps per pixel: 174 -> 20

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float Time;
    float Scale;
    float2 Resolution;
    float4 Background;
};

// ---------------------------------------------------------------- knobs -----
#define SCANLINE_FACTOR 0.26f
#define SCALED_SCANLINE_PERIOD Scale

#define GLOW_ENABLE 1
#define GLOW_INNER_RADIUS (3.6f * Scale)   // texels
#define GLOW_OUTER_RADIUS (8.0f * Scale)   // texels
#define GLOW_INNER_WEIGHT 0.55f
#define GLOW_STRENGTH 0.40f

#define ABERRATION_ENABLE 1
#define RGB_SHIFT 0.42f
#define RGB_ABERRATION_STRENGTH 0.35f

#define ENABLE_GRAIN 1
#define GRAIN_INTENSITY 0.012f
#define ENABLE_BLACKLEVEL 1
#define REFRESHLINE_STRENGTH 0.028f
#define CURVE_INTENSITY 0.55f

#define CRT_FONT_COLOR float3(1.000f, 0.620f, 0.105f)
#define CRT_BACKGROUND_COLOR float3(0.150f, 0.075f, 0.012f)
#define CRT_CHROMA 0.20f
#define CRT_SCREEN_BRIGHTNESS 1.3f
#define CRT_BLACK_FLOOR float3(0.055f, 0.038f, 0.013f)
#define CRT_DIM_TEXT_LUMA_GATE 0.075f
#define CRT_DIM_TEXT_LUMA_FLOOR 0.28f
#define OVERSCAN_PERCENTAGE 0.018f
#define FRAME_COLOR float3(0.030f, 0.026f, 0.020f)
#define BEZEL_COLOR float3(0.075f, 0.060f, 0.043f)
#define FRAME_HIGHLIGHT float3(0.24f, 0.20f, 0.15f)
#define VIGNETTE_STRENGTH 0.48f

static const float2 RING[8] = {
    float2( 1.0f,  0.0f), float2(-1.0f,  0.0f),
    float2( 0.0f,  1.0f), float2( 0.0f, -1.0f),
    float2( 0.7071f,  0.7071f), float2(-0.7071f,  0.7071f),
    float2( 0.7071f, -0.7071f), float2(-0.7071f, -0.7071f)
};

// --------------------------------------------------------------- helpers -----
float Luma(float3 color)
{
    return dot(color, float3(0.21f, 0.72f, 0.04f));
}

float ReadableLuma(float grey)
{
    float contentMask = smoothstep(CRT_DIM_TEXT_LUMA_GATE, CRT_DIM_TEXT_LUMA_GATE + 0.035f, grey);
    return lerp(grey, max(grey, CRT_DIM_TEXT_LUMA_FLOOR), contentMask);
}

float3 ConvertWithChroma(float3 sourceColor)
{
    float grey = Luma(sourceColor);
    float visibleGrey = ReadableLuma(grey);
    float denom = max(grey, 0.0001f);
    float3 chromaForeground = sourceColor * CRT_FONT_COLOR / denom;
    float3 foreground = lerp(CRT_FONT_COLOR, chromaForeground, CRT_CHROMA);
    return lerp(CRT_BACKGROUND_COLOR, foreground, saturate(visibleGrey));
}

float Hash(float2 p)
{
    return frac(sin(dot(p, float2(12.9898f, 78.233f)) + Time * 31.17f) * 43758.5453f);
}

float2 Curve(float2 tex)
{
    tex -= 0.5f;
    float radius = dot(tex, tex) * CURVE_INTENSITY;
    tex *= 4.2f + radius;
    tex *= 0.25f;
    tex += 0.5f;
    return tex;
}

float4 GlowLite(float2 uv)
{
    float2 texel = 1.0f / Resolution;

    float4 sum = shaderTexture.Sample(samplerState, uv) * (1.0f - GLOW_INNER_WEIGHT);

    float innerW = GLOW_INNER_WEIGHT * 0.5f / 8.0f;
    float outerW = GLOW_INNER_WEIGHT * 0.5f / 8.0f;

    [unroll]
    for (int i = 0; i < 8; i++)
    {
        sum += shaderTexture.Sample(samplerState, uv + RING[i] * texel * GLOW_INNER_RADIUS) * innerW;
        sum += shaderTexture.Sample(samplerState, uv + RING[i] * texel * GLOW_OUTER_RADIUS) * outerW;
    }

    return sum;
}

float SquareWave(float y)
{
    return 1.0f - (floor(y / SCALED_SCANLINE_PERIOD) % 2.0f) * SCANLINE_FACTOR;
}

float4 Frame(float2 tex, float2 curvedTex, float4 color)
{
    if (curvedTex.x < -0.025f || curvedTex.y < -0.025f || curvedTex.x > 1.025f || curvedTex.y > 1.025f)
    {
        return float4(0, 0, 0, 1);
    }

    if (curvedTex.x < -0.015f || curvedTex.y < -0.015f || curvedTex.x > 1.015f || curvedTex.y > 1.015f)
    {
        float edgeLight = smoothstep(-0.025f, -0.015f, min(min(curvedTex.x, curvedTex.y), min(1.025f - curvedTex.x, 1.025f - curvedTex.y)));
        return float4(lerp(FRAME_COLOR, BEZEL_COLOR, edgeLight), 1);
    }

    if (curvedTex.x < -0.001f || curvedTex.y < -0.001f || curvedTex.x > 1.001f || curvedTex.y > 1.001f)
    {
        return float4(0, 0, 0, 1);
    }

    float edge = min(min(curvedTex.x, 1.0f - curvedTex.x), min(curvedTex.y, 1.0f - curvedTex.y));
    float innerShadow = 1.0f - smoothstep(0.000f, 0.075f, edge);
    float topShadow = 1.0f - smoothstep(0.03f, 0.18f, tex.y);
    float bottomShadow = smoothstep(0.80f, 1.0f, tex.y);
    float topLight = innerShadow * smoothstep(0.0f, 0.55f, 1.0f - tex.y);
    float2 centered = tex - 0.5f;
    float vignette = smoothstep(0.18f, 0.78f, dot(centered, centered) * 2.2f);

    color.rgb *= 1.0f - vignette * VIGNETTE_STRENGTH;
    color.rgb *= 1.0f - innerShadow * 0.34f;
    color.rgb *= 1.0f - topShadow * 0.20f;
    color.rgb *= 1.0f - bottomShadow * 0.18f;
    color.rgb += FRAME_HIGHLIGHT * topLight * 0.08f;
    return color;
}

// ------------------------------------------------------------------ main -----
float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float2 curvedTex = Curve(tex);

    float2 sampleTex = curvedTex;
    sampleTex -= 0.5f;
    sampleTex *= 1.0f / (1.0f - OVERSCAN_PERCENTAGE);
    sampleTex += 0.5f;

    bool inside = sampleTex.x >= 0.0f && sampleTex.y >= 0.0f && sampleTex.x <= 1.0f && sampleTex.y <= 1.0f;

    float4 sourceColor = float4(0, 0, 0, 1);
    if (inside)
    {
        sourceColor = shaderTexture.Sample(samplerState, sampleTex);
    }

    float3 color = ConvertWithChroma(sourceColor.rgb) * CRT_SCREEN_BRIGHTNESS;

#if ABERRATION_ENABLE
    if (inside)
    {
        float2 centerDir = normalize((tex - 0.5f) + float2(0.0001f, 0.0001f));
        float2 rgbOffset = centerDir * RGB_SHIFT / Resolution;
        float centerLuma = Luma(sourceColor.rgb);
        float3 sourceRed = shaderTexture.Sample(samplerState, saturate(sampleTex + rgbOffset)).rgb;
        float3 sourceBlue = shaderTexture.Sample(samplerState, saturate(sampleTex - rgbOffset)).rgb;
        float redEdge = max(0.0f, Luma(sourceRed) - centerLuma);
        float blueEdge = max(0.0f, Luma(sourceBlue) - centerLuma);
        color += float3(redEdge, 0.0f, blueEdge) * RGB_ABERRATION_STRENGTH;
    }
#endif

#if ENABLE_BLACKLEVEL
    color = max(color, CRT_BLACK_FLOOR);
#endif

#if GLOW_ENABLE
    if (inside)
    {
        float4 glow = GlowLite(sampleTex);
        color += ConvertWithChroma(glow.rgb) * GLOW_STRENGTH * saturate(Luma(glow.rgb) * 1.7f);
    }
#endif

    float refresh = smoothstep(0.025f, 0.0f, abs(sampleTex.y - frac(Time / 5.0f)));
    color += refresh * REFRESHLINE_STRENGTH;

#if ENABLE_GRAIN
    color += (Hash(tex * Resolution) - 0.5f) * GRAIN_INTENSITY;
#endif

    float4 result = float4(color, 1);
    result *= SquareWave(pos.y);
    result = Frame(tex, curvedTex, result);
    result.a = 1.0f;

    return saturate(result);
}

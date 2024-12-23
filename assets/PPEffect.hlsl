
Texture2D tex : register(t0);
SamplerState texSampler : register(s0);

cbuffer globalUniforms: register(b0) {
    int2 resolution;
    float time;
}

cbuffer uniforms: register(b1) {
    float brightness;
}

struct VSOut {
    float4 pos: SV_POSITION;
    float2 uv: TEX;
};

VSOut vs_main(uint spriteId: SV_INSTANCEID, uint vertexId : SV_VERTEXID) {
    uint2 i = { vertexId & 2, (vertexId << 1 & 2) ^ 3 };

    float4 pos = float4(-1, -1, 1, 1);
    float4 tex = float4(0, 1, 1, 0);

    VSOut output;
    output.pos = float4(pos[i.x], pos[i.y], 0, 1);
    output.uv = float2(tex[i.x], tex[i.y]);

    return output;
}

float4 ps_main(VSOut input) : SV_TARGET
{
    int2 pixel = floor(input.uv * resolution);
    int op = (int) pixel.x % 3;

    float3 col = tex.Sample(texSampler, input.uv).rgb;
    float3 original = col;

    // CRT points mask
    const float maskValue1 = 0.51;
    const float maskValue2 = 0.255;
    const float scanlineValue = 0.1;

    float3 mults[3] = {
        float3(1, maskValue1, maskValue2),
        float3(maskValue1, 1, maskValue2),
        float3(maskValue1, maskValue2, 1),
    };

    float3 m = mults[op];
    m *= pixel.y % 3 == 0 ? scanlineValue : 1;

    col *= m;

    // brightness
    // const float brightness = 1.3;
    col *= 1 + brightness;

    // contrast
    const float contrast = .5;
    col = col - contrast * (col - 1) * col * (col - 0.5);

    // return float4(input.uv.x > 0.5 ? col : original, 1);
    return float4(col, 1);
}
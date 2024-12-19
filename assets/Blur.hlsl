
Texture2D tex : register(t0);
SamplerState texSampler : register(s0);

cbuffer globalUniforms: register(b0) {
    int2 resolution;
    float time;
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
    const float kernel[9] = { 1.0 / 16, 2.0 / 16, 1.0 / 16,
                              2.0 / 16, 4.0 / 16, 2.0 / 16,
                              1.0 / 16, 2.0 / 16, 1.0 / 16 };

    float3 col = tex.Sample(texSampler, input.uv).rgb;
    float3 original = col;

    col = 0;
    int i = 0;
    for(int x = -1; x <= 1; x++) {
        for(int y = -1; y <= 1; y++) {
            float2 offset = float2(x, y) / resolution;
            float3 sample = tex.Sample(texSampler, input.uv + offset).rgb;
            col += sample * kernel[i++];
        }
    }

    return float4(col, 1);
}
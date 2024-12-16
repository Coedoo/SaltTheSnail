
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
    float3 col = tex.Sample(texSampler, input.uv).rgb;

    return float4(1 - col, 1);
}
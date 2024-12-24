#if defined(VERTEX)
precision mediump float;

layout(std140) uniform globalUniforms {
    vec2 resolution;
    float time;
};

out vec2 uv;

void main() {
    const vec4 pos = vec4(-1, -1, 1, 1);

    ivec2 i = ivec2(gl_VertexID & 2, (gl_VertexID << 1 & 2) ^ 3);
    gl_Position = vec4(pos[i.x], pos[i.y], 0.0, 1.0);

    vec4 tex = vec4(0.0, 0.0, 1.0, 1.0);
    uv = vec2(tex[i.x], tex[i.y]);
}

#elif defined(FRAGMENT)
precision mediump float;

in vec2 uv;

out vec4 FragColor;

uniform sampler2D tex;

void main() {
    const float innerRadius = 0.7;
    const float outerRadius = 1.6;

    vec3 col = texture(tex, uv).rgb;
    col = pow(col, vec3(2.2));

    vec2 p = uv * 2.0 - 1.0;
    float v = 1.0 - smoothstep(innerRadius, outerRadius, length(p));

    col *= v;
    col = pow(col, vec3(1.0 / 2.2));

    FragColor = vec4(col, 1.0);
}

#endif
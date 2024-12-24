#if defined(VERTEX)
precision mediump float;
precision highp int;

layout(std140) uniform globalUniforms {
    ivec2 resolution;
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
precision highp int;

layout(std140) uniform globalUniforms {
    ivec2 resolution;
    float time;
};

in vec2 uv;

out vec4 FragColor;

uniform sampler2D tex;

void main() {
    float kernel[9] = float[] (1.0 / 16.0, 2.0 / 16.0, 1.0 / 16.0,
                               2.0 / 16.0, 4.0 / 16.0, 2.0 / 16.0,
                               1.0 / 16.0, 2.0 / 16.0, 1.0 / 16.0 );

    // vec4 col = texture(tex, uv);

    vec3 col = vec3(0.0, 0.0, 0.0);
    int i = 0;
    for(int x = -1; x <= 1; x++) {
        for(int y = -1; y <= 1; y++) {
            vec2 offset = vec2(x, y) / vec2(resolution);
            vec3 texSample = texture(tex, uv + offset).rgb;
            col += texSample * kernel[i++];
        }
    }
    FragColor = vec4(col.rgb, 1.0);
}

#endif
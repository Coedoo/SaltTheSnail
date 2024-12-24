#if defined(VERTEX)
precision mediump float;

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

layout(std140) uniform globalUniforms {
    ivec2 resolution;
    float time;
};

layout(std140) uniform uniforms {
    float brightness;
};

in vec2 uv;

out vec4 FragColor;

uniform sampler2D tex;

void main() {
    vec2 pixel = floor(uv * vec2(resolution));
    int op = int(pixel.x) % 3;

    vec3 col = texture(tex, uv).rgb;
    // gamma to linear
    col = pow(col, vec3(2.2));
    // vec3 original = col;

    // CRT points mask
    const float maskValue1 = 0.51;
    const float maskValue2 = 0.255;
    const float scanlineValue = 0.1;

    vec3 mults[3] = vec3[3](
        vec3(1.0, maskValue1, maskValue2),
        vec3(maskValue1, 1.0, maskValue2),
        vec3(maskValue1, maskValue2, 1.0)
    );

    vec3 m = mults[op];
    m *= int(pixel.y) % 3 == 0 ? scanlineValue : 1.0;

    col *= m;

    // brightness
    // const float brightness = 1.3;
    col *= 1.0 + brightness;

    // contrast
    const float contrast = .5;
    col = col - contrast * (col - 1.0) * col * (col - 0.5);

    // linear to gamma
    col = pow(col, vec3(1.0 / 2.2));
    FragColor = vec4(col, 1.0);
}

#endif
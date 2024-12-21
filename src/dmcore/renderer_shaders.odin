package dmcore

DefaultShaderType :: enum {
    Blit,
    Sprite,
    ScreenSpaceRect,
    SDFFont,
    Grid,
}

Shader :: struct {
    handle: ShaderHandle,
    name: string,
    using backend: _Shader,
}

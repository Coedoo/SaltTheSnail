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
    using backend: _Shader,
}

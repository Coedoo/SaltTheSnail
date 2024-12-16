package dmcore

PPHandle :: Handle

PostProcessGlobalData :: struct #align(16) {
    resolution: iv2,
    time: f32,
}

PostProcess :: struct {
    handle: PPHandle,

    isActive: bool,
    isDirty: bool,

    uniformBuffer: GPUBufferHandle,
    shader: ShaderHandle,
}

CreatePostProcess :: proc(shader: ShaderHandle, uniformData: any = nil) -> PPHandle {
    pp := CreateElement(&renderCtx.postProcess)
    pp.shader = shader
    pp.isActive = true

    if uniformData != nil {
        pp.uniformBuffer = CreateGPUBuffer(uniformData)
        pp.isDirty = true
    }

    return pp.handle
}

PostProcessUpdateData :: proc(pp: PPHandle) {
    ptr, ok := GetElementPtr(renderCtx.postProcess, pp)
    if ok {
        ptr.isDirty = true
    }
}
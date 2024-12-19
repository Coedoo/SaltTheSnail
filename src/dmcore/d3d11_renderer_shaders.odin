#+build windows
package dmcore

import d3d11 "vendor:directx/d3d11"
import d3d "vendor:directx/d3d_compiler"

import "core:fmt"


_Shader :: struct {
    vertexShader: ^d3d11.IVertexShader,
    pixelShader: ^d3d11.IPixelShader,
}

CompileShaderSource :: proc(renderCtx: ^RenderContext, source: string) -> ShaderHandle {
    shader := CreateElement(&renderCtx.shaders)

    if InitShaderSource(renderCtx, shader, source) {
        return shader.handle
    }

    return shader.handle
}

InitShaderSource :: proc(renderCtx: ^RenderContext, shader: ^Shader, source: string) -> (result: bool) {
    error: ^d3d11.IBlob
    vsBlob: ^d3d11.IBlob

    hr := d3d.Compile(raw_data(source), len(source), "shaders.hlsl", nil, nil, 
                      "vs_main", "vs_5_0", 0, 0, &vsBlob, &error)

    defer if result == false {
        if error               != nil do error->Release()
        if vsBlob              != nil do vsBlob->Release()
        if shader.vertexShader != nil do shader.vertexShader->Release()
        if shader.pixelShader  != nil do shader.pixelShader->Release()

        shader.pixelShader = nil
        shader.vertexShader = nil
    }

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        result = false
        return
    }

    hr = renderCtx.device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), 
                                         nil, &shader.backend.vertexShader)

    if hr != 0 {
        fmt.printf("%x\n", transmute(u32) hr)
        hr = renderCtx.device->GetDeviceRemovedReason()

        result = false
        return
    }

    psBlob: ^d3d11.IBlob
    hr = d3d.Compile(raw_data(source), len(source), "shaders.hlsl", nil, nil,
                     "ps_main", "ps_5_0", 0, 0, &psBlob, &error)

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        result = false
        return
    }

    hr = renderCtx.device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), 
                                        nil, &shader.backend.pixelShader)

    if hr != 0 {
        fmt.printf("%x\n", transmute(u32) hr)

        result = false
        return
    }

    psBlob->Release()
    vsBlob->Release()
    return true
}


DestroyShader :: proc(renderCtx: ^RenderContext, handle: ShaderHandle, freeHandle := true) {
    shader, ok := GetElementPtr(renderCtx.shaders, handle)
    if ok == false {
        return
    }

    if shader.vertexShader != nil {
        shader.vertexShader->Release()
    }

    if shader.pixelShader != nil {
        shader.pixelShader->Release()
    }

    if freeHandle {
        shader.vertexShader = nil
        shader.pixelShader = nil
        FreeSlot(&renderCtx.shaders, handle)
    }
}
#+build windows
package dmcore

import "core:mem"
import "core:fmt"

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

FramebufferBackend :: struct {
    renderTargetView: ^d3d11.IRenderTargetView,
    textureView: ^d3d11.IShaderResourceView,
}

InitFramebuffer :: proc(ctx: ^RenderContext, framebuffer: ^Framebuffer) {
    desc := d3d11.TEXTURE2D_DESC {
        Width      = cast(u32) framebuffer.width,
        Height     = cast(u32) framebuffer.height,
        MipLevels  = 1,
        ArraySize  = 1,
        Format     = .R32G32B32A32_FLOAT,
        SampleDesc = {Count = 1},
        Usage      = .DEFAULT,
        BindFlags  = {.SHADER_RESOURCE, .RENDER_TARGET},
    }

    d3dTexture: ^d3d11.ITexture2D
    ctx.device->CreateTexture2D(&desc, nil, &d3dTexture)

    ctx.device->CreateRenderTargetView(d3dTexture, nil, &framebuffer.renderTargetView)
    ctx.device->CreateShaderResourceView(d3dTexture, nil, &framebuffer.textureView)

    d3dTexture->Release()
}

DeinitFramebuffer :: proc(framebuffer: ^Framebuffer) {
    if framebuffer.renderTargetView != nil {
        framebuffer.renderTargetView->Release()
        framebuffer.renderTargetView = nil
    }

    if framebuffer.textureView != nil {
        framebuffer.textureView->Release()
        framebuffer.textureView = nil
    }
}


GPUBufferBackend :: struct {
    d3dBuffer: ^d3d11.IBuffer,
}

BackendInitGPUBuffer :: proc(buff: ^GPUBuffer) {
    constBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = cast(u32) buff.dataLen,
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    renderCtx.device->CreateBuffer(&constBuffDesc, nil, &buff.d3dBuffer)
}

BackendUpdateBufferData :: proc(buff: ^GPUBuffer) {
    mapped: d3d11.MAPPED_SUBRESOURCE
    res := renderCtx.deviceContext->Map(buff.d3dBuffer, 0, .WRITE_DISCARD, nil, &mapped)
    if res == 0 {
        mem.copy(mapped.pData, buff.dataPtr, buff.dataLen)
    }
    else {
        fmt.eprintln("Cannot Updload data of uniform buffer. Error Code:", res)
    }
    renderCtx.deviceContext->Unmap(buff.d3dBuffer, 0)
}
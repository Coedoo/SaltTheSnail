#+build windows
package dmcore

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

// import sdl "vendor:sdl2"

import "core:fmt"
import "core:c/libc"
import "core:mem"

import sa "core:container/small_array"

import "core:image"

import "core:math/linalg/glsl"

BlitShaderSource := #load("shaders/hlsl/Blit.hlsl", string)
ScreenSpaceRectShaderSource := #load("shaders/hlsl/ScreenSpaceRect.hlsl", string)
SpriteShaderSource := #load("shaders/hlsl/Sprite.hlsl", string)
SDFFontSource := #load("shaders/hlsl/SDFFont.hlsl", string)
GridShaderSource := #load("shaders/hlsl/Grid.hlsl", string)

//////////////////////
/// RENDER CONTEXT
//////////////////////

RenderContextBackend :: struct {
    device: ^d3d11.IDevice,
    deviceContext: ^d3d11.IDeviceContext,
    swapchain: ^dxgi.ISwapChain1,

    rasterizerState: ^d3d11.IRasterizerState,

    ppRenderTargetSrc: ^d3d11.IRenderTargetView,
    ppTextureSrc: ^d3d11.IShaderResourceView,

    ppRenderTargetDest: ^d3d11.IRenderTargetView,
    ppTextureDest: ^d3d11.IShaderResourceView,

    ppTextureSampler: ^d3d11.ISamplerState,

    screenRenderTarget: ^d3d11.IRenderTargetView,

    ppGlobalUniformBuffer: ^d3d11.IBuffer,

    blendState: ^d3d11.IBlendState,

    cameraConstBuff: ^d3d11.IBuffer,

    // Debug, @TODO: do something about it
    gpuVertBuffer: ^d3d11.IBuffer,
    inputLayout: ^d3d11.IInputLayout,
}

CreateRenderContextBackend :: proc(nativeWnd: dxgi.HWND) -> ^RenderContext {
    // @TODO: allocation
    ctx := new(RenderContext)

    featureLevels := [?]d3d11.FEATURE_LEVEL{._11_0}

    d3d11.CreateDevice(nil, .HARDWARE, nil, {.BGRA_SUPPORT}, &featureLevels[0], len(featureLevels),
                       d3d11.SDK_VERSION, &ctx.device, nil, &ctx.deviceContext)

    dxgiDevice: ^dxgi.IDevice
    ctx.device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgiDevice))

    dxgiAdapter: ^dxgi.IAdapter
    dxgiDevice->GetAdapter(&dxgiAdapter)

    dxgiFactory: ^dxgi.IFactory2
    dxgiAdapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&dxgiFactory))

    defer dxgiFactory->Release();
    defer dxgiAdapter->Release();
    defer dxgiDevice->Release();

    /////

    swapchainDesc := dxgi.SWAP_CHAIN_DESC1{
        Width  = 0,
        Height = 0,
        Format = .B8G8R8A8_UNORM_SRGB,
        Stereo = false,
        SampleDesc = {
            Count   = 1,
            Quality = 0,
        },
        BufferUsage = {.RENDER_TARGET_OUTPUT},
        BufferCount = 2,
        Scaling     = .STRETCH,
        SwapEffect  = .DISCARD,
        AlphaMode   = .UNSPECIFIED,
        Flags       = nil,
    }

    dxgiFactory->CreateSwapChainForHwnd(ctx.device, nativeWnd, &swapchainDesc, nil, nil, &ctx.swapchain)

    rasterizerDesc := d3d11.RASTERIZER_DESC{
        FillMode = .SOLID,
        CullMode = .NONE,
        // ScissorEnable = true,
        DepthClipEnable = true,
        // MultisampleEnable = true,
        // AntialiasedLineEnable = true,
    }

    ctx.device->CreateRasterizerState(&rasterizerDesc, &ctx.rasterizerState)

    ////

    ResizeFramebuffer(ctx, defaultWindowWidth, defaultWindowHeight)

    /////
    blendDesc: d3d11.BLEND_DESC
    blendDesc.RenderTarget[0] = {
        BlendEnable = true,
        SrcBlend = .SRC_ALPHA,
        DestBlend = .INV_SRC_ALPHA,
        BlendOp = .ADD,
        SrcBlendAlpha = .SRC_ALPHA,
        DestBlendAlpha = .INV_SRC_ALPHA,
        BlendOpAlpha = .ADD,
        RenderTargetWriteMask = 0b1111,
    }

    ctx.device->CreateBlendState(&blendDesc, &ctx.blendState)

    ////

    constBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = size_of(PerFrameData),
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    ctx.device->CreateBuffer(&constBuffDesc, nil, &ctx.cameraConstBuff)

    ////

    ppBuffDesc := d3d11.BUFFER_DESC {
        ByteWidth = size_of(PostProcessGlobalData),
        Usage = .DYNAMIC,
        BindFlags = { .CONSTANT_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    res := ctx.device->CreateBuffer(&ppBuffDesc, nil, &ctx.ppGlobalUniformBuffer)

    return ctx
}

EndFrame :: proc(ctx: ^RenderContext) {
    ctx.swapchain->Present(1, nil)
}

FlushCommands :: proc(ctx: ^RenderContext) {

    viewport := d3d11.VIEWPORT {
        0, 0,
        f32(ctx.frameSize.x), f32(ctx.frameSize.y),
        0, 1,
    }

    // @TODO: make this settable
    ctx.deviceContext->RSSetViewports(1, &viewport)
    ctx.deviceContext->RSSetState(ctx.rasterizerState)

    ctx.deviceContext->OMSetRenderTargets(1, &ctx.ppRenderTargetSrc, nil)
    ctx.deviceContext->OMSetBlendState(ctx.blendState, nil, ~u32(0))

    // Default Camera
    view := GetViewMatrix(ctx.camera)
    proj := GetProjectionMatrixZTO(ctx.camera)

    mapped: d3d11.MAPPED_SUBRESOURCE
    res := ctx.deviceContext->Map(ctx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped);
    c := cast(^PerFrameData) mapped.pData
    c.VPMat = proj * view
    c.invVPMat = glsl.inverse(proj * view)
    c.screenSpace = 0

    ctx.deviceContext->Unmap(ctx.cameraConstBuff, 0)
    ctx.deviceContext->VSSetConstantBuffers(0, 1, &ctx.cameraConstBuff)

    shadersStack: sa.Small_Array(128, ShaderHandle)

    for c in &ctx.commandBuffer.commands {
        switch &cmd in c {
        case ClearColorCommand:
            ctx.deviceContext->ClearRenderTargetView(ctx.ppRenderTargetSrc, transmute(^[4]f32) &cmd.clearColor)

        case CameraCommand:
            view := GetViewMatrix(cmd.camera)
            proj := GetProjectionMatrixZTO(cmd.camera)

            mapped: d3d11.MAPPED_SUBRESOURCE
            res := ctx.deviceContext->Map(ctx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped);
            c := cast(^PerFrameData) mapped.pData
            c.VPMat = proj * view
            c.invVPMat = glsl.inverse(proj * view)
            c.screenSpace = 0

            ctx.deviceContext->Unmap(ctx.cameraConstBuff, 0)
            ctx.deviceContext->VSSetConstantBuffers(0, 1, &ctx.cameraConstBuff)

        case DrawRectCommand:
            if ctx.defaultBatch.count >= ctx.defaultBatch.maxCount {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            shadersLen := sa.len(shadersStack)
            shader :=  shadersLen > 0 ? sa.get(shadersStack, shadersLen - 1) : cmd.shader

            if ctx.defaultBatch.shader.gen != 0 && 
               ctx.defaultBatch.shader != shader {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            if ctx.defaultBatch.texture.gen != 0 && 
               ctx.defaultBatch.texture != cmd.texture {
                DrawBatch(ctx, &ctx.defaultBatch)
            }

            ctx.defaultBatch.shader = shader
            ctx.defaultBatch.texture = cmd.texture

            entry := RectBatchEntry {
                position = cmd.position,
                size = cmd.size,
                rotation = cmd.rotation,

                texPos  = {cmd.texSource.x, cmd.texSource.y},
                texSize = {cmd.texSource.width, cmd.texSource.height},
                pivot = cmd.pivot,
                color = cmd.tint,
            }

            AddBatchEntry(ctx, &ctx.defaultBatch, entry)

        case DrawGridCommand:
            DrawBatch(ctx, &ctx.defaultBatch)

            shaderHandle := ctx.defaultShaders[.Grid]
            shader := GetElement(ctx.shaders, shaderHandle)

            ctx.deviceContext->VSSetShader(shader.backend.vertexShader, nil, 0)
            ctx.deviceContext->PSSetShader(shader.backend.pixelShader, nil, 0)

            ctx.deviceContext->IASetPrimitiveTopology(.TRIANGLESTRIP)

            ctx.deviceContext->Draw(4, 0)

        case DrawMeshCommand:

        case PushShaderCommand: sa.push(&shadersStack, cmd.shader)
        case PopShaderCommand:  sa.pop_back(&shadersStack)

        case BeginScreenSpaceCommand:
            DrawBatch(ctx, &ctx.defaultBatch)

            scale := [3]f32{ 2.0 / f32(ctx.frameSize.x), -2.0 / f32(ctx.frameSize.y), 0}
            mat := glsl.mat4Translate({-1, 1, 0}) * glsl.mat4Scale(scale)

            mapped: d3d11.MAPPED_SUBRESOURCE
            res := ctx.deviceContext->Map(ctx.cameraConstBuff, 0, .WRITE_DISCARD, nil, &mapped);
            c := cast(^PerFrameData) mapped.pData
            c.VPMat = mat
            c.invVPMat = glsl.inverse(mat)
            c.screenSpace = 1

            ctx.deviceContext->Unmap(ctx.cameraConstBuff, 0)
            ctx.deviceContext->VSSetConstantBuffers(0, 1, &ctx.cameraConstBuff)

        case EndScreenSpaceCommand:
            DrawBatch(ctx, &ctx.defaultBatch)
            
        }
    }

    DrawBatch(ctx, &ctx.defaultBatch)
    clear(&ctx.commandBuffer.commands)

    // Post process
    ctx.deviceContext->IASetPrimitiveTopology(.TRIANGLESTRIP)

    // upload global uniform data
    ppMapped: d3d11.MAPPED_SUBRESOURCE
    res = ctx.deviceContext->Map(ctx.ppGlobalUniformBuffer, 0, .WRITE_DISCARD, nil, &ppMapped)

    data := cast(^PostProcessGlobalData) ppMapped.pData
    data.resolution = ctx.frameSize
    data.time = cast(f32) time.gameTime
    ctx.deviceContext->Unmap(ctx.ppGlobalUniformBuffer, 0)

    ctx.deviceContext->PSSetConstantBuffers(0, 1, &ctx.ppGlobalUniformBuffer)

    // Iterate over post process effects using ping-pong framebuffers
    ppIter := MakePoolIter(&ctx.postProcess)
    for pp in PoolIterate(&ppIter) {
        if pp.isActive == false {
            continue
        }

        shader := GetElement(ctx.shaders, pp.shader)
        if shader.pixelShader == nil || shader.vertexShader == nil {
            continue
        }


        ctx.deviceContext->OMSetRenderTargets(1, &ctx.ppRenderTargetDest, nil)

        ctx.deviceContext->VSSetShader(shader.vertexShader, nil, 0)

        ctx.deviceContext->PSSetShader(shader.pixelShader, nil, 0)

        // PP uniform data
        if pp.uniformBuffer != {} {
            buff, ok := GetElementPtr(ctx.buffers, pp.uniformBuffer)
            if pp.isDirty && ok {
                pp.isDirty = false
                BackendUpdateBufferData(buff)
            }

            ctx.deviceContext -> PSSetConstantBuffers(1, 1, &buff.d3dBuffer)
        }

        ctx.deviceContext->PSSetShaderResources(0, 1, &ctx.ppTextureSrc)
        ctx.deviceContext->PSSetSamplers(0, 1, &ctx.ppTextureSampler)

        ctx.deviceContext->Draw(4, 0)

        // swap src and dest for the next pass
        ctx.ppRenderTargetSrc, ctx.ppRenderTargetDest = ctx.ppRenderTargetDest, ctx.ppRenderTargetSrc
        ctx.ppTextureSrc, ctx.ppTextureDest = ctx.ppTextureDest, ctx.ppTextureSrc
    }

    // Final Blit
    ctx.deviceContext->OMSetRenderTargets(1, &ctx.screenRenderTarget, nil)

    shader := GetElement(ctx.shaders, ctx.defaultShaders[.Blit])

    ctx.deviceContext->VSSetShader(shader.vertexShader, nil, 0)
    ctx.deviceContext->PSSetShader(shader.pixelShader, nil, 0);
    ctx.deviceContext->PSSetShaderResources(0, 1, &ctx.ppTextureSrc)
    ctx.deviceContext->PSSetSamplers(0, 1, &ctx.ppTextureSampler)

    ctx.deviceContext->Draw(4, 0)
}

ResizeFramebuffer :: proc(ctx: ^RenderContext, width, height: int) {
    if ctx.screenRenderTarget != nil {
        ctx.screenRenderTarget->Release()

        ctx.ppRenderTargetSrc->Release()
        ctx.ppTextureSrc->Release()

        ctx.ppRenderTargetDest->Release()
        ctx.ppTextureDest->Release()
    }

    if ctx.ppTextureSampler == nil {
        samplerDesc := d3d11.SAMPLER_DESC{
            Filter         = .MIN_MAG_MIP_POINT,
            AddressU       = .CLAMP,
            AddressV       = .CLAMP,
            AddressW       = .CLAMP,
            ComparisonFunc = .NEVER,
        }

        ctx.device->CreateSamplerState(&samplerDesc, &ctx.ppTextureSampler)
    }

    ctx.swapchain->ResizeBuffers(0, cast(u32) width, cast(u32) height, .UNKNOWN, nil)

    ppTextureDesc := d3d11.TEXTURE2D_DESC {
        Width      = cast(u32) width,
        Height     = cast(u32) height,
        MipLevels  = 1,
        ArraySize  = 1,
        Format     = .R32G32B32A32_FLOAT,
        SampleDesc = {Count = 1},
        Usage      = .DEFAULT,
        BindFlags  = {.SHADER_RESOURCE, .RENDER_TARGET},
    }

    ppFramebuffer1: ^d3d11.ITexture2D
    ctx.device->CreateTexture2D(&ppTextureDesc, nil, &ppFramebuffer1)

    ctx.device->CreateRenderTargetView(ppFramebuffer1, nil, &ctx.ppRenderTargetSrc)
    ctx.device->CreateShaderResourceView(ppFramebuffer1, nil, &ctx.ppTextureSrc)

    ppFramebuffer2: ^d3d11.ITexture2D
    ctx.device->CreateTexture2D(&ppTextureDesc, nil, &ppFramebuffer2)

    ctx.device->CreateRenderTargetView(ppFramebuffer2, nil, &ctx.ppRenderTargetDest)
    ctx.device->CreateShaderResourceView(ppFramebuffer2, nil, &ctx.ppTextureDest)


    screenBuffer: ^d3d11.ITexture2D
    ctx.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&screenBuffer))

    ctx.device->CreateRenderTargetView(screenBuffer, nil, &ctx.screenRenderTarget)

    ppFramebuffer1->Release()
    ppFramebuffer2->Release()
    screenBuffer->Release()
}


////////////////////
// Primitive Buffer
///////////////


CreatePrimitiveBatch :: proc(ctx: ^RenderContext, maxCount: int, shaderSource: string) -> (ret: PrimitiveBatch) {
    // ctx.debugBatch.buffer = make([]PrimitiveVertex, maxCount)
    ret.buffer = make([dynamic]PrimitiveVertex, 0, maxCount)
    ret.gpuBufferSize = maxCount;

    // vert buffer
    desc := d3d11.BUFFER_DESC {
        ByteWidth = u32(maxCount) * size_of(PrimitiveVertex),
        Usage     = .DYNAMIC,
        BindFlags = { .VERTEX_BUFFER },
        CPUAccessFlags = { .WRITE },
    }

    res := ctx.device->CreateBuffer(&desc, nil, &ctx.gpuVertBuffer)
    ret.shader = CompileShaderSource(ctx, "Primitive Batch", shaderSource);

    // @HACK: I need to somehow have shader byte code in order to create input layout
    // But my current implementation doesn't store shader bytecode so I need to compile it 
    // again to create the layout.
    // Maybe with precompiled shaders I could get away with
    vsBlob: ^d3d11.IBlob
    defer vsBlob->Release()

    error: ^d3d11.IBlob
    hr := d3d.Compile(raw_data(shaderSource), len(shaderSource), 
                      "shaders.hlsl", nil, nil, 
                      "vs_main", "vs_5_0", 0, 0, &vsBlob, &error)

    if hr < 0 {
        fmt.println(transmute(cstring) error->GetBufferPointer())
        error->Release()

        return
    }


    inputDescs: []d3d11.INPUT_ELEMENT_DESC = {
        {"POSITION", 0, .R32G32B32_FLOAT,    0,                            0, .VERTEX_DATA, 0 },
        {"COLOR",    0, .R32G32B32A32_FLOAT, 0, d3d11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
    }

    res = ctx.device->CreateInputLayout(&inputDescs[0], cast(u32) len(inputDescs), 
                          vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(),
                          &ctx.inputLayout)

    return
}

DrawPrimitiveBatch :: proc(ctx: ^RenderContext, batch: ^PrimitiveBatch) {
    count := len(batch.buffer)

    if count == 0 {
        return
    }

    mapped: d3d11.MAPPED_SUBRESOURCE

    shader := GetElement(ctx.shaders, batch.shader)

    stride: u32 = size_of(PrimitiveVertex)
    offset: u32 = 0

    ctx.deviceContext->IASetPrimitiveTopology(.LINELIST)
    ctx.deviceContext->IASetInputLayout(ctx.inputLayout)
    ctx.deviceContext->IASetVertexBuffers(0, 1, &ctx.gpuVertBuffer, &stride, &offset)

    ctx.deviceContext->VSSetShader(shader.backend.vertexShader, nil, 0)

    ctx.deviceContext->PSSetShader(shader.backend.pixelShader, nil, 0)

    // round up
    iterCount := (count + batch.gpuBufferSize - 1) / batch.gpuBufferSize

    for i in 0..<iterCount {
        drawCount := min(count, batch.gpuBufferSize)

        result := ctx.deviceContext->Map(ctx.gpuVertBuffer, 0, .WRITE_DISCARD, nil, &mapped)
        mem.copy(mapped.pData, &batch.buffer[i * batch.gpuBufferSize], drawCount * size_of(PrimitiveVertex))
        ctx.deviceContext->Unmap(ctx.gpuVertBuffer, 0)

        ctx.deviceContext->Draw(u32(drawCount), 0)

        count = count - batch.gpuBufferSize
    }

    clear(&batch.buffer)
}
#+build windows
package dmcore

import "core:mem"
import "core:fmt"

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3d "vendor:directx/d3d_compiler"

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
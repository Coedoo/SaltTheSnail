#+build js
package dmcore

import gl "vendor:wasm/WebGL"

import "core:mem"
import "core:fmt"

GPUBufferBackend :: struct {
    glBuffer: gl.Buffer,
}

BackendInitGPUBuffer :: proc(buff: ^GPUBuffer) {
    buff.glBuffer = gl.CreateBuffer()

    gl.BindBuffer(gl.UNIFORM_BUFFER, buff.glBuffer)
    gl.BufferData(gl.UNIFORM_BUFFER, buff.dataLen, nil, gl.DYNAMIC_DRAW)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)
}

BackendUpdateBufferData :: proc(buff: ^GPUBuffer) {
    gl.BindBuffer(gl.UNIFORM_BUFFER, buff.glBuffer)
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, buff.dataLen, buff.dataPtr)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)
}
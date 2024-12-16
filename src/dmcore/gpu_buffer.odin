package dmcore

GPUBufferHandle :: distinct Handle

GPUBuffer :: struct {
    handle: GPUBufferHandle,

    dataPtr: rawptr,
    dataLen: int,

    using backend: GPUBufferBackend,
}

// CreateGPUBuffer :: proc($T: typeid, count: int = 1) -> ^GPUBuffer {
//     ret := CreateElement(&renderContext.buffers)

//     ret.byteSize = size_of(T) * count

//     BackendInitGPUBuffer(ret)
//     return ret
// }

CreateGPUBuffer :: proc(dataStruct: any) -> GPUBufferHandle {
    ret := CreateElement(&renderCtx.buffers)

    ret.dataPtr = dataStruct.data
    ret.dataLen = type_info_of(dataStruct.id).size

    BackendInitGPUBuffer(ret)
    return ret.handle
}

UpdateBufferData :: proc(handle: GPUBufferHandle) {
    buff, ok := GetElementPtr(renderCtx.buffers, handle)
    if ok {
        BackendUpdateBufferData(buff)
    }
}
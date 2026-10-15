--!strict

const ByteBuffer = require("@buffer/ByteBuffer")
const Cursor = require("@buffer/Cursor")

export type ByteBuffer = ByteBuffer.ByteBuffer
export type Cursor = Cursor.Cursor

--[=[
	@class Buffer
	@within Burn
	Buffer manipulation utilities comprising resizable `ByteBuffer` buffers and sequential `Cursor` readers.
]=]
return table.freeze({
	ByteBuffer = ByteBuffer,
	Cursor = Cursor,
})

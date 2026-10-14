--!strict

const ByteBuffer = require("@buffer/ByteBuffer")
const Cursor = require("@buffer/Cursor")

export type ByteBuffer = ByteBuffer.ByteBuffer
export type Cursor = Cursor.Cursor

return table.freeze({
	ByteBuffer = ByteBuffer,
	Cursor = Cursor,
})

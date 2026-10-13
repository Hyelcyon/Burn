--!strict

const ByteBuffer = require(script.ByteBuffer)
const Cursor = require(script.Cursor)

export type ByteBuffer = ByteBuffer.ByteBuffer
export type Cursor = Cursor.Cursor

return table.freeze({
	ByteBuffer = ByteBuffer,
	Cursor = Cursor,
})

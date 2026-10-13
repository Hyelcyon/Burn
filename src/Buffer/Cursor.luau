--!strict

const Types = require(script.Parent.Parent.Types)

export type Cursor = {
	raw: buffer,
	offset: number,
}

const Cursor = {}

@native
function Cursor.new(raw: buffer, initialOffset: number?): Cursor
	return {
		raw = raw,
		offset = initialOffset or 0,
	}
end

@native
function Cursor.readU8(self: Cursor): number
	const value = buffer.readu8(self.raw, self.offset)
	self.offset += 1
	return value
end

@native
function Cursor.readU16(self: Cursor): number
	const value = buffer.readu16(self.raw, self.offset)
	self.offset += 2
	return value
end

@native
function Cursor.readU32(self: Cursor): number
	const value = buffer.readu32(self.raw, self.offset)
	self.offset += 4
	return value
end

@native
function Cursor.readI8(self: Cursor): number
	const value = buffer.readi8(self.raw, self.offset)
	self.offset += 1
	return value
end

@native
function Cursor.readI16(self: Cursor): number
	const value = buffer.readi16(self.raw, self.offset)
	self.offset += 2
	return value
end

@native
function Cursor.readI32(self: Cursor): number
	const value = buffer.readi32(self.raw, self.offset)
	self.offset += 4
	return value
end

@native
function Cursor.readF32(self: Cursor): number
	const value = buffer.readf32(self.raw, self.offset)
	self.offset += 4
	return value
end

@native
function Cursor.readF64(self: Cursor): number
	const value = buffer.readf64(self.raw, self.offset)
	self.offset += 8
	return value
end

@native
function Cursor.readString(self: Cursor, count: number): string
	const value = buffer.readstring(self.raw, self.offset, count)
	self.offset += count
	return value
end

@native
function Cursor.skip(self: Cursor, count: number): ()
	self.offset += count
end

@native
function Cursor.skipType<T>(self: Cursor, descriptor: Types.TypeDescriptor<T>): ()
	self.offset = descriptor.skip(self.raw, self.offset)
end

@native
function Cursor.remaining(self: Cursor): number
	return buffer.len(self.raw) - self.offset
end

@native
function Cursor.isEOF(self: Cursor): boolean
	return self.offset >= buffer.len(self.raw)
end

return Cursor

--!strict

const Types = require("@src/Types")

--[=[
	@class Cursor
	Sequential read cursor tracking byte offset into an underlying buffer.
]=]
export type Cursor = {
	raw: buffer,
	offset: number,
	readU8: (self: Cursor) -> number,
	readU16: (self: Cursor) -> number,
	readU32: (self: Cursor) -> number,
	readI8: (self: Cursor) -> number,
	readI16: (self: Cursor) -> number,
	readI32: (self: Cursor) -> number,
	readF32: (self: Cursor) -> number,
	readF64: (self: Cursor) -> number,
	readString: (self: Cursor, count: number) -> string,
	skip: (self: Cursor, count: number) -> (),
	skipType: <T>(self: Cursor, descriptor: Types.TypeDescriptor<T>) -> (),
	readType: <T>(self: Cursor, descriptor: Types.TypeDescriptor<T>) -> T,
	remaining: (self: Cursor) -> number,
	isEOF: (self: Cursor) -> boolean,
}

const Cursor = {}
Cursor.__index = Cursor

--[=[
	Wraps a buffer into a Cursor starting at `initialOffset` (defaults to 0).
]=]
@native
function Cursor.new(raw: buffer, initialOffset: number?): Cursor
	return setmetatable({
		raw = raw,
		offset = initialOffset or 0,
	}, Cursor) :: Cursor
end

@native
function Cursor.readU8(self: Cursor): number
	const bufLen = buffer.len(self.raw)
	if self.offset + 1 > bufLen then
		error(`[Burn] Cursor buffer underflow reading u8 at offset {self.offset} (bufLen {bufLen})`)
	end
	const value = buffer.readu8(self.raw, self.offset)
	self.offset += 1
	return value
end

@native
function Cursor.readU16(self: Cursor): number
	const bufLen = buffer.len(self.raw)
	if self.offset + 2 > bufLen then
		error(`[Burn] Cursor buffer underflow reading u16 at offset {self.offset} (bufLen {bufLen})`)
	end
	const value = buffer.readu16(self.raw, self.offset)
	self.offset += 2
	return value
end

@native
function Cursor.readU32(self: Cursor): number
	const bufLen = buffer.len(self.raw)
	if self.offset + 4 > bufLen then
		error(`[Burn] Cursor buffer underflow reading u32 at offset {self.offset} (bufLen {bufLen})`)
	end
	const value = buffer.readu32(self.raw, self.offset)
	self.offset += 4
	return value
end

@native
function Cursor.readI8(self: Cursor): number
	const bufLen = buffer.len(self.raw)
	if self.offset + 1 > bufLen then
		error(`[Burn] Cursor buffer underflow reading i8 at offset {self.offset} (bufLen {bufLen})`)
	end
	const value = buffer.readi8(self.raw, self.offset)
	self.offset += 1
	return value
end

@native
function Cursor.readI16(self: Cursor): number
	const bufLen = buffer.len(self.raw)
	if self.offset + 2 > bufLen then
		error(`[Burn] Cursor buffer underflow reading i16 at offset {self.offset} (bufLen {bufLen})`)
	end
	const value = buffer.readi16(self.raw, self.offset)
	self.offset += 2
	return value
end

@native
function Cursor.readI32(self: Cursor): number
	const bufLen = buffer.len(self.raw)
	if self.offset + 4 > bufLen then
		error(`[Burn] Cursor buffer underflow reading i32 at offset {self.offset} (bufLen {bufLen})`)
	end
	const value = buffer.readi32(self.raw, self.offset)
	self.offset += 4
	return value
end

@native
function Cursor.readF32(self: Cursor): number
	const bufLen = buffer.len(self.raw)
	if self.offset + 4 > bufLen then
		error(`[Burn] Cursor buffer underflow reading f32 at offset {self.offset} (bufLen {bufLen})`)
	end
	const value = buffer.readf32(self.raw, self.offset)
	self.offset += 4
	return value
end

@native
function Cursor.readF64(self: Cursor): number
	const bufLen = buffer.len(self.raw)
	if self.offset + 8 > bufLen then
		error(`[Burn] Cursor buffer underflow reading f64 at offset {self.offset} (bufLen {bufLen})`)
	end
	const value = buffer.readf64(self.raw, self.offset)
	self.offset += 8
	return value
end

@native
function Cursor.readString(self: Cursor, count: number): string
	const bufLen = buffer.len(self.raw)
	if self.offset + count > bufLen then
		error(
			`[Burn] Cursor buffer underflow reading string of length {count} at offset {self.offset} (bufLen {bufLen})`
		)
	end
	const value = buffer.readstring(self.raw, self.offset, count)
	self.offset += count
	return value
end

--[=[
	Advances the cursor offset by `count` bytes without decoding data.
]=]
@native
function Cursor.skip(self: Cursor, count: number): ()
	const bufLen = buffer.len(self.raw)
	if self.offset + count > bufLen then
		error(`[Burn] Cursor buffer underflow skipping {count} bytes at offset {self.offset} (bufLen {bufLen})`)
	end
	self.offset += count
end

--[=[
	Advances the cursor offset past the encoded representation using the descriptor's `skip` logic.
]=]
@native
function Cursor.skipType<T>(self: Cursor, descriptor: Types.TypeDescriptor<T>): ()
	self.offset = descriptor.skip(self.raw, self.offset)
end

--[=[
	Deserializes a value using the descriptor's `read` logic and advances cursor offset.
]=]
@native
function Cursor.readType<T>(self: Cursor, descriptor: Types.TypeDescriptor<T>): T
	local value: T
	value, self.offset = descriptor.read(self.raw, self.offset)
	return value
end

--[=[
	Returns the number of unread bytes remaining before end of buffer.
]=]
@native
function Cursor.remaining(self: Cursor): number
	return math.max(0, buffer.len(self.raw) - self.offset)
end

--[=[
	Returns whether the cursor offset has reached or exceeded buffer capacity.
]=]
@native
function Cursor.isEOF(self: Cursor): boolean
	return self.offset >= buffer.len(self.raw)
end

return Cursor

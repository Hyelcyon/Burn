--!strict

const Types = require("@src/Types")

--[=[
	@within DataTypes
	Unsigned 24-bit integer TypeDescriptor (range [0, 16,777,215]).
	Encoded in 3 bytes: little-endian u16 low bits + u8 high bits.
]=]
@native
const function write(buf: buffer, offset: number, value: number): number
	buffer.writeu16(buf, offset, bit32.band(value, 0xFFFF))
	buffer.writeu8(buf, offset + 2, bit32.band(bit32.rshift(value, 16), 0xFF))
	return offset + 3
end

@native
const function read(buf: buffer, offset: number): (number, number)
	const bufLen = buffer.len(buf)
	if offset + 3 > bufLen then
		error(`[Burn] Buffer underflow: cannot read u24 at offset {offset} (bufLen {bufLen})`)
	end
	const low = buffer.readu16(buf, offset)
	const high = buffer.readu8(buf, offset + 2)
	return bit32.bor(low, bit32.lshift(high, 16)), offset + 3
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 3
end

const descriptor: Types.TypeDescriptor<number> = table.freeze({
	size = 3,
	write = write,
	read = read,
	skip = skip,
})

return descriptor

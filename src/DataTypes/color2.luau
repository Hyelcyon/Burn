--!strict

const Types = require("@src/Types")

--[=[
	@within DataTypes
	16-bit (2-byte) Color3 TypeDescriptor packed using the RGB565 format.
	Layout: R = 5 bits [15:11], G = 6 bits [10:5], B = 5 bits [4:0].
	Green is allocated 6 bits to match human visual sensitivity.
]=]
@native
const function write(buf: buffer, offset: number, value: Color3): number
	const r = math.clamp(math.round(value.R * 31), 0, 31)
	const g = math.clamp(math.round(value.G * 63), 0, 63)
	const b = math.clamp(math.round(value.B * 31), 0, 31)
	const packed = bit32.bor(bit32.lshift(r, 11), bit32.lshift(g, 5), b)
	buffer.writeu16(buf, offset, packed)
	return offset + 2
end

@native
const function read(buf: buffer, offset: number): (Color3, number)
	const bufLen = buffer.len(buf)
	if offset + 2 > bufLen then
		error(`[Burn] Buffer underflow: cannot read Color2 at offset {offset} (bufLen {bufLen})`)
	end
	const packed = buffer.readu16(buf, offset)
	const r = bit32.rshift(packed, 11) * (1 / 31)
	const g = bit32.band(bit32.rshift(packed, 5), 0x3F) * (1 / 63)
	const b = bit32.band(packed, 0x1F) * (1 / 31)
	return Color3.new(r, g, b), offset + 2
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 2
end

const descriptor: Types.TypeDescriptor<Color3> = table.freeze({
	size = 2,
	write = write,
	read = read,
	skip = skip,
})

return descriptor

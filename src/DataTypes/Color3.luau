--!strict

const Types = require("@src/Types")

--[=[
	@within DataTypes
	3-byte Color3 TypeDescriptor (3x u8 RGB channels in 0..255).
]=]
@native
const function write(buf: buffer, offset: number, value: Color3): number
	buffer.writeu8(buf, offset, math.clamp(math.round(value.R * 255), 0, 255))
	buffer.writeu8(buf, offset + 1, math.clamp(math.round(value.G * 255), 0, 255))
	buffer.writeu8(buf, offset + 2, math.clamp(math.round(value.B * 255), 0, 255))
	return offset + 3
end

@native
const function read(buf: buffer, offset: number): (Color3, number)
	const r = buffer.readu8(buf, offset)
	const g = buffer.readu8(buf, offset + 1)
	const b = buffer.readu8(buf, offset + 2)
	return Color3.fromRGB(r, g, b), offset + 3
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 3
end

const descriptor: Types.TypeDescriptor<Color3> = table.freeze({
	size = 3,
	write = write,
	read = read,
	skip = skip,
})

return descriptor

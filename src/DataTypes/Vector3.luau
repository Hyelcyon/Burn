--!strict

--[=[
	@within DataTypes
	12-byte Vector3 TypeDescriptor (3x f32 components: X, Y, Z).
]=]
@native
const function write(buf: buffer, offset: number, value: Vector3): number
	buffer.writef32(buf, offset, value.X)
	buffer.writef32(buf, offset + 4, value.Y)
	buffer.writef32(buf, offset + 8, value.Z)
	return offset + 12
end

@native
const function read(buf: buffer, offset: number): (Vector3, number)
	const x = buffer.readf32(buf, offset)
	const y = buffer.readf32(buf, offset + 4)
	const z = buffer.readf32(buf, offset + 8)
	return Vector3.new(x, y, z), offset + 12
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 12
end

return table.freeze({
	size = 12,
	write = write,
	read = read,
	skip = skip,
})

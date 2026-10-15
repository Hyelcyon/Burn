--!strict

--[=[
	@within DataTypes
	8-byte Vector2 TypeDescriptor (2x f32 components: X, Y).
]=]
@native
const function write(buf: buffer, offset: number, value: Vector2): number
	buffer.writef32(buf, offset, value.X)
	buffer.writef32(buf, offset + 4, value.Y)
	return offset + 8
end

@native
const function read(buf: buffer, offset: number): (Vector2, number)
	const x = buffer.readf32(buf, offset)
	const y = buffer.readf32(buf, offset + 4)
	return Vector2.new(x, y), offset + 8
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 8
end

return table.freeze({
	size = 8,
	write = write,
	read = read,
	skip = skip,
})

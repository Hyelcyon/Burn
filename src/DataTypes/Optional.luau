--!strict

const Types = require(script.Parent.Parent.Types)

const function Optional<T>(descriptor: Types.TypeDescriptor<T>): Types.TypeDescriptor<T?>
	const innerWrite = descriptor.write
	const innerRead = descriptor.read
	const innerSkip = descriptor.skip

	@native
	const function write(buf: buffer, offset: number, value: T?): number
		if value == nil then
			buffer.writeu8(buf, offset, 0)
			return offset + 1
		else
			buffer.writeu8(buf, offset, 1)
			return innerWrite(buf, offset + 1, value)
		end
	end

	@native
	const function read(buf: buffer, offset: number): (T?, number)
		const hasValue = buffer.readu8(buf, offset) ~= 0
		if hasValue then
			return innerRead(buf, offset + 1)
		else
			return nil, offset + 1
		end
	end

	@native
	const function skip(buf: buffer, offset: number): number
		const hasValue = buffer.readu8(buf, offset) ~= 0
		if hasValue then
			return innerSkip(buf, offset + 1)
		else
			return offset + 1
		end
	end

	return {
		size = nil,
		write = write,
		read = read,
		skip = skip,
	}
end

return Optional

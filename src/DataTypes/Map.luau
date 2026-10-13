--!strict

const Types = require(script.Parent.Parent.Types)

const function Map<K, V>(
	keyDescriptor: Types.TypeDescriptor<K>,
	valueDescriptor: Types.TypeDescriptor<V>
): Types.TypeDescriptor<{ [K]: V }>
	const keyWrite = keyDescriptor.write
	const keyRead = keyDescriptor.read
	const keySkip = keyDescriptor.skip

	const valWrite = valueDescriptor.write
	const valRead = valueDescriptor.read
	const valSkip = valueDescriptor.skip

	@native
	const function write(buf: buffer, offset: number, dict: { [K]: V }): number
		local currentOffset = offset
		local count = 0
		for _ in dict do
			count += 1
		end

		buffer.writeu16(buf, currentOffset, count)
		currentOffset += 2

		for k, v in dict do
			currentOffset = keyWrite(buf, currentOffset, k)
			currentOffset = valWrite(buf, currentOffset, v)
		end

		return currentOffset
	end

	@native
	const function read(buf: buffer, offset: number): ({ [K]: V }, number)
		local currentOffset = offset
		const count = buffer.readu16(buf, currentOffset)
		currentOffset += 2

		const dict: { [K]: V } = {}
		for _ = 1, count do
			local k: K
			k, currentOffset = keyRead(buf, currentOffset)
			local v: V
			v, currentOffset = valRead(buf, currentOffset)
			dict[k] = v
		end

		return dict, currentOffset
	end

	@native
	const function skip(buf: buffer, offset: number): number
		local currentOffset = offset
		const count = buffer.readu16(buf, currentOffset)
		currentOffset += 2

		for _ = 1, count do
			currentOffset = keySkip(buf, currentOffset)
			currentOffset = valSkip(buf, currentOffset)
		end

		return currentOffset
	end

	return {
		size = nil,
		write = write,
		read = read,
		skip = skip,
	}
end

return Map

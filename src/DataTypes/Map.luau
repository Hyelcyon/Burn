--!strict

const Types = require("@src/Types")

export type MapDescriptor<K, V> = Types.TypeDescriptor<{ [K]: V }>

--[=[
	@within DataTypes
	Creates a dictionary TypeDescriptor with a 2-byte (u16) entry count prefix followed by key-value pairs.
]=]
const function Map<K, V>(
	keyDescriptor: Types.TypeDescriptor<K>,
	valueDescriptor: Types.TypeDescriptor<V>
): MapDescriptor<K, V>
	const keyWrite = keyDescriptor.write
	const keyRead = keyDescriptor.read
	const keySkip = keyDescriptor.skip

	const valWrite = valueDescriptor.write
	const valRead = valueDescriptor.read
	const valSkip = valueDescriptor.skip

	@native
	const function write(buf: buffer, offset: number, dict: { [K]: V }): number
		-- Reserve 2 bytes for the entry count, counting entries during traversal to avoid a pre-pass.
		local currentOffset = offset + 2
		local count = 0

		for k, v in dict do
			count += 1
			if count > 65535 then
				error(`[Burn] Map entry count exceeds u16 limit (65535)`)
			end
			currentOffset = keyWrite(buf, currentOffset, k)
			currentOffset = valWrite(buf, currentOffset, v)
		end

		buffer.writeu16(buf, offset, count)
		return currentOffset
	end

	@native
	const function read(buf: buffer, offset: number): ({ [K]: V }, number)
		const bufLen = buffer.len(buf)
		if offset + 2 > bufLen then
			error(`[Burn] Buffer underflow: cannot read map entry count at offset {offset} (bufLen {bufLen})`)
		end
		const count = buffer.readu16(buf, offset)
		local currentOffset = offset + 2

		if keyDescriptor.size ~= nil and valueDescriptor.size ~= nil then
			const fixedEntrySize = keyDescriptor.size + valueDescriptor.size
			if currentOffset + count * fixedEntrySize > bufLen then
				error(`[Burn] Buffer underflow: map of {count} fixed entries exceeds buffer size {bufLen}`)
			end
		end

		const dict: { [K]: V } = {}
		local k: K
		local v: V
		for _ = 1, count do
			k, currentOffset = keyRead(buf, currentOffset)
			v, currentOffset = valRead(buf, currentOffset)
			dict[k] = v
		end

		return dict, currentOffset
	end

	local skip: (buf: buffer, offset: number) -> number
	if keyDescriptor.size ~= nil and valueDescriptor.size ~= nil then
		const fixedEntrySize = keyDescriptor.size + valueDescriptor.size
		-- O(1) skip: When both key and value have known static sizes, skip computes offset directly.
		@native
		local function skipFixed(buf: buffer, offset: number): number
			const bufLen = buffer.len(buf)
			if offset + 2 > bufLen then
				error(`[Burn] Buffer underflow: cannot read map entry count at offset {offset} (bufLen {bufLen})`)
			end
			const count = buffer.readu16(buf, offset)
			const nextOffset = offset + 2 + count * fixedEntrySize
			if nextOffset > bufLen then
				error(`[Burn] Buffer underflow: map of {count} fixed entries exceeds buffer size {bufLen}`)
			end
			return nextOffset
		end
		skip = skipFixed
	else
		@native
		local function skipDynamic(buf: buffer, offset: number): number
			const bufLen = buffer.len(buf)
			if offset + 2 > bufLen then
				error(`[Burn] Buffer underflow: cannot read map entry count at offset {offset} (bufLen {bufLen})`)
			end
			const count = buffer.readu16(buf, offset)
			local currentOffset = offset + 2

			for _ = 1, count do
				currentOffset = keySkip(buf, currentOffset)
				currentOffset = valSkip(buf, currentOffset)
			end

			return currentOffset
		end
		skip = skipDynamic
	end

	return table.freeze({
		size = nil,
		write = write,
		read = read,
		skip = skip,
	})
end

return Map

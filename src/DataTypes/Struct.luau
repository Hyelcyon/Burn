--!strict

const Types = require(script.Parent.Parent.Types)

type FieldEntry = {
	key: string,
	desc: Types.TypeDescriptor<unknown>,
}

const function Struct(fields: { [string]: Types.TypeDescriptor<unknown> })
	const keys: { string } = {}
	for k in fields do
		table.insert(keys, k)
	end
	table.sort(keys)

	const orderedFields: { FieldEntry } = {}
	local totalFixedSize: number? = 0

	for _, k in keys do
		const desc = fields[k]
		table.insert(orderedFields, {
			key = k,
			desc = desc,
		})
		if totalFixedSize ~= nil then
			if desc.size ~= nil then
				totalFixedSize += desc.size
			else
				totalFixedSize = nil
			end
		end
	end

	const fieldCount = #orderedFields

	@native
	const function write(buf: buffer, offset: number, value): number
		local currentOffset = offset
		for index = 1, fieldCount do
			const field = orderedFields[index]
			currentOffset = field.desc.write(buf, currentOffset, value[field.key])
		end
		return currentOffset
	end

	@native
	const function read(buf: buffer, offset: number)
		local currentOffset = offset
		const result = {}
		for index = 1, fieldCount do
			const field = orderedFields[index]
			local item
			item, currentOffset = field.desc.read(buf, currentOffset)
			result[field.key] = item
		end
		return result, currentOffset
	end

	@native
	const function skip(buf: buffer, offset: number): number
		if totalFixedSize ~= nil then
			return offset + totalFixedSize
		end

		local currentOffset = offset
		for index = 1, fieldCount do
			currentOffset = orderedFields[index].desc.skip(buf, currentOffset)
		end
		return currentOffset
	end

	return {
		size = totalFixedSize,
		write = write,
		read = read,
		skip = skip,
	}
end

return Struct

--!strict

const Types = require("@src/Types")

export type EnumDescriptor<E = EnumItem> = Types.TypeDescriptor<E>

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 2
end

--[=[
	@within DataTypes
	Creates an EnumItem TypeDescriptor that serializes the integer `.Value` as a 2-byte (u16) integer,
	resolving back to the EnumItem on read using a pre-indexed value lookup table.
]=]
const function createEnumItemDescriptor(enumType: Enum): Types.TypeDescriptor<EnumItem>
	const itemsByValue: { [number]: EnumItem } = {}
	for _, item in enumType:GetEnumItems() do
		itemsByValue[(item :: EnumItem).Value] = item :: EnumItem
	end

	@native
	const function write(buf: buffer, offset: number, value: EnumItem): number
		buffer.writeu16(buf, offset, value.Value)
		return offset + 2
	end

	@native
	const function read(buf: buffer, offset: number): (EnumItem, number)
		const bufLen = buffer.len(buf)
		if offset + 2 > bufLen then
			error(`[Burn] Buffer underflow: cannot read EnumItem at offset {offset} (bufLen {bufLen})`)
		end
		const val = buffer.readu16(buf, offset)
		const item = itemsByValue[val]
		if item == nil then
			error(`[Burn] Invalid EnumItem value {val} at offset {offset}`)
		end
		return item, offset + 2
	end

	return table.freeze({
		size = 2,
		write = write,
		read = read,
		skip = skip,
	})
end

return createEnumItemDescriptor

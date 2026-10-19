--!strict

const Types = require("@src/Types")

export type EnumType<E> = {
	GetEnumItems: (self: any) -> { E },
}

export type EnumDescriptor<E> = Types.TypeDescriptor<E>

@native
const function write(buf: buffer, offset: number, value: any): number
	buffer.writeu16(buf, offset, value.Value)
	return offset + 2
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 2
end

--[=[
	@within DataTypes
	Creates an EnumItem TypeDescriptor that serializes the integer `.Value` as a 2-byte (u16) integer,
	resolving back to the EnumItem on read using a pre-indexed value lookup table.
]=]
const function createEnumItemDescriptor<E>(enumType: EnumType<E> | Enum): Types.TypeDescriptor<E>
	const itemsByValue: { [number]: E } = {}
	for _, item in (enumType :: any):GetEnumItems() do
		itemsByValue[(item :: any).Value] = item
	end

	@native
	const function read(buf: buffer, offset: number): (E, number)
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
		write = write :: any,
		read = read,
		skip = skip,
	})
end

return createEnumItemDescriptor

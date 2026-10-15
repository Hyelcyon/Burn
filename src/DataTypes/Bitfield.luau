--!strict

const Types = require("@src/Types")

type function InferBitfieldType(T: type)
	if not T:is("table") then
		return types.unknown
	end
	const resultTable = types.newtable()
	for key, prop in T:properties() do
		const valType = prop.read or prop.write
		if valType and valType:is("singleton") and typeof(valType:value()) == "string" then
			resultTable:setproperty(valType, types.boolean)
		elseif key:is("singleton") and typeof(key:value()) == "string" then
			resultTable:setproperty(key, types.boolean)
		end
	end
	return resultTable
end

export type BitfieldDescriptor<F> = Types.TypeDescriptor<InferBitfieldType<F>>

const function Bitfield<F>(flagList: F & { [number]: string }): BitfieldDescriptor<F>
	type T = InferBitfieldType<F>

	const keys: { string } = {}
	for i = 1, #flagList do
		keys[i] = flagList[i]
	end

	const count = #keys
	if count < 1 or count > 32 then
		error(`[Burn] Bitfield requires between 1 and 32 flags, got {count}`)
	end

	const byteSize = if count <= 8 then 1 elseif count <= 16 then 2 elseif count <= 24 then 3 else 4

	local write: (buf: buffer, offset: number, value: T) -> number
	local read: (buf: buffer, offset: number) -> (T, number)

	if count == 1 then
		const k1 = keys[1]
		write = function(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: boolean }
			buffer.writeu8(buf, offset, if val[k1] then 1 else 0)
			return offset + 1
		end
		read = function(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			return ({
				[k1] = bit32.btest(raw, 1),
			} :: { [string]: boolean }) :: T, offset + 1
		end
	elseif count == 2 then
		const k1 = keys[1]
		const k2 = keys[2]
		write = function(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: boolean }
			local mask = 0
			if val[k1] then
				mask = bit32.bor(mask, 1)
			end
			if val[k2] then
				mask = bit32.bor(mask, 2)
			end
			buffer.writeu8(buf, offset, mask)
			return offset + 1
		end
		read = function(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			return ({
				[k1] = bit32.btest(raw, 1),
				[k2] = bit32.btest(raw, 2),
			} :: { [string]: boolean }) :: T,
				offset + 1
		end
	elseif count == 3 then
		const k1 = keys[1]
		const k2 = keys[2]
		const k3 = keys[3]
		write = function(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: boolean }
			local mask = 0
			if val[k1] then
				mask = bit32.bor(mask, 1)
			end
			if val[k2] then
				mask = bit32.bor(mask, 2)
			end
			if val[k3] then
				mask = bit32.bor(mask, 4)
			end
			buffer.writeu8(buf, offset, mask)
			return offset + 1
		end
		read = function(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			return ({
				[k1] = bit32.btest(raw, 1),
				[k2] = bit32.btest(raw, 2),
				[k3] = bit32.btest(raw, 4),
			} :: { [string]: boolean }) :: T,
				offset + 1
		end
	elseif count == 4 then
		const k1 = keys[1]
		const k2 = keys[2]
		const k3 = keys[3]
		const k4 = keys[4]
		write = function(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: boolean }
			local mask = 0
			if val[k1] then
				mask = bit32.bor(mask, 1)
			end
			if val[k2] then
				mask = bit32.bor(mask, 2)
			end
			if val[k3] then
				mask = bit32.bor(mask, 4)
			end
			if val[k4] then
				mask = bit32.bor(mask, 8)
			end
			buffer.writeu8(buf, offset, mask)
			return offset + 1
		end
		read = function(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			return ({
				[k1] = bit32.btest(raw, 1),
				[k2] = bit32.btest(raw, 2),
				[k3] = bit32.btest(raw, 4),
				[k4] = bit32.btest(raw, 8),
			} :: { [string]: boolean }) :: T,
				offset + 1
		end
	elseif count <= 8 then
		write = function(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: boolean }
			local mask = 0
			local bit = 1
			for i = 1, count do
				if val[keys[i]] then
					mask = bit32.bor(mask, bit)
				end
				bit = bit32.lshift(bit, 1)
			end
			buffer.writeu8(buf, offset, mask)
			return offset + 1
		end
		read = function(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			const res: { [string]: boolean } = {}
			local bit = 1
			for i = 1, count do
				res[keys[i]] = bit32.btest(raw, bit)
				bit = bit32.lshift(bit, 1)
			end
			return res :: T, offset + 1
		end
	elseif count <= 16 then
		write = function(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: boolean }
			local mask = 0
			local bit = 1
			for i = 1, count do
				if val[keys[i]] then
					mask = bit32.bor(mask, bit)
				end
				bit = bit32.lshift(bit, 1)
			end
			buffer.writeu16(buf, offset, mask)
			return offset + 2
		end
		read = function(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu16(buf, offset)
			const res: { [string]: boolean } = {}
			local bit = 1
			for i = 1, count do
				res[keys[i]] = bit32.btest(raw, bit)
				bit = bit32.lshift(bit, 1)
			end
			return res :: T, offset + 2
		end
	elseif count <= 24 then
		write = function(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: boolean }
			local mask = 0
			local bit = 1
			for i = 1, count do
				if val[keys[i]] then
					mask = bit32.bor(mask, bit)
				end
				bit = bit32.lshift(bit, 1)
			end
			buffer.writeu16(buf, offset, bit32.band(mask, 0xFFFF))
			buffer.writeu8(buf, offset + 2, bit32.rshift(mask, 16))
			return offset + 3
		end
		read = function(buf: buffer, offset: number): (T, number)
			const low = buffer.readu16(buf, offset)
			const high = buffer.readu8(buf, offset + 2)
			const raw = bit32.bor(low, bit32.lshift(high, 16))
			const res: { [string]: boolean } = {}
			local bit = 1
			for i = 1, count do
				res[keys[i]] = bit32.btest(raw, bit)
				bit = bit32.lshift(bit, 1)
			end
			return res :: T, offset + 3
		end
	else
		write = function(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: boolean }
			local mask = 0
			local bit = 1
			for i = 1, count do
				if val[keys[i]] then
					mask = bit32.bor(mask, bit)
				end
				bit = bit32.lshift(bit, 1)
			end
			buffer.writeu32(buf, offset, mask)
			return offset + 4
		end
		read = function(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu32(buf, offset)
			const res: { [string]: boolean } = {}
			local bit = 1
			for i = 1, count do
				res[keys[i]] = bit32.btest(raw, bit)
				bit = bit32.lshift(bit, 1)
			end
			return res :: T, offset + 4
		end
	end

	@native
	const function skip(_buf: buffer, offset: number): number
		return offset + byteSize
	end

	return table.freeze({
		size = byteSize,
		write = write,
		read = read,
		skip = skip,
	})
end

return Bitfield

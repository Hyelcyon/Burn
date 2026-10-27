--!strict

const Types = require("@src/Types")

export type function InferBitfieldType(T: type)
	if not T:is("table") then
		return types.unknown
	end
	const resultTable = types.newtable()
	local propCount = 0
	for key, prop in T:properties() do
		const valType = prop.read or prop.write
		if valType and valType:is("singleton") and typeof(valType:value()) == "string" then
			resultTable:setproperty(valType, types.boolean)
			propCount += 1
		elseif key:is("singleton") and typeof(key:value()) == "string" then
			resultTable:setproperty(key, types.boolean)
			propCount += 1
		end
	end

	const idx = T:indexer()
	if idx then
		const readType = idx.readresult
		if readType:is("singleton") and typeof(readType:value()) == "string" then
			resultTable:setproperty(readType, types.boolean)
			propCount += 1
		elseif readType:is("union") then
			for _, comp in readType:components() do
				if comp:is("singleton") and typeof(comp:value()) == "string" then
					resultTable:setproperty(comp, types.boolean)
					propCount += 1
				end
			end
		end
	end

	if propCount == 0 then
		resultTable:setindexer(types.string, types.boolean)
	end

	return resultTable
end

export type BitfieldDescriptor<F> = Types.TypeDescriptor<InferBitfieldType<F>>
export type InferBitfield<F> = InferBitfieldType<F>

--[=[
	@within DataTypes
	Creates a Bitfield TypeDescriptor packing between 1 and 32 named boolean flags
	into a 1 to 4 byte compact integer.
]=]
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

	-- Minimum byte width: 1-8 flags -> 1 byte (u8), 9-16 -> 2 bytes (u16),
	-- 17-24 -> 3 bytes (u16+u8), 25-32 -> 4 bytes (u32).
	const byteSize = if count <= 8 then 1 elseif count <= 16 then 2 elseif count <= 24 then 3 else 4

	-- Pre-shaped template for > 4 flags: table.clone(template) leverages the VM's fast allocation path
	-- with pre-allocated hash node capacity matching the flag count to eliminate dynamic table growth.
	const template: { [string]: boolean } = {}
	for i = 1, count do
		template[keys[i]] = false
	end

	local write: (buf: buffer, offset: number, value: T) -> number
	local read: (buf: buffer, offset: number) -> (T, number)

	-- Direct branchless masks for 1-4 flags avoid loop and bit-shift overhead.
	if count == 1 then
		const k1 = keys[1]
		@native
		local function write1(buf: buffer, offset: number, value: T): number
			const val = value :: { read [string]: boolean }
			buffer.writeu8(buf, offset, if val[k1] then 1 else 0)
			return offset + 1
		end
		@native
		local function read1(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			const res: { [string]: boolean } = {
				[k1] = bit32.btest(raw, 1),
			}
			return res :: T, offset + 1
		end
		write = write1
		read = read1
	elseif count == 2 then
		const k1 = keys[1]
		const k2 = keys[2]
		@native
		local function write2(buf: buffer, offset: number, value: T): number
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
		@native
		local function read2(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			const res: { [string]: boolean } = {
				[k1] = bit32.btest(raw, 1),
				[k2] = bit32.btest(raw, 2),
			}
			return res :: T, offset + 1
		end
		write = write2
		read = read2
	elseif count == 3 then
		const k1 = keys[1]
		const k2 = keys[2]
		const k3 = keys[3]
		@native
		local function write3(buf: buffer, offset: number, value: T): number
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
		@native
		local function read3(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			const res: { [string]: boolean } = {
				[k1] = bit32.btest(raw, 1),
				[k2] = bit32.btest(raw, 2),
				[k3] = bit32.btest(raw, 4),
			}
			return res :: T, offset + 1
		end
		write = write3
		read = read3
	elseif count == 4 then
		const k1 = keys[1]
		const k2 = keys[2]
		const k3 = keys[3]
		const k4 = keys[4]
		@native
		local function write4(buf: buffer, offset: number, value: T): number
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
		@native
		local function read4(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			const res: { [string]: boolean } = {
				[k1] = bit32.btest(raw, 1),
				[k2] = bit32.btest(raw, 2),
				[k3] = bit32.btest(raw, 4),
				[k4] = bit32.btest(raw, 8),
			}
			return res :: T, offset + 1
		end
		write = write4
		read = read4
	elseif count <= 8 then
		@native
		local function write8(buf: buffer, offset: number, value: T): number
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
		@native
		local function read8(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu8(buf, offset)
			const res = table.clone(template)
			local bit = 1
			for i = 1, count do
				res[keys[i]] = bit32.btest(raw, bit)
				bit = bit32.lshift(bit, 1)
			end
			return res :: T, offset + 1
		end
		write = write8
		read = read8
	elseif count <= 16 then
		@native
		local function write16(buf: buffer, offset: number, value: T): number
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
		@native
		local function read16(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu16(buf, offset)
			const res = table.clone(template)
			local bit = 1
			for i = 1, count do
				res[keys[i]] = bit32.btest(raw, bit)
				bit = bit32.lshift(bit, 1)
			end
			return res :: T, offset + 2
		end
		write = write16
		read = read16
	elseif count <= 24 then
		@native
		local function write24(buf: buffer, offset: number, value: T): number
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
		@native
		local function read24(buf: buffer, offset: number): (T, number)
			const low = buffer.readu16(buf, offset)
			const high = buffer.readu8(buf, offset + 2)
			const raw = bit32.bor(low, bit32.lshift(high, 16))
			const res = table.clone(template)
			local bit = 1
			for i = 1, count do
				res[keys[i]] = bit32.btest(raw, bit)
				bit = bit32.lshift(bit, 1)
			end
			return res :: T, offset + 3
		end
		write = write24
		read = read24
	else
		@native
		local function write32(buf: buffer, offset: number, value: T): number
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
		@native
		local function read32(buf: buffer, offset: number): (T, number)
			const raw = buffer.readu32(buf, offset)
			const res = table.clone(template)
			local bit = 1
			for i = 1, count do
				res[keys[i]] = bit32.btest(raw, bit)
				bit = bit32.lshift(bit, 1)
			end
			return res :: T, offset + 4
		end
		write = write32
		read = read32
	end

	const rawRead = read
	@native
	const function checkedRead(buf: buffer, offset: number): (T, number)
		const bufLen = buffer.len(buf)
		if offset + byteSize > bufLen then
			error(`[Burn] Buffer underflow: cannot read Bitfield at offset {offset} (bufLen {bufLen})`)
		end
		return rawRead(buf, offset)
	end

	@native
	const function skip(_buf: buffer, offset: number): number
		return offset + byteSize
	end

	return table.freeze({
		size = byteSize,
		write = write,
		read = checkedRead,
		skip = skip,
	})
end

return Bitfield

--!strict

const Types = require("@src/Types")

-- LEB128 unsigned 32-bit integer encoding: 7 payload bits per byte with bit 7 (0x80) as continuation flag.
-- Value thresholds are unrolled into magnitude branches to avoid loop overhead in hot paths.
@native
const function writeVarU32(buf: buffer, offset: number, value: number): number
	const v = if value < 0 then 0 else bit32.band(value, 0xFFFFFFFF)
	if v < 0x80 then
		buffer.writeu8(buf, offset, v)
		return offset + 1
	elseif v < 0x4000 then
		buffer.writeu8(buf, offset, bit32.bor(bit32.band(v, 0x7F), 0x80))
		buffer.writeu8(buf, offset + 1, bit32.rshift(v, 7))
		return offset + 2
	elseif v < 0x200000 then
		buffer.writeu8(buf, offset, bit32.bor(bit32.band(v, 0x7F), 0x80))
		buffer.writeu8(buf, offset + 1, bit32.bor(bit32.band(bit32.rshift(v, 7), 0x7F), 0x80))
		buffer.writeu8(buf, offset + 2, bit32.rshift(v, 14))
		return offset + 3
	elseif v < 0x10000000 then
		buffer.writeu8(buf, offset, bit32.bor(bit32.band(v, 0x7F), 0x80))
		buffer.writeu8(buf, offset + 1, bit32.bor(bit32.band(bit32.rshift(v, 7), 0x7F), 0x80))
		buffer.writeu8(buf, offset + 2, bit32.bor(bit32.band(bit32.rshift(v, 14), 0x7F), 0x80))
		buffer.writeu8(buf, offset + 3, bit32.rshift(v, 21))
		return offset + 4
	else
		buffer.writeu8(buf, offset, bit32.bor(bit32.band(v, 0x7F), 0x80))
		buffer.writeu8(buf, offset + 1, bit32.bor(bit32.band(bit32.rshift(v, 7), 0x7F), 0x80))
		buffer.writeu8(buf, offset + 2, bit32.bor(bit32.band(bit32.rshift(v, 14), 0x7F), 0x80))
		buffer.writeu8(buf, offset + 3, bit32.bor(bit32.band(bit32.rshift(v, 21), 0x7F), 0x80))
		buffer.writeu8(buf, offset + 4, bit32.rshift(v, 28))
		return offset + 5
	end
end

@native
const function readVarU32(buf: buffer, offset: number): (number, number)
	const bufLen = buffer.len(buf)
	if offset >= bufLen then
		error(`[Burn] Buffer underflow: cannot read VarU32 at offset {offset} (bufLen {bufLen})`)
	end
	const b0 = buffer.readu8(buf, offset)
	if bit32.band(b0, 0x80) == 0 then
		return b0, offset + 1
	end
	if offset + 1 >= bufLen then
		error(`[Burn] Buffer underflow: truncated VarU32 at offset {offset} (bufLen {bufLen})`)
	end
	const b1 = buffer.readu8(buf, offset + 1)
	if bit32.band(b1, 0x80) == 0 then
		return bit32.bor(bit32.band(b0, 0x7F), bit32.lshift(b1, 7)), offset + 2
	end
	if offset + 2 >= bufLen then
		error(`[Burn] Buffer underflow: truncated VarU32 at offset {offset} (bufLen {bufLen})`)
	end
	const b2 = buffer.readu8(buf, offset + 2)
	if bit32.band(b2, 0x80) == 0 then
		return bit32.bor(bit32.band(b0, 0x7F), bit32.lshift(bit32.band(b1, 0x7F), 7), bit32.lshift(b2, 14)), offset + 3
	end
	if offset + 3 >= bufLen then
		error(`[Burn] Buffer underflow: truncated VarU32 at offset {offset} (bufLen {bufLen})`)
	end
	const b3 = buffer.readu8(buf, offset + 3)
	if bit32.band(b3, 0x80) == 0 then
		return bit32.bor(
			bit32.band(b0, 0x7F),
			bit32.lshift(bit32.band(b1, 0x7F), 7),
			bit32.lshift(bit32.band(b2, 0x7F), 14),
			bit32.lshift(b3, 21)
		),
			offset + 4
	end
	if offset + 4 >= bufLen then
		error(`[Burn] Buffer underflow: truncated VarU32 at offset {offset} (bufLen {bufLen})`)
	end
	const b4 = buffer.readu8(buf, offset + 4)
	return bit32.bor(
		bit32.band(b0, 0x7F),
		bit32.lshift(bit32.band(b1, 0x7F), 7),
		bit32.lshift(bit32.band(b2, 0x7F), 14),
		bit32.lshift(bit32.band(b3, 0x7F), 21),
		bit32.lshift(bit32.band(b4, 0x0F), 28)
	),
		offset + 5
end

@native
const function skipVarU32(buf: buffer, offset: number): number
	const bufLen = buffer.len(buf)
	local cur = offset
	local bytesRead = 0
	while cur < bufLen and bit32.band(buffer.readu8(buf, cur), 0x80) ~= 0 do
		cur += 1
		bytesRead += 1
		if bytesRead >= 5 then
			error(`[Burn] Corrupted VarInt: continuation exceeds 5 bytes at offset {offset}`)
		end
	end
	if cur >= bufLen then
		error(`[Burn] Buffer underflow: truncated VarInt at offset {offset} (bufLen {bufLen})`)
	end
	return cur + 1
end

-- Zigzag encoding maps signed numbers to positive integers: 0 -> 0, -1 -> 1, 1 -> 2, -2 -> 3.
-- This ensures small negative numbers occupy 1-2 bytes instead of 5 bytes under standard LEB128.
@native
const function writeVarI32(buf: buffer, offset: number, value: number): number
	const n = bit32.band(value, 0xFFFFFFFF)
	const zigzag = bit32.bxor(bit32.lshift(n, 1), bit32.arshift(n, 31))
	return writeVarU32(buf, offset, zigzag)
end

@native
const function readVarI32(buf: buffer, offset: number): (number, number)
	const raw, nextOff = readVarU32(buf, offset)

	-- If LSB is set, the original value was negative.
	const decoded = if bit32.btest(raw, 1) then -(bit32.rshift(raw, 1) + 1) else bit32.rshift(raw, 1)
	return decoded, nextOff
end

const VarU32: Types.TypeDescriptor<number> = table.freeze({
	size = nil,
	write = writeVarU32,
	read = readVarU32,
	skip = skipVarU32,
})

const VarI32: Types.TypeDescriptor<number> = table.freeze({
	size = nil,
	write = writeVarI32,
	read = readVarI32,
	skip = skipVarU32,
})

return table.freeze({
	VarU32 = VarU32,
	VarI32 = VarI32,
	varu32 = VarU32,
	vari32 = VarI32,
})

--!strict

@native
const function write(buf: buffer, offset: number, value: CFrame): number
	const x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

	local qx: number
	local qy: number
	local qz: number
	local qw: number

	const trace = r00 + r11 + r22
	if trace > 0 then
		const s = math.sqrt(trace + 1.0) * 2
		qw = 0.25 * s
		qx = (r21 - r12) / s
		qy = (r02 - r20) / s
		qz = (r10 - r01) / s
	elseif (r00 > r11) and (r00 > r22) then
		const s = math.sqrt(1.0 + r00 - r11 - r22) * 2
		qw = (r21 - r12) / s
		qx = 0.25 * s
		qy = (r01 + r10) / s
		qz = (r02 + r20) / s
	elseif r11 > r22 then
		const s = math.sqrt(1.0 + r11 - r00 - r22) * 2
		qw = (r02 - r20) / s
		qx = (r01 + r10) / s
		qy = 0.25 * s
		qz = (r12 + r21) / s
	else
		const s = math.sqrt(1.0 + r22 - r00 - r11) * 2
		qw = (r10 - r01) / s
		qx = (r02 + r20) / s
		qy = (r12 + r21) / s
		qz = 0.25 * s
	end

	buffer.writef32(buf, offset, x)
	buffer.writef32(buf, offset + 4, y)
	buffer.writef32(buf, offset + 8, z)
	buffer.writef32(buf, offset + 12, qx)
	buffer.writef32(buf, offset + 16, qy)
	buffer.writef32(buf, offset + 20, qz)
	buffer.writef32(buf, offset + 24, qw)

	return offset + 28
end

@native
const function read(buf: buffer, offset: number): (CFrame, number)
	const x = buffer.readf32(buf, offset)
	const y = buffer.readf32(buf, offset + 4)
	const z = buffer.readf32(buf, offset + 8)
	const qx = buffer.readf32(buf, offset + 12)
	const qy = buffer.readf32(buf, offset + 16)
	const qz = buffer.readf32(buf, offset + 20)
	const qw = buffer.readf32(buf, offset + 24)

	return CFrame.new(x, y, z, qx, qy, qz, qw), offset + 28
end

@native
const function skip(_buf: buffer, offset: number): number
	return offset + 28
end

return table.freeze({
	size = 28,
	write = write,
	read = read,
	skip = skip,
})

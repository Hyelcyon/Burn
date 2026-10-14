--!strict

const Constants = require("@src/Constants")

export type ByteBuffer = {
	raw: buffer,
	capacity: number,
	size: number,
}

const ByteBuffer = {}

@native
function ByteBuffer.create(initialCapacity: number?): ByteBuffer
	const capacity = if typeof(initialCapacity) == "number" then initialCapacity else Constants.DEFAULT_BUFFER_CAPACITY
	return {
		raw = buffer.create(capacity),
		capacity = capacity,
		size = 0,
	}
end

@native
function ByteBuffer.ensureCapacity(self: ByteBuffer, required: number)
	if required <= self.capacity then
		return
	end

	local newCapacity = self.capacity * 2
	if newCapacity < required then
		newCapacity = required
	end

	const newRaw = buffer.create(newCapacity)
	if self.size > 0 then
		buffer.copy(newRaw, 0, self.raw, 0, self.size)
	end

	self.raw = newRaw
	self.capacity = newCapacity
end

@native
function ByteBuffer.reset(self: ByteBuffer)
	self.size = 0
end

@native
function ByteBuffer.compact(self: ByteBuffer): buffer
	const exact = buffer.create(self.size)
	if self.size > 0 then
		buffer.copy(exact, 0, self.raw, 0, self.size)
	end
	return exact
end

const scratchBuffer: ByteBuffer = ByteBuffer.create(Constants.MAX_PACKET_SIZE)

@native
function ByteBuffer.getScratch(): ByteBuffer
	scratchBuffer.size = 0
	return scratchBuffer
end

return ByteBuffer

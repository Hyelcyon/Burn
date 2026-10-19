--!strict

const Constants = require("@src/Constants")

--[=[
	@class ByteBuffer
	Dynamic byte buffer tracking allocated capacity, logical write size, and raw memory.
]=]
export type ByteBuffer = {
	raw: buffer,
	capacity: number,
	size: number,
	ensureCapacity: (self: ByteBuffer, required: number) -> (),
	reset: (self: ByteBuffer) -> (),
	compact: (self: ByteBuffer) -> buffer,
}

const ByteBuffer = {}
ByteBuffer.__index = ByteBuffer

--[=[
	Creates a new ByteBuffer with the specified initial capacity.
]=]
@native
function ByteBuffer.create(initialCapacity: number?): ByteBuffer
	const capacity = if typeof(initialCapacity) == "number" then initialCapacity else Constants.DEFAULT_BUFFER_CAPACITY
	return setmetatable({
		raw = buffer.create(capacity),
		capacity = capacity,
		size = 0,
	}, ByteBuffer) :: ByteBuffer
end

--[=[
	Ensures the buffer can hold at least `required` bytes, doubling capacity geometrically
	to amortize reallocation and memory copying costs.
]=]
@native
function ByteBuffer.ensureCapacity(self: ByteBuffer, required: number)
	const currentCapacity = self.capacity
	if required <= currentCapacity then
		return
	end

	local newCapacity = currentCapacity * 2
	if newCapacity < required then
		newCapacity = required
	end

	const newRaw = buffer.create(newCapacity)
	const currentSize = self.size
	if currentSize > 0 then
		buffer.copy(newRaw, 0, self.raw, 0, currentSize)
	end

	self.raw = newRaw
	self.capacity = newCapacity
end

--[=[
	Resets the logical size to 0 without reallocating or releasing the underlying buffer.
]=]
@native
function ByteBuffer.reset(self: ByteBuffer)
	self.size = 0
end

--[=[
	Returns a new buffer containing exactly `self.size` bytes copied from the active data.
]=]
@native
function ByteBuffer.compact(self: ByteBuffer): buffer
	const currentSize = self.size
	const exact = buffer.create(currentSize)
	if currentSize > 0 then
		buffer.copy(exact, 0, self.raw, 0, currentSize)
	end
	return exact
end

-- Shared scratch buffer to eliminate heap allocation during intermediate serialization passes.
const scratchBuffer: ByteBuffer = ByteBuffer.create(Constants.MAX_PACKET_SIZE)

--[=[
	Returns the shared module-level scratch ByteBuffer with size reset to 0.
]=]
@native
function ByteBuffer.getScratch(): ByteBuffer
	scratchBuffer.size = 0
	return scratchBuffer
end

--[=[
	Returns the raw underlying buffer of the shared scratch buffer.
]=]
@native
function ByteBuffer.getScratchRaw(): buffer
	return scratchBuffer.raw
end

return ByteBuffer

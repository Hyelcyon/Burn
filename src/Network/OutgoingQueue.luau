--!strict

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Constants = require("@src/Constants")
const Types = require("@src/Types")
const ByteBuffer = require("@buffer/ByteBuffer")
const Channel = require("@network/Channel")

type PriorityQueues = {
	[number]: ByteBuffer.ByteBuffer,
}

--[=[
	@class OutgoingQueue
	@within Network
	Frame-batched outgoing network queue supporting transmission priorities,
	proactive MTU splitting, and serialization deduplication.
]=]
const OutgoingQueue = {}

const function createPriorityQueues(): PriorityQueues
	return {
		[1] = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY),
		[2] = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY),
		[3] = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY),
		[4] = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY),
	}
end

local clientReliable = createPriorityQueues()
local clientUnreliable = createPriorityQueues()

local playerReliable: { [Player]: PriorityQueues? } = {}
local playerUnreliable: { [Player]: PriorityQueues? } = {}
local broadcastReliable = createPriorityQueues()
local broadcastUnreliable = createPriorityQueues()

local activeReliablePlayers: { Player } = {}
local isReliablePlayerDirty: { [Player]: boolean? } = {}
local activeUnreliablePlayers: { Player } = {}
local isUnreliablePlayerDirty: { [Player]: boolean? } = {}

-- Weak-keyed set to prevent memory leaks while verifying player validity during disconnect.
local removingPlayers = setmetatable({} :: { [Player]: boolean? }, { __mode = "k" })
local isInitialized = false
local isClientChannelReady = false

const function isPlayerActive(player: Player): boolean
	return not removingPlayers[player] and player.Parent == Players
end

-- Concatenates queues in descending priority order (Max [4], High [3], Medium [2], Low [1]).
-- If all data belongs to a single priority, compacts that buffer directly to avoid allocation.
@native
const function flushPriorityQueues(queues: PriorityQueues): buffer?
	const s4 = queues[4].size
	const s3 = queues[3].size
	const s2 = queues[2].size
	const s1 = queues[1].size
	const total = s4 + s3 + s2 + s1
	if total == 0 then
		return nil
	end

	if s4 == total then
		const compacted = ByteBuffer.compact(queues[4])
		ByteBuffer.reset(queues[4])
		return compacted
	elseif s3 == total then
		const compacted = ByteBuffer.compact(queues[3])
		ByteBuffer.reset(queues[3])
		return compacted
	elseif s2 == total then
		const compacted = ByteBuffer.compact(queues[2])
		ByteBuffer.reset(queues[2])
		return compacted
	elseif s1 == total then
		const compacted = ByteBuffer.compact(queues[1])
		ByteBuffer.reset(queues[1])
		return compacted
	end

	const out = buffer.create(total)
	local offset = 0
	if s4 > 0 then
		buffer.copy(out, offset, queues[4].raw, 0, s4)
		offset += s4
		ByteBuffer.reset(queues[4])
	end
	if s3 > 0 then
		buffer.copy(out, offset, queues[3].raw, 0, s3)
		offset += s3
		ByteBuffer.reset(queues[3])
	end
	if s2 > 0 then
		buffer.copy(out, offset, queues[2].raw, 0, s2)
		offset += s2
		ByteBuffer.reset(queues[2])
	end
	if s1 > 0 then
		buffer.copy(out, offset, queues[1].raw, 0, s1)
		offset += s1
		ByteBuffer.reset(queues[1])
	end

	return out
end

@native
const function serializeToScratch<T>(packetDef: Types.PacketDefinition<T>, data: T): (buffer, number)
	if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
		error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
	end

	const scratchRaw = ByteBuffer.getScratchRaw()
	const payloadLen = packetDef.schema.write(scratchRaw, 0, data)
	if payloadLen < 0 or payloadLen > Constants.MAX_PAYLOAD_SIZE then
		error(
			`Packet '{packetDef.name}' payload ({payloadLen} bytes) exceeds limit ({Constants.MAX_PAYLOAD_SIZE} bytes)`
		)
	end
	const schemaSize = packetDef.schema.size
	if typeof(schemaSize) == "number" and payloadLen ~= schemaSize then
		error(`Packet '{packetDef.name}' wrote {payloadLen} bytes, expected fixed size {schemaSize}`)
	end

	return scratchRaw, payloadLen
end

-- Zero-copy fast path: when the schema has a known fixed size, serializes directly
-- into the destination buffer to avoid intermediate scratch copying.
@native
const function writeFixedToBuffer<T>(
	target: ByteBuffer.ByteBuffer,
	packetDef: Types.PacketDefinition<T>,
	schemaSize: number,
	data: T
)
	const packetTotal = Constants.HEADER_SIZE + schemaSize
	const targetOffset = target.size
	const totalNeeded = targetOffset + packetTotal
	ByteBuffer.ensureCapacity(target, totalNeeded)

	buffer.writeu8(target.raw, targetOffset, packetDef.id)
	buffer.writeu16(target.raw, targetOffset + 1, schemaSize)
	const writtenLen = packetDef.schema.write(target.raw, targetOffset + Constants.HEADER_SIZE, data)
	if writtenLen ~= schemaSize then
		error(`Packet '{packetDef.name}' wrote {writtenLen} bytes, expected fixed size {schemaSize}`)
	end

	target.size = totalNeeded
end

@native
const function writeSerializedToBuffer(
	target: ByteBuffer.ByteBuffer,
	packetId: number,
	payloadBuf: buffer,
	payloadLen: number
)
	const packetTotal = Constants.HEADER_SIZE + payloadLen
	const targetOffset = target.size
	const totalNeeded = targetOffset + packetTotal
	ByteBuffer.ensureCapacity(target, totalNeeded)

	buffer.writeu8(target.raw, targetOffset, packetId)
	buffer.writeu16(target.raw, targetOffset + 1, payloadLen)
	if payloadLen > 0 then
		buffer.copy(target.raw, targetOffset + Constants.HEADER_SIZE, payloadBuf, 0, payloadLen)
	end

	target.size = totalNeeded
end

@native
const function buildImmediateBuffer<T>(packetDef: Types.PacketDefinition<T>, data: T): buffer
	if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
		error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
	end

	const schemaSize = packetDef.schema.size
	if typeof(schemaSize) == "number" then
		if schemaSize < 0 or schemaSize > Constants.MAX_PAYLOAD_SIZE then
			error(
				`Packet '{packetDef.name}' payload ({schemaSize} bytes) exceeds limit ({Constants.MAX_PAYLOAD_SIZE} bytes)`
			)
		end
		const packetTotal = Constants.HEADER_SIZE + schemaSize
		if packetDef.packetType == "Unreliable" and packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			error(
				`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
			)
		end

		const out = buffer.create(packetTotal)
		buffer.writeu8(out, 0, packetDef.id)
		buffer.writeu16(out, 1, schemaSize)
		const writtenLen = packetDef.schema.write(out, Constants.HEADER_SIZE, data)
		if writtenLen ~= schemaSize then
			error(`Packet '{packetDef.name}' wrote {writtenLen} bytes, expected fixed size {schemaSize}`)
		end
		return out
	end

	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	const packetTotal = Constants.HEADER_SIZE + payloadLen
	if packetDef.packetType == "Unreliable" and packetTotal > Constants.MAX_UNRELIABLE_BYTES then
		error(
			`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
		)
	end

	const out = buffer.create(packetTotal)
	buffer.writeu8(out, 0, packetDef.id)
	buffer.writeu16(out, 1, payloadLen)
	if payloadLen > 0 then
		buffer.copy(out, Constants.HEADER_SIZE, scratchRaw, 0, payloadLen)
	end
	return out
end

const function getPlayerQueues(dict: { [Player]: PriorityQueues? }, player: Player): PriorityQueues
	const existing = dict[player]
	if existing ~= nil then
		return existing
	end
	const created = createPriorityQueues()
	dict[player] = created
	return created
end

function OutgoingQueue.init()
	if isInitialized then
		return
	end
	isInitialized = true

	if RunService:IsServer() then
		Channel.init()

		Players.PlayerRemoving:Connect(function(player)
			removingPlayers[player] = true
			playerReliable[player] = nil
			playerUnreliable[player] = nil
			isReliablePlayerDirty[player] = nil
			isUnreliablePlayerDirty[player] = nil
		end)

		RunService.Heartbeat:Connect(function()
			const bRel = flushPriorityQueues(broadcastReliable)
			if bRel ~= nil then
				Channel.getReliableEvent():FireAllClients(bRel)
			end

			const bUnrel = flushPriorityQueues(broadcastUnreliable)
			if bUnrel ~= nil then
				Channel.getUnreliableEvent():FireAllClients(bUnrel)
			end

			for _, player in activeReliablePlayers do
				const pQueues = playerReliable[player]
				if not isPlayerActive(player) then
					playerReliable[player] = nil
				elseif pQueues ~= nil then
					const pRel = flushPriorityQueues(pQueues)
					if pRel ~= nil then
						Channel.getReliableEvent():FireClient(player, pRel)
					end
				end
				isReliablePlayerDirty[player] = nil
			end
			table.clear(activeReliablePlayers)

			for _, player in activeUnreliablePlayers do
				const pQueues = playerUnreliable[player]
				if not isPlayerActive(player) then
					playerUnreliable[player] = nil
				elseif pQueues ~= nil then
					const pUnrel = flushPriorityQueues(pQueues)
					if pUnrel ~= nil then
						Channel.getUnreliableEvent():FireClient(player, pUnrel)
					end
				end
				isUnreliablePlayerDirty[player] = nil
			end
			table.clear(activeUnreliablePlayers)
		end)
	else
		task.spawn(function()
			Channel.getReliableEvent()
			Channel.getUnreliableEvent()
			isClientChannelReady = true
		end)

		RunService.Heartbeat:Connect(function()
			if not isClientChannelReady then
				return
			end

			const cRel = flushPriorityQueues(clientReliable)
			if cRel ~= nil then
				Channel.getReliableEvent():FireServer(cRel)
			end

			const cUnrel = flushPriorityQueues(clientUnreliable)
			if cUnrel ~= nil then
				Channel.getUnreliableEvent():FireServer(cUnrel)
			end
		end)
	end
end

function OutgoingQueue.clientEnqueue<T>(packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end

	const priorityIndex = packetDef.priorityIndex
	const schemaSize = packetDef.schema.size
	if typeof(schemaSize) == "number" then
		if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
			error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
		end
		const packetTotal = Constants.HEADER_SIZE + schemaSize
		if packetDef.packetType == "Unreliable" then
			if packetTotal > Constants.MAX_UNRELIABLE_BYTES then
				error(
					`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
				)
			end
			const target = clientUnreliable[priorityIndex]
			if
				isClientChannelReady
				and target.size > 0
				and target.size + packetTotal > Constants.MAX_UNRELIABLE_BYTES
			then
				const flushed = flushPriorityQueues(clientUnreliable)
				if flushed ~= nil then
					Channel.getUnreliableEvent():FireServer(flushed)
				end
			end
			writeFixedToBuffer(target, packetDef, schemaSize, data)
		else
			const target = clientReliable[priorityIndex]
			if isClientChannelReady and target.size > 0 and target.size + packetTotal > Constants.MAX_PACKET_SIZE then
				const flushed = flushPriorityQueues(clientReliable)
				if flushed ~= nil then
					Channel.getReliableEvent():FireServer(flushed)
				end
			end
			writeFixedToBuffer(target, packetDef, schemaSize, data)
		end
		return
	end

	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	const packetTotal = Constants.HEADER_SIZE + payloadLen

	if packetDef.packetType == "Unreliable" then
		if packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			error(
				`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
			)
		end
		const target = clientUnreliable[priorityIndex]
		if isClientChannelReady and target.size > 0 and target.size + packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			const flushed = flushPriorityQueues(clientUnreliable)
			if flushed ~= nil then
				Channel.getUnreliableEvent():FireServer(flushed)
			end
		end
		writeSerializedToBuffer(target, packetDef.id, scratchRaw, payloadLen)
	else
		const target = clientReliable[priorityIndex]
		if isClientChannelReady and target.size > 0 and target.size + packetTotal > Constants.MAX_PACKET_SIZE then
			const flushed = flushPriorityQueues(clientReliable)
			if flushed ~= nil then
				Channel.getReliableEvent():FireServer(flushed)
			end
		end
		writeSerializedToBuffer(target, packetDef.id, scratchRaw, payloadLen)
	end
end

function OutgoingQueue.clientSendImmediate<T>(packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		Channel.getUnreliableEvent():FireServer(buf)
	else
		Channel.getReliableEvent():FireServer(buf)
	end
end

@native
const function enqueuePreSerializedVerified<T>(
	player: Player,
	packetDef: Types.PacketDefinition<T>,
	scratchRaw: buffer,
	payloadLen: number
)
	const packetTotal = Constants.HEADER_SIZE + payloadLen
	const priorityIndex = packetDef.priorityIndex

	if packetDef.packetType == "Unreliable" then
		if packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			error(
				`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
			)
		end
		const pQueues = getPlayerQueues(playerUnreliable, player)
		const buf = pQueues[priorityIndex]
		if buf.size > 0 and buf.size + packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			const flushed = flushPriorityQueues(pQueues)
			if flushed ~= nil then
				Channel.getUnreliableEvent():FireClient(player, flushed)
			end
		end
		writeSerializedToBuffer(buf, packetDef.id, scratchRaw, payloadLen)
		if not isUnreliablePlayerDirty[player] then
			isUnreliablePlayerDirty[player] = true
			table.insert(activeUnreliablePlayers, player)
		end
	else
		const pQueues = getPlayerQueues(playerReliable, player)
		const buf = pQueues[priorityIndex]
		if buf.size > 0 and buf.size + packetTotal > Constants.MAX_PACKET_SIZE then
			const flushed = flushPriorityQueues(pQueues)
			if flushed ~= nil then
				Channel.getReliableEvent():FireClient(player, flushed)
			end
		end
		writeSerializedToBuffer(buf, packetDef.id, scratchRaw, payloadLen)
		if not isReliablePlayerDirty[player] then
			isReliablePlayerDirty[player] = true
			table.insert(activeReliablePlayers, player)
		end
	end
end

function OutgoingQueue.serverEnqueue<T>(player: Player, packetDef: Types.PacketDefinition<T>, data: T)
	if not isPlayerActive(player) then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end

	const priorityIndex = packetDef.priorityIndex
	const schemaSize = packetDef.schema.size
	if typeof(schemaSize) == "number" then
		if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
			error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
		end
		const packetTotal = Constants.HEADER_SIZE + schemaSize
		if packetDef.packetType == "Unreliable" then
			if packetTotal > Constants.MAX_UNRELIABLE_BYTES then
				error(
					`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
				)
			end
			const pQueues = getPlayerQueues(playerUnreliable, player)
			const buf = pQueues[priorityIndex]
			if buf.size > 0 and buf.size + packetTotal > Constants.MAX_UNRELIABLE_BYTES then
				const flushed = flushPriorityQueues(pQueues)
				if flushed ~= nil then
					Channel.getUnreliableEvent():FireClient(player, flushed)
				end
			end
			writeFixedToBuffer(buf, packetDef, schemaSize, data)
			if not isUnreliablePlayerDirty[player] then
				isUnreliablePlayerDirty[player] = true
				table.insert(activeUnreliablePlayers, player)
			end
		else
			const pQueues = getPlayerQueues(playerReliable, player)
			const buf = pQueues[priorityIndex]
			if buf.size > 0 and buf.size + packetTotal > Constants.MAX_PACKET_SIZE then
				const flushed = flushPriorityQueues(pQueues)
				if flushed ~= nil then
					Channel.getReliableEvent():FireClient(player, flushed)
				end
			end
			writeFixedToBuffer(buf, packetDef, schemaSize, data)
			if not isReliablePlayerDirty[player] then
				isReliablePlayerDirty[player] = true
				table.insert(activeReliablePlayers, player)
			end
		end
		return
	end

	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	enqueuePreSerializedVerified(player, packetDef, scratchRaw, payloadLen)
end

-- Serializes once to the scratch buffer, copying the pre-serialized slice into each
-- recipient's queue to eliminate repeated encoding work across multiple players.
function OutgoingQueue.serverEnqueueList<T>(players: { Player }, packetDef: Types.PacketDefinition<T>, data: T)
	if #players == 0 then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end
	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	for _, player in players do
		if isPlayerActive(player) then
			enqueuePreSerializedVerified(player, packetDef, scratchRaw, payloadLen)
		end
	end
end

function OutgoingQueue.serverBroadcast<T>(packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end

	const priorityIndex = packetDef.priorityIndex
	const schemaSize = packetDef.schema.size
	if typeof(schemaSize) == "number" then
		if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
			error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
		end
		const packetTotal = Constants.HEADER_SIZE + schemaSize
		if packetDef.packetType == "Unreliable" then
			if packetTotal > Constants.MAX_UNRELIABLE_BYTES then
				error(
					`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
				)
			end
			const buf = broadcastUnreliable[priorityIndex]
			if buf.size > 0 and buf.size + packetTotal > Constants.MAX_UNRELIABLE_BYTES then
				const flushed = flushPriorityQueues(broadcastUnreliable)
				if flushed ~= nil then
					Channel.getUnreliableEvent():FireAllClients(flushed)
				end
			end
			writeFixedToBuffer(buf, packetDef, schemaSize, data)
		else
			const buf = broadcastReliable[priorityIndex]
			if buf.size > 0 and buf.size + packetTotal > Constants.MAX_PACKET_SIZE then
				const flushed = flushPriorityQueues(broadcastReliable)
				if flushed ~= nil then
					Channel.getReliableEvent():FireAllClients(flushed)
				end
			end
			writeFixedToBuffer(buf, packetDef, schemaSize, data)
		end
		return
	end

	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	const packetTotal = Constants.HEADER_SIZE + payloadLen

	if packetDef.packetType == "Unreliable" then
		if packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			error(
				`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
			)
		end
		const buf = broadcastUnreliable[priorityIndex]
		if buf.size > 0 and buf.size + packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			const flushed = flushPriorityQueues(broadcastUnreliable)
			if flushed ~= nil then
				Channel.getUnreliableEvent():FireAllClients(flushed)
			end
		end
		writeSerializedToBuffer(buf, packetDef.id, scratchRaw, payloadLen)
	else
		const buf = broadcastReliable[priorityIndex]
		if buf.size > 0 and buf.size + packetTotal > Constants.MAX_PACKET_SIZE then
			const flushed = flushPriorityQueues(broadcastReliable)
			if flushed ~= nil then
				Channel.getReliableEvent():FireAllClients(flushed)
			end
		end
		writeSerializedToBuffer(buf, packetDef.id, scratchRaw, payloadLen)
	end
end

function OutgoingQueue.serverBroadcastExcept<T>(excludedPlayer: Player, packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	for _, player in Players:GetPlayers() do
		if player ~= excludedPlayer and not removingPlayers[player] then
			enqueuePreSerializedVerified(player, packetDef, scratchRaw, payloadLen)
		end
	end
end

function OutgoingQueue.serverSendImmediate<T>(player: Player, packetDef: Types.PacketDefinition<T>, data: T)
	if not isPlayerActive(player) then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		Channel.getUnreliableEvent():FireClient(player, buf)
	else
		Channel.getReliableEvent():FireClient(player, buf)
	end
end

function OutgoingQueue.serverSendImmediateList<T>(players: { Player }, packetDef: Types.PacketDefinition<T>, data: T)
	if #players == 0 then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		const event = Channel.getUnreliableEvent()
		for _, player in players do
			if isPlayerActive(player) then
				event:FireClient(player, buf)
			end
		end
	else
		const event = Channel.getReliableEvent()
		for _, player in players do
			if isPlayerActive(player) then
				event:FireClient(player, buf)
			end
		end
	end
end

function OutgoingQueue.serverBroadcastImmediate<T>(packetDef: Types.PacketDefinition<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf = buildImmediateBuffer(packetDef, data)
	if packetDef.packetType == "Unreliable" then
		Channel.getUnreliableEvent():FireAllClients(buf)
	else
		Channel.getReliableEvent():FireAllClients(buf)
	end
end

return OutgoingQueue

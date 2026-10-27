--!strict

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Constants = require("@src/Constants")
const Types = require("@src/Types")
const ByteBuffer = require("@buffer/ByteBuffer")
const Channel = require("@network/Channel")
const InstanceCodec = require("@datatypes/Instance")

type PriorityQueues = {
	totalSize: number,
	instances: { Instance },
	[number]: ByteBuffer.ByteBuffer,
}

--[=[
	@class OutgoingQueue
	@within Network
	Frame-batched outgoing network queue supporting transmission priorities,
	proactive MTU splitting, and side-car Instance replication.
]=]
const OutgoingQueue = {}

const function createPriorityQueues(): PriorityQueues
	return {
		totalSize = 0,
		instances = {},
		[1] = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY),
		[2] = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY),
		[3] = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY),
		[4] = ByteBuffer.create(Constants.DEFAULT_BUFFER_CAPACITY),
	}
end

local clientReliable = createPriorityQueues()
local clientUnreliable = createPriorityQueues()

local playerReliable: { [Player]: PriorityQueues? } =
	setmetatable({} :: { [Player]: PriorityQueues? }, { __mode = "k" })
local playerUnreliable: { [Player]: PriorityQueues? } =
	setmetatable({} :: { [Player]: PriorityQueues? }, { __mode = "k" })
local broadcastReliable = createPriorityQueues()
local broadcastUnreliable = createPriorityQueues()

local activeReliablePlayers: { Player } = {}
local isReliablePlayerDirty: { [Player]: boolean? } = setmetatable({} :: { [Player]: boolean? }, { __mode = "k" })
local activeUnreliablePlayers: { Player } = {}
local isUnreliablePlayerDirty: { [Player]: boolean? } = setmetatable({} :: { [Player]: boolean? }, { __mode = "k" })

-- Weak-keyed set to prevent memory leaks while verifying player validity during disconnect.
local removingPlayers = setmetatable({} :: { [Player]: boolean? }, { __mode = "k" })
local isInitialized = false

const function isPlayerActive(player: Player): boolean
	return not removingPlayers[player] and player.Parent == Players
end

@native
const function fireServerFlush(isUnreliable: boolean, buf: buffer, instances: { Instance }?)
	if isUnreliable then
		const event = Channel.getUnreliableEvent()
		if instances ~= nil then
			event:FireServer(buf, instances)
		else
			event:FireServer(buf)
		end
	else
		const event = Channel.getReliableEvent()
		if instances ~= nil then
			event:FireServer(buf, instances)
		else
			event:FireServer(buf)
		end
	end
end

@native
const function fireClientFlush(player: Player, isUnreliable: boolean, buf: buffer, instances: { Instance }?)
	if isUnreliable then
		const event = Channel.getUnreliableEvent()
		if instances ~= nil then
			event:FireClient(player, buf, instances)
		else
			event:FireClient(player, buf)
		end
	else
		const event = Channel.getReliableEvent()
		if instances ~= nil then
			event:FireClient(player, buf, instances)
		else
			event:FireClient(player, buf)
		end
	end
end

@native
const function fireAllClientsFlush(isUnreliable: boolean, buf: buffer, instances: { Instance }?)
	if isUnreliable then
		const event = Channel.getUnreliableEvent()
		if instances ~= nil then
			event:FireAllClients(buf, instances)
		else
			event:FireAllClients(buf)
		end
	else
		const event = Channel.getReliableEvent()
		if instances ~= nil then
			event:FireAllClients(buf, instances)
		else
			event:FireAllClients(buf)
		end
	end
end

-- Concatenates queues in descending priority order (Max [4], High [3], Medium [2], Low [1]).
-- If all data belongs to a single priority, compacts that buffer directly to avoid allocation.
-- Side-car instances are extracted and reset atomically with the buffer payload.
@native
const function flushPriorityQueues(queues: PriorityQueues): (buffer?, { Instance }?)
	const total = queues.totalSize
	if total == 0 then
		return nil, nil
	end
	queues.totalSize = 0

	local outInstances: { Instance }? = nil
	if #queues.instances > 0 then
		outInstances = queues.instances
		queues.instances = {}
	end

	const s4 = queues[4].size
	const s3 = queues[3].size
	const s2 = queues[2].size
	const s1 = queues[1].size

	if s4 == total then
		const compacted = ByteBuffer.compact(queues[4])
		ByteBuffer.reset(queues[4])
		return compacted, outInstances
	elseif s3 == total then
		const compacted = ByteBuffer.compact(queues[3])
		ByteBuffer.reset(queues[3])
		return compacted, outInstances
	elseif s2 == total then
		const compacted = ByteBuffer.compact(queues[2])
		ByteBuffer.reset(queues[2])
		return compacted, outInstances
	elseif s1 == total then
		const compacted = ByteBuffer.compact(queues[1])
		ByteBuffer.reset(queues[1])
		return compacted, outInstances
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

	return out, outInstances
end

@native
const function serializeToScratch<T>(packetDef: Types.PacketHandle<T>, data: T): (buffer, number)
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
	queues: PriorityQueues,
	priorityIndex: number,
	packetDef: Types.PacketHandle<T>,
	schemaSize: number,
	data: T
)
	const target = queues[priorityIndex]
	const packetTotal = Constants.HEADER_SIZE + schemaSize
	const targetOffset = target.size
	const totalNeeded = targetOffset + packetTotal
	ByteBuffer.ensureCapacity(target, totalNeeded)

	buffer.writeu8(target.raw, targetOffset, packetDef.id)
	buffer.writeu16(target.raw, targetOffset + 1, schemaSize)
	const payloadStart = targetOffset + Constants.HEADER_SIZE
	const nextOffset = packetDef.schema.write(target.raw, payloadStart, data)
	const writtenLen = nextOffset - payloadStart
	if writtenLen ~= schemaSize then
		error(`Packet '{packetDef.name}' wrote {writtenLen} bytes, expected fixed size {schemaSize}`)
	end

	target.size = totalNeeded
	queues.totalSize += packetTotal
end

@native
const function writeSerializedToBuffer(
	queues: PriorityQueues,
	priorityIndex: number,
	packetId: number,
	payloadBuf: buffer,
	payloadLen: number
)
	const target = queues[priorityIndex]
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
	queues.totalSize += packetTotal
end

@native
const function buildImmediateBuffer<T>(packetDef: Types.PacketHandle<T>, data: T): (buffer, { Instance }?)
	if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
		error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
	end

	local instances: { Instance } = {}
	InstanceCodec.setOutgoingInstances(instances)

	local ok: boolean, resBuf: buffer?, resErr: unknown? = true, nil, nil
	const schemaSize = packetDef.schema.size
	if typeof(schemaSize) == "number" then
		const packetTotal = Constants.HEADER_SIZE + schemaSize
		if packetDef.packetType == "Unreliable" and packetTotal > Constants.MAX_UNRELIABLE_BYTES then
			InstanceCodec.setOutgoingInstances(nil)
			error(
				`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
			)
		end

		local out = buffer.create(packetTotal)
		buffer.writeu8(out, 0, packetDef.id)
		buffer.writeu16(out, 1, schemaSize)
		const payloadStart = Constants.HEADER_SIZE
		local nextOffset = 0
		ok, resErr = pcall(function()
			nextOffset = packetDef.schema.write(out, payloadStart, data)
		end)
		if ok then
			const writtenLen = nextOffset - payloadStart
			if writtenLen ~= schemaSize then
				ok = false
				resErr = `Packet '{packetDef.name}' wrote {writtenLen} bytes, expected fixed size {schemaSize}`
			else
				resBuf = out
			end
		end
	else
		local scratchRaw: buffer? = nil
		local payloadLen = 0
		ok, resErr = pcall(function()
			scratchRaw, payloadLen = serializeToScratch(packetDef, data)
		end)
		if ok and scratchRaw ~= nil then
			const packetTotal = Constants.HEADER_SIZE + payloadLen
			if packetDef.packetType == "Unreliable" and packetTotal > Constants.MAX_UNRELIABLE_BYTES then
				ok = false
				resErr =
					`Unreliable packet '{packetDef.name}' ({packetTotal} bytes) exceeds {Constants.MAX_UNRELIABLE_BYTES} bytes`
			else
				local out = buffer.create(packetTotal)
				buffer.writeu8(out, 0, packetDef.id)
				buffer.writeu16(out, 1, payloadLen)
				if payloadLen > 0 then
					buffer.copy(out, Constants.HEADER_SIZE, scratchRaw, 0, payloadLen)
				end
				resBuf = out
			end
		end
	end

	InstanceCodec.setOutgoingInstances(nil)
	if resBuf == nil then
		error(resErr)
	end

	return resBuf, if #instances > 0 then instances else nil
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
			const bRel, bRelInst = flushPriorityQueues(broadcastReliable)
			if bRel ~= nil then
				fireAllClientsFlush(false, bRel, bRelInst)
			end

			const bUnrel, bUnrelInst = flushPriorityQueues(broadcastUnreliable)
			if bUnrel ~= nil then
				fireAllClientsFlush(true, bUnrel, bUnrelInst)
			end

			for _, player in activeReliablePlayers do
				const pQueues = playerReliable[player]
				if not isPlayerActive(player) then
					playerReliable[player] = nil
				elseif pQueues ~= nil then
					const pRel, pRelInst = flushPriorityQueues(pQueues)
					if pRel ~= nil then
						fireClientFlush(player, false, pRel, pRelInst)
					end
				end
			end
			table.clear(isReliablePlayerDirty)
			table.clear(activeReliablePlayers)

			for _, player in activeUnreliablePlayers do
				const pQueues = playerUnreliable[player]
				if not isPlayerActive(player) then
					playerUnreliable[player] = nil
				elseif pQueues ~= nil then
					const pUnrel, pUnrelInst = flushPriorityQueues(pQueues)
					if pUnrel ~= nil then
						fireClientFlush(player, true, pUnrel, pUnrelInst)
					end
				end
			end
			table.clear(isUnreliablePlayerDirty)
			table.clear(activeUnreliablePlayers)
		end)
	else
		Channel.init()

		RunService.Heartbeat:Connect(function()
			if not Channel.isReady() then
				return
			end

			const cRel, cRelInst = flushPriorityQueues(clientReliable)
			if cRel ~= nil then
				fireServerFlush(false, cRel, cRelInst)
			end

			const cUnrel, cUnrelInst = flushPriorityQueues(clientUnreliable)
			if cUnrel ~= nil then
				fireServerFlush(true, cUnrel, cUnrelInst)
			end
		end)
	end
end

@native
function OutgoingQueue.clientEnqueue<T>(packetDef: Types.PacketHandle<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end

	const isUnreliable = packetDef.packetType == "Unreliable"
	const targetQueues = if isUnreliable then clientUnreliable else clientReliable
	const maxLimit = if isUnreliable then Constants.MAX_UNRELIABLE_BYTES else Constants.MAX_PACKET_SIZE
	const priorityIndex = packetDef.priorityIndex
	const schemaSize = packetDef.schema.size

	if typeof(schemaSize) == "number" then
		if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
			error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
		end
		const packetTotal = Constants.HEADER_SIZE + schemaSize
		if packetTotal > maxLimit then
			error(`Packet '{packetDef.name}' ({packetTotal} bytes) exceeds limit ({maxLimit} bytes)`)
		end
		const totalQueued = targetQueues.totalSize
		if Channel.isReady() and totalQueued > 0 and totalQueued + packetTotal > maxLimit then
			const flushed, flushedInst = flushPriorityQueues(targetQueues)
			if flushed ~= nil then
				fireServerFlush(isUnreliable, flushed, flushedInst)
			end
		end

		InstanceCodec.setOutgoingInstances(targetQueues.instances)
		const ok, err = pcall(writeFixedToBuffer, targetQueues, priorityIndex, packetDef, schemaSize, data)
		InstanceCodec.setOutgoingInstances(nil)
		if not ok then
			error(err)
		end
		return
	end

	InstanceCodec.setOutgoingInstances(targetQueues.instances)
	local scratchRaw: buffer? = nil
	local payloadLen = 0
	const ok, err = pcall(function()
		scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	end)
	InstanceCodec.setOutgoingInstances(nil)
	if not ok or scratchRaw == nil then
		error(err)
	end

	const packetTotal = Constants.HEADER_SIZE + payloadLen
	if packetTotal > maxLimit then
		error(`Packet '{packetDef.name}' ({packetTotal} bytes) exceeds limit ({maxLimit} bytes)`)
	end
	const totalQueued = targetQueues.totalSize
	if Channel.isReady() and totalQueued > 0 and totalQueued + packetTotal > maxLimit then
		const flushed, flushedInst = flushPriorityQueues(targetQueues)
		if flushed ~= nil then
			fireServerFlush(isUnreliable, flushed, flushedInst)
		end
	end

	writeSerializedToBuffer(targetQueues, priorityIndex, packetDef.id, scratchRaw, payloadLen)
end

@native
function OutgoingQueue.clientSendImmediate<T>(packetDef: Types.PacketHandle<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf, insts = buildImmediateBuffer(packetDef, data)
	fireServerFlush(packetDef.packetType == "Unreliable", buf, insts)
end

@native
function OutgoingQueue.serverEnqueue<T>(player: Player, packetDef: Types.PacketHandle<T>, data: T)
	if not isPlayerActive(player) then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end

	const isUnreliable = packetDef.packetType == "Unreliable"
	const pQueues = if isUnreliable
		then getPlayerQueues(playerUnreliable, player)
		else getPlayerQueues(playerReliable, player)
	const maxLimit = if isUnreliable then Constants.MAX_UNRELIABLE_BYTES else Constants.MAX_PACKET_SIZE
	const priorityIndex = packetDef.priorityIndex
	const schemaSize = packetDef.schema.size

	if typeof(schemaSize) == "number" then
		if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
			error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
		end
		const packetTotal = Constants.HEADER_SIZE + schemaSize
		if packetTotal > maxLimit then
			error(`Packet '{packetDef.name}' ({packetTotal} bytes) exceeds limit ({maxLimit} bytes)`)
		end
		const totalQueued = pQueues.totalSize
		if totalQueued > 0 and totalQueued + packetTotal > maxLimit then
			const flushed, flushedInst = flushPriorityQueues(pQueues)
			if flushed ~= nil then
				fireClientFlush(player, isUnreliable, flushed, flushedInst)
			end
		end

		InstanceCodec.setOutgoingInstances(pQueues.instances)
		const ok, err = pcall(writeFixedToBuffer, pQueues, priorityIndex, packetDef, schemaSize, data)
		InstanceCodec.setOutgoingInstances(nil)
		if not ok then
			error(err)
		end

		if isUnreliable then
			if not isUnreliablePlayerDirty[player] then
				isUnreliablePlayerDirty[player] = true
				table.insert(activeUnreliablePlayers, player)
			end
		else
			if not isReliablePlayerDirty[player] then
				isReliablePlayerDirty[player] = true
				table.insert(activeReliablePlayers, player)
			end
		end
		return
	end

	InstanceCodec.setOutgoingInstances(pQueues.instances)
	local scratchRaw: buffer? = nil
	local payloadLen = 0
	const ok, err = pcall(function()
		scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	end)
	InstanceCodec.setOutgoingInstances(nil)
	if not ok or scratchRaw == nil then
		error(err)
	end

	const packetTotal = Constants.HEADER_SIZE + payloadLen
	if packetTotal > maxLimit then
		error(`Packet '{packetDef.name}' ({packetTotal} bytes) exceeds limit ({maxLimit} bytes)`)
	end
	const totalQueued = pQueues.totalSize
	if totalQueued > 0 and totalQueued + packetTotal > maxLimit then
		const flushed, flushedInst = flushPriorityQueues(pQueues)
		if flushed ~= nil then
			fireClientFlush(player, isUnreliable, flushed, flushedInst)
		end
	end

	writeSerializedToBuffer(pQueues, priorityIndex, packetDef.id, scratchRaw, payloadLen)
	if isUnreliable then
		if not isUnreliablePlayerDirty[player] then
			isUnreliablePlayerDirty[player] = true
			table.insert(activeUnreliablePlayers, player)
		end
	else
		if not isReliablePlayerDirty[player] then
			isReliablePlayerDirty[player] = true
			table.insert(activeReliablePlayers, player)
		end
	end
end

-- Pre-serializes dynamic payload once into scratch buffer if no Instance side-cars are present,
-- bypassing duplicate serialization passes across multiple recipients.
@native
function OutgoingQueue.serverEnqueueList<T>(players: { Player }, packetDef: Types.PacketHandle<T>, data: T)
	if #players == 0 then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end

	const schemaSize = packetDef.schema.size
	if typeof(schemaSize) == "number" then
		for _, player in players do
			if isPlayerActive(player) then
				OutgoingQueue.serverEnqueue(player, packetDef, data)
			end
		end
		return
	end

	local tempInstances: { Instance } = {}
	InstanceCodec.setOutgoingInstances(tempInstances)
	local scratchRaw: buffer? = nil
	local payloadLen = 0
	const ok, err = pcall(function()
		scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	end)
	InstanceCodec.setOutgoingInstances(nil)
	if not ok or scratchRaw == nil then
		error(err)
	end

	if #tempInstances > 0 then
		for _, player in players do
			if isPlayerActive(player) then
				OutgoingQueue.serverEnqueue(player, packetDef, data)
			end
		end
		return
	end

	const isUnreliable = packetDef.packetType == "Unreliable"
	const maxLimit = if isUnreliable then Constants.MAX_UNRELIABLE_BYTES else Constants.MAX_PACKET_SIZE
	const priorityIndex = packetDef.priorityIndex
	const packetTotal = Constants.HEADER_SIZE + payloadLen
	if packetTotal > maxLimit then
		error(`Packet '{packetDef.name}' ({packetTotal} bytes) exceeds limit ({maxLimit} bytes)`)
	end

	for _, player in players do
		if isPlayerActive(player) then
			const pQueues = if isUnreliable
				then getPlayerQueues(playerUnreliable, player)
				else getPlayerQueues(playerReliable, player)
			const totalQueued = pQueues.totalSize
			if totalQueued > 0 and totalQueued + packetTotal > maxLimit then
				const flushed, flushedInst = flushPriorityQueues(pQueues)
				if flushed ~= nil then
					fireClientFlush(player, isUnreliable, flushed, flushedInst)
				end
			end

			writeSerializedToBuffer(pQueues, priorityIndex, packetDef.id, scratchRaw, payloadLen)
			if isUnreliable then
				if not isUnreliablePlayerDirty[player] then
					isUnreliablePlayerDirty[player] = true
					table.insert(activeUnreliablePlayers, player)
				end
			else
				if not isReliablePlayerDirty[player] then
					isReliablePlayerDirty[player] = true
					table.insert(activeReliablePlayers, player)
				end
			end
		end
	end
end

@native
function OutgoingQueue.serverBroadcast<T>(packetDef: Types.PacketHandle<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end

	const isUnreliable = packetDef.packetType == "Unreliable"
	const targetQueues = if isUnreliable then broadcastUnreliable else broadcastReliable
	const maxLimit = if isUnreliable then Constants.MAX_UNRELIABLE_BYTES else Constants.MAX_PACKET_SIZE
	const priorityIndex = packetDef.priorityIndex
	const schemaSize = packetDef.schema.size

	if typeof(schemaSize) == "number" then
		if packetDef.packetType ~= "Reliable" and packetDef.packetType ~= "Unreliable" then
			error(`Packet '{packetDef.name}' has type '{packetDef.packetType}' and cannot be sent as an event`)
		end
		const packetTotal = Constants.HEADER_SIZE + schemaSize
		if packetTotal > maxLimit then
			error(`Packet '{packetDef.name}' ({packetTotal} bytes) exceeds limit ({maxLimit} bytes)`)
		end
		const totalQueued = targetQueues.totalSize
		if totalQueued > 0 and totalQueued + packetTotal > maxLimit then
			const flushed, flushedInst = flushPriorityQueues(targetQueues)
			if flushed ~= nil then
				fireAllClientsFlush(isUnreliable, flushed, flushedInst)
			end
		end

		InstanceCodec.setOutgoingInstances(targetQueues.instances)
		const ok, err = pcall(writeFixedToBuffer, targetQueues, priorityIndex, packetDef, schemaSize, data)
		InstanceCodec.setOutgoingInstances(nil)
		if not ok then
			error(err)
		end
		return
	end

	InstanceCodec.setOutgoingInstances(targetQueues.instances)
	local scratchRaw: buffer? = nil
	local payloadLen = 0
	const ok, err = pcall(function()
		scratchRaw, payloadLen = serializeToScratch(packetDef, data)
	end)
	InstanceCodec.setOutgoingInstances(nil)
	if not ok or scratchRaw == nil then
		error(err)
	end

	const packetTotal = Constants.HEADER_SIZE + payloadLen
	if packetTotal > maxLimit then
		error(`Packet '{packetDef.name}' ({packetTotal} bytes) exceeds limit ({maxLimit} bytes)`)
	end
	const totalQueued = targetQueues.totalSize
	if totalQueued > 0 and totalQueued + packetTotal > maxLimit then
		const flushed, flushedInst = flushPriorityQueues(targetQueues)
		if flushed ~= nil then
			fireAllClientsFlush(isUnreliable, flushed, flushedInst)
		end
	end

	writeSerializedToBuffer(targetQueues, priorityIndex, packetDef.id, scratchRaw, payloadLen)
end

@native
function OutgoingQueue.serverBroadcastExcept<T>(excludedPlayer: Player, packetDef: Types.PacketHandle<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const allPlayers = Players:GetPlayers()
	if #allPlayers <= 1 then
		if #allPlayers == 1 and allPlayers[1] == excludedPlayer then
			return
		end
	end

	const recipients: { Player } = {}
	for _, player in allPlayers do
		if player ~= excludedPlayer and isPlayerActive(player) then
			table.insert(recipients, player)
		end
	end

	OutgoingQueue.serverEnqueueList(recipients, packetDef, data)
end

@native
function OutgoingQueue.serverSendImmediate<T>(player: Player, packetDef: Types.PacketHandle<T>, data: T)
	if not isPlayerActive(player) then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf, insts = buildImmediateBuffer(packetDef, data)
	fireClientFlush(player, packetDef.packetType == "Unreliable", buf, insts)
end

@native
function OutgoingQueue.serverSendImmediateList<T>(players: { Player }, packetDef: Types.PacketHandle<T>, data: T)
	if #players == 0 then
		return
	end
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf, insts = buildImmediateBuffer(packetDef, data)
	const isUnreliable = packetDef.packetType == "Unreliable"
	for _, player in players do
		if isPlayerActive(player) then
			fireClientFlush(player, isUnreliable, buf, insts)
		end
	end
end

@native
function OutgoingQueue.serverBroadcastImmediate<T>(packetDef: Types.PacketHandle<T>, data: T)
	if not isInitialized then
		OutgoingQueue.init()
	end
	const buf, insts = buildImmediateBuffer(packetDef, data)
	fireAllClientsFlush(packetDef.packetType == "Unreliable", buf, insts)
end

if RunService:IsServer() then
	OutgoingQueue.init()
end

return OutgoingQueue

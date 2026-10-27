--!strict

const RunService = game:GetService("RunService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Constants = require("@src/Constants")

--[=[
	@class Channel
	@within Network
	Manages the lifecycle and replication handshake for network instances in ReplicatedStorage.

	The server creates the communication folder and remotes (`RemoteEvent`, `UnreliableRemoteEvent`,
	`RemoteFunction`). Clients yield via `WaitForChild` until instances replicate from the server.
	Resolved instance references are cached in module-level variables.
]=]
const Channel = {}

local cachedFolder: Folder? = nil
local cachedReliable: RemoteEvent? = nil
local cachedUnreliable: UnreliableRemoteEvent? = nil
local cachedRequest: RemoteFunction? = nil
local isReady = false
local isInitialized = false
local readyListeners: { () -> () }? = {}

function Channel.isReady(): boolean
	return isReady
end

function Channel.onReady(callback: () -> ())
	if isReady then
		task.spawn(callback)
		return
	end
	if readyListeners ~= nil then
		table.insert(readyListeners, callback)
	else
		task.spawn(callback)
	end
end

--[=[
	Resolves and caches the shared network folder in ReplicatedStorage.
]=]
function Channel.getFolder(): Folder
	if cachedFolder ~= nil then
		return cachedFolder
	end

	local folder: Folder
	if RunService:IsServer() then
		const existing = ReplicatedStorage:FindFirstChild(Constants.REMOTE_FOLDER_NAME)
		if existing ~= nil then
			folder = existing :: Folder
		else
			const newFolder = Instance.new("Folder")
			newFolder.Name = Constants.REMOTE_FOLDER_NAME
			newFolder.Parent = ReplicatedStorage
			folder = newFolder
		end
	else
		folder = ReplicatedStorage:WaitForChild(Constants.REMOTE_FOLDER_NAME) :: Folder
	end

	cachedFolder = folder
	return folder
end

function Channel.getReliableEvent(): RemoteEvent
	if cachedReliable ~= nil then
		return cachedReliable
	end

	const folder = Channel.getFolder()
	local event: RemoteEvent
	if RunService:IsServer() then
		const existing = folder:FindFirstChild(Constants.RELIABLE_EVENT_NAME)
		if existing ~= nil then
			event = existing :: RemoteEvent
		else
			const newEvent = Instance.new("RemoteEvent")
			newEvent.Name = Constants.RELIABLE_EVENT_NAME
			newEvent.Parent = folder
			event = newEvent
		end
	else
		event = folder:WaitForChild(Constants.RELIABLE_EVENT_NAME) :: RemoteEvent
	end

	cachedReliable = event
	return event
end

function Channel.getUnreliableEvent(): UnreliableRemoteEvent
	if cachedUnreliable ~= nil then
		return cachedUnreliable
	end

	const folder = Channel.getFolder()
	local event: UnreliableRemoteEvent
	if RunService:IsServer() then
		const existing = folder:FindFirstChild(Constants.UNRELIABLE_EVENT_NAME)
		if existing ~= nil then
			event = existing :: UnreliableRemoteEvent
		else
			const newEvent = Instance.new("UnreliableRemoteEvent")
			newEvent.Name = Constants.UNRELIABLE_EVENT_NAME
			newEvent.Parent = folder
			event = newEvent
		end
	else
		event = folder:WaitForChild(Constants.UNRELIABLE_EVENT_NAME) :: UnreliableRemoteEvent
	end

	cachedUnreliable = event
	return event
end

function Channel.getRequestFunction(): RemoteFunction
	if cachedRequest ~= nil then
		return cachedRequest
	end

	const folder = Channel.getFolder()
	local func: RemoteFunction
	if RunService:IsServer() then
		const existing = folder:FindFirstChild(Constants.REQUEST_FUNCTION_NAME)
		if existing ~= nil then
			func = existing :: RemoteFunction
		else
			const newFunc = Instance.new("RemoteFunction")
			newFunc.Name = Constants.REQUEST_FUNCTION_NAME
			newFunc.Parent = folder
			func = newFunc
		end
	else
		func = folder:WaitForChild(Constants.REQUEST_FUNCTION_NAME) :: RemoteFunction
	end

	cachedRequest = func
	return func
end

function Channel.init()
	if isInitialized then
		return
	end
	isInitialized = true

	if RunService:IsServer() then
		Channel.getFolder()
		Channel.getReliableEvent()
		Channel.getUnreliableEvent()
		Channel.getRequestFunction()
		isReady = true
	else
		task.spawn(function()
			Channel.getFolder()
			Channel.getReliableEvent()
			Channel.getUnreliableEvent()
			Channel.getRequestFunction()
			isReady = true

			const listeners = readyListeners
			readyListeners = nil
			if listeners ~= nil then
				for _, cb in listeners do
					task.spawn(cb)
				end
			end
		end)
	end
end

Channel.init()

return Channel

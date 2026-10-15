--!strict

const Channel = require("@network/Channel")
const OutgoingQueue = require("@network/OutgoingQueue")
const Server = require("@network/Server")
const Client = require("@network/Client")

--[=[
	@class Network
	@within Burn
	Internal networking subsystems including remote channels, outgoing queues, and peer managers.
]=]
return table.freeze({
	Channel = Channel,
	OutgoingQueue = OutgoingQueue,
	Server = Server,
	Client = Client,
})

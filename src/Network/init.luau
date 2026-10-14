--!strict

const Channel = require("@network/Channel")
const OutgoingQueue = require("@network/OutgoingQueue")
const Server = require("@network/Server")
const Client = require("@network/Client")

return table.freeze({
	Channel = Channel,
	OutgoingQueue = OutgoingQueue,
	Server = Server,
	Client = Client,
})

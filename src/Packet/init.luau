--!strict

const Definition = require("@packet/Definition")
const Registry = require("@packet/Registry")

export type PacketType = Definition.PacketType
export type PacketPriority = Definition.PacketPriority
export type PacketDefinition<T> = Definition.PacketDefinition<T>
export type PacketOptions = Registry.PacketOptions

--[=[
	@class Packet
	@within Burn
	Packet definition and central identifier registry subpackage.
]=]
return table.freeze({
	Definition = Definition,
	Registry = Registry,
})

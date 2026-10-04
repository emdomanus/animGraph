--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.Parent.Parent.types.components.stackModifier.shared.stackModifier)

type Release = Types.Release
type SpeedModifierMode = Types.SpeedModifierMode
type SpeedModifierOptions = Types.SpeedModifierOptions
type StackModifierConfig = Types.StackModifierConfig
type StackModifierEntry = Types.StackModifierEntry
type StackModifier = Types.StackModifier
type StackModifierImpl = Types.StackModifierImpl

local DEFAULT_MODE: SpeedModifierMode = "multiply"
local DEFAULT_PRIORITY = 0

local function noop(): ()
	return
end

local function insertEntry(entries: { StackModifierEntry }, entry: StackModifierEntry): ()
	for index = 1, #entries do
		local existing = entries[index]
		if
			entry.priority < existing.priority or (entry.priority == existing.priority and entry.order < existing.order)
		then
			table.insert(entries, index, entry)
			return
		end
	end

	entries[#entries + 1] = entry
end

local StackModifier = {}
StackModifier.__index = StackModifier

function StackModifier.new(config: StackModifierConfig?): StackModifier
	local self: StackModifierImpl = setmetatable({}, StackModifier) :: any

	self._entries = {}
	self._nextToken = 0
	self._nextOrder = 0
	self._onChanged = if config ~= nil then config.onChanged else nil
	self._destroyed = false

	return self
end

function StackModifier.push(self: StackModifierImpl, value: number, options: SpeedModifierOptions?): Release
	if self._destroyed then
		return noop
	end

	local duration = if options ~= nil then options.duration else nil
	if duration ~= nil and duration <= 0 then
		return noop
	end

	local mode: SpeedModifierMode = if options ~= nil and options.mode ~= nil then options.mode else DEFAULT_MODE

	self._nextToken += 1
	self._nextOrder += 1

	local token = self._nextToken
	local entry: StackModifierEntry = {
		token = token,
		order = self._nextOrder,
		value = value,
		mode = mode,
		priority = if options ~= nil and options.priority ~= nil then options.priority else DEFAULT_PRIORITY,
	}
	insertEntry(self._entries, entry)
	self:_emitChanged()

	local released = false
	local release = function()
		if released or self._destroyed then
			return
		end
		released = true

		for index = #self._entries, 1, -1 do
			if self._entries[index].token == token then
				table.remove(self._entries, index)
				self:_emitChanged()
				return
			end
		end
	end

	if duration ~= nil then
		task.delay(duration, release)
	end

	return release
end

function StackModifier._applyEntries(self: StackModifierImpl, baseValue: number): number
	local value = baseValue
	for index = 1, #self._entries do
		local entry = self._entries[index]
		if entry.mode == "set" then
			value = entry.value
		elseif entry.mode == "add" then
			value += entry.value
		else
			value *= entry.value
		end
	end

	return value
end

function StackModifier.evaluate(self: StackModifierImpl, baseValue: number, nextStack: StackModifier?): number
	local value = self:_applyEntries(baseValue)
	if nextStack ~= nil then
		value = (nextStack :: StackModifierImpl):_applyEntries(value)
	end

	return value
end

function StackModifier.clear(self: StackModifierImpl): ()
	if #self._entries == 0 then
		return
	end

	self._entries = {}
	self:_emitChanged()
end

function StackModifier.destroy(self: StackModifierImpl): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._entries = {}
	self._onChanged = nil
end

function StackModifier.isEmpty(self: StackModifierImpl): boolean
	return #self._entries == 0
end

function StackModifier._emitChanged(self: StackModifierImpl): ()
	local onChanged = self._onChanged
	if onChanged ~= nil then
		onChanged()
	end
end

return { new = StackModifier.new }

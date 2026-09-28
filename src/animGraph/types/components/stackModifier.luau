--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)

export type Release = DefTypes.Release

export type SpeedModifierMode = "set" | "add" | "multiply"

export type SpeedModifierOptions = {
	mode: SpeedModifierMode?,
	priority: number?,
	duration: number?,
}

export type StackModifierConfig = {
	onChanged: (() -> ())?,
}

export type StackModifierEntry = {
	token: number,
	order: number,
	value: number,
	mode: SpeedModifierMode,
	priority: number,
}

export type StackModifier = {
	read push: (self: StackModifier, value: number, options: SpeedModifierOptions?) -> Release,
	read evaluate: (self: StackModifier, baseValue: number, nextStack: StackModifier?) -> number,
	read clear: (self: StackModifier) -> (),
	read destroy: (self: StackModifier) -> (),
	read isEmpty: (self: StackModifier) -> boolean,
}

export type StackModifierImpl = StackModifier & {
	_entries: { StackModifierEntry },
	_nextToken: number,
	_nextOrder: number,
	_onChanged: (() -> ())?,
	_destroyed: boolean,

	read _applyEntries: (self: StackModifierImpl, baseValue: number) -> number,
	read _emitChanged: (self: StackModifierImpl) -> (),
}

return {}

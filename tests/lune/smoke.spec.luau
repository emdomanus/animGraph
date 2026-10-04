--!strict
--!optimize 2

local requireAny = require :: any
local process = requireAny("@lune/process")
local ModuleLoader = requireAny(process.cwd .. "/tests/lune/lib/moduleLoader.luau")

local transformed = ModuleLoader.write({
	sourceRoot = "src",
	tempDir = ".tmp/lune-smoke",
})

type StateEnteredEvent = {
	name: "stateEntered",
	layer: string,
	state: string,
	fromState: string?,
	toState: string,
	transition: string,
}

local ok, result = pcall(function(): ()
	local EventBus = transformed.requireModule(
		"animGraph/controller/animationController/shared/animationController/eventBus.luau"
	) :: any
	local eventBus = EventBus.new()
	local observedState = nil
	local release = eventBus:on("stateEntered", function(event)
		observedState = event.state
	end)

	local idleEntered: StateEnteredEvent = {
		name = "stateEntered",
		layer = "base",
		state = "idle",
		fromState = nil,
		toState = "idle",
		transition = "initial",
	}
	eventBus:emit(idleEntered)
	assert(observedState == "idle", "event bus did not dispatch the emitted state")

	release()
	local runEntered: StateEnteredEvent = {
		name = "stateEntered",
		layer = "base",
		state = "run",
		fromState = "idle",
		toState = "run",
		transition = "run",
	}
	eventBus:emit(runEntered)
	assert(observedState == "idle", "released event listener was invoked")
	print("PASS smoke: stateEntered uses the complete discriminated event variant")
end)

transformed.cleanup()
assert(ok, result)

return true

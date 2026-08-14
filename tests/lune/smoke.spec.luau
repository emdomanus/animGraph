--!strict

local requireAny = require :: any
local process = requireAny("@lune/process")
local ModuleLoader = requireAny(process.cwd .. "/tests/lune/lib/moduleLoader.luau")

local transformed = ModuleLoader.write({
	sourceRoot = "src",
	tempDir = ".tmp/lune-smoke",
})

local ok, result = pcall(function(): ()
	local EventBus = transformed.requireModule("animGraph/controller/animationController/eventBus.luau") :: any
	local eventBus = EventBus.new()
	local observedState = nil
	local release = eventBus:on("stateEntered", function(event)
		observedState = event.state
	end)

	eventBus:emit({
		name = "stateEntered",
		layer = "base",
		state = "idle",
	})
	assert(observedState == "idle", "event bus did not dispatch the emitted state")

	release()
	eventBus:emit({
		name = "stateEntered",
		layer = "base",
		state = "run",
	})
	assert(observedState == "idle", "released event listener was invoked")
end)

transformed.cleanup()
assert(ok, result)

return true

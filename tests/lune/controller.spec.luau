--!strict

local requireAny = require :: any
local process = requireAny("@lune/process")
local ModuleLoader = requireAny(process.cwd .. "/tests/lune/lib/moduleLoader.luau")

local transformed = ModuleLoader.write({
	sourceRoot = "src",
	tempDir = ".tmp/lune-controller",
})

local function expectError(callback: () -> (), message: string): ()
	local ok = pcall(callback)
	assert(not ok, message)
end

local function newBackend(): any
	local backend = {
		applyCount = 0,
		batches = {} :: { any },
		sampleTimes = {} :: { number },
		stopCalls = {} :: { any },
		clearCount = 0,
		destroyCount = 0,
		bindCount = 0,
		bindingReleaseCount = 0,
		positionCalls = {} :: { any },
		offsetCalls = {} :: { any },
		completionListeners = {} :: { any },
	}

	function backend:apply(sampleTime, requests): ()
		self.applyCount += 1
		self.sampleTimes[#self.sampleTimes + 1] = sampleTime
		self.batches[#self.batches + 1] = requests
	end

	function backend:stopLayer(layer, fadeTime): ()
		self.stopCalls[#self.stopCalls + 1] = { layer = layer, fadeTime = fadeTime }
	end

	function backend:setTrackPosition(trackKey, position): boolean
		self.positionCalls[#self.positionCalls + 1] = { trackKey = trackKey, position = position }
		return self.positionResult ~= false
	end

	function backend:offsetTrackPosition(trackKey, deltaSeconds): boolean
		self.offsetCalls[#self.offsetCalls + 1] = { trackKey = trackKey, deltaSeconds = deltaSeconds }
		return self.offsetResult ~= false
	end

	function backend:bindToTrackCompleted(callback): () -> ()
		self.bindCount += 1
		self.completionListeners[#self.completionListeners + 1] = callback
		local released = false
		return function()
			if released then
				return
			end
			released = true
			self.bindingReleaseCount += 1
			for index = #self.completionListeners, 1, -1 do
				if self.completionListeners[index] == callback then
					table.remove(self.completionListeners, index)
				end
			end
		end
	end

	function backend:emitTrackCompleted(event): ()
		for _, callback in table.clone(self.completionListeners) do
			callback(event)
		end
	end

	function backend:clear(): ()
		self.clearCount += 1
	end

	function backend:destroy(): ()
		self.destroyCount += 1
	end

	function backend:getCapabilities(): any
		return {
			positionMode = "nativeRate",
			unlimitedPriority = true,
			perJointFallback = "full",
			customMasks = false,
		}
	end

	function backend:getDebugSnapshot(): any
		return {
			name = "FakeBackend",
			capabilities = self:getCapabilities(),
			tracks = {},
			warnings = {},
		}
	end

	return backend
end

local function sample(position: number, addressRevision: number?): any
	return {
		position = position,
		addressRevision = addressRevision or 0,
	}
end

local function makeMotion(trackKey: string, clip: string, speed: number, observations: any?): any
	local state = observations or {
		evaluations = 0,
		logicalPositions = {} :: { number },
	}

	return {
		evaluate = function(_, context)
			state.evaluations += 1
			state.logicalPositions[#state.logicalPositions + 1] = context.logicalPosition
			if state.parameter ~= nil then
				state.parameterValues = state.parameterValues or {}
				state.parameterValues[state.evaluations] = context.getParameter(state.parameter)
			end
			if state.emitAfter ~= nil and state.evaluations < state.emitAfter then
				return {}
			end

			local overrides = context.overrides
			return {
				{
					trackKey = if overrides ~= nil and overrides.trackKey ~= nil then overrides.trackKey else trackKey,
					layer = context.layer,
					state = context.state,
					clip = clip,
					weight = if overrides ~= nil and overrides.weight ~= nil then overrides.weight else 1,
					speed = if overrides ~= nil and overrides.speed ~= nil then overrides.speed else speed,
					initialPosition = if overrides ~= nil then overrides.initialPosition else nil,
					looped = if overrides ~= nil and overrides.looped ~= nil then overrides.looped else false,
					logicalPriority = context.logicalPriority,
					layerBackend = context.layerBackend,
					fadeTime = context.fadeTime,
					forceRestart = if overrides ~= nil and overrides.forceRestart ~= nil
						then overrides.forceRestart
						else false,
				},
			}
		end,
		getDebugSnapshot = function()
			return { kind = "Test", name = trackKey }
		end,
	}
end

local ok, result = pcall(function(): number
	local AnimationController = transformed.requireModule("animGraph/controller/animationController/init.luau") :: any
	local ClipNode = transformed.requireModule("animGraph/motions/clipNode/init.luau") :: any
	local StateMachineRuntime = transformed.requireModule("animGraph/runtime/stateMachineRuntime/init.luau") :: any
	local testCount = 0

	local function test(name: string, callback: () -> ()): ()
		local passed, failure = pcall(callback)
		if not passed then
			error(`controller: {name}: {failure}`, 0)
		end
		testCount += 1
		print(`PASS controller: {name}`)
	end

	test("samples each distinct reader once at the explicit coordinate", function(): ()
		local backend = newBackend()
		local calls = 0
		local observedTimes = {} :: { number }
		local logicalPosition = 5
		local reader = function(sampleTime: number): any
			calls += 1
			observedTimes[#observedTimes + 1] = sampleTime
			return sample(logicalPosition)
		end
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = reader,
			layers = { { id = "base" }, { id = "action" } },
		})
		controller:play("base", makeMotion("base/idle", "idle", 1))
		controller:play("action", makeMotion("action/wave", "wave", 1))

		controller:update(40)
		controller:update(40)
		assert(calls == 2, "shared reader was not sampled once per update")
		assert(observedTimes[1] == 40 and observedTimes[2] == 40, "reader received the wrong coordinate")
		assert(backend.applyCount == 2, "stationary coordinate skipped backend apply")
		assert(backend.sampleTimes[1] == 40 and backend.sampleTimes[2] == 40, "backend received a different coordinate")
	end)

	test("uses active-play then layer then controller reader precedence", function(): ()
		local backend = newBackend()
		local calls = { default = 0, layer = 0, shadow = 0, play = 0 }
		local function reader(name: string, position: number): (number) -> any
			return function(_sampleTime: number): any
				calls[name] += 1
				return sample(position)
			end
		end
		local defaultReader = reader("default", 1)
		local layerReader = reader("layer", 2)
		local shadowReader = reader("shadow", 3)
		local playReader = reader("play", 4)
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = defaultReader,
			layers = {
				{ id = "default" },
				{ id = "layer", logicalTimeReader = layerReader },
				{ id = "play", logicalTimeReader = shadowReader },
			},
		})
		controller:play("default", makeMotion("default", "idle", 1))
		controller:play("layer", makeMotion("layer", "idle", 1))
		controller:play("play", makeMotion("play", "idle", 1), { logicalTimeReader = playReader })
		controller:update(10)

		assert(calls.default == 1 and calls.layer == 1 and calls.play == 1, "selected readers were not sampled")
		assert(calls.shadow == 0, "active-play reader did not shadow the layer reader")
	end)

	test("advances only on forward same-revision reader movement", function(): ()
		local backend = newBackend()
		local current = sample(10, 1)
		local observations = { evaluations = 0, logicalPositions = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				return current
			end,
			layers = { { id = "base", speed = 2 } },
		})
		controller:play("base", makeMotion("base", "idle", 1.5, observations))
		controller:update(0)
		current = sample(12, 1)
		controller:update(1)
		current = sample(12, 1)
		controller:update(2)
		current = sample(5, 1)
		controller:update(3)
		current = sample(6, 1)
		controller:update(4)
		current = sample(100, 2)
		controller:update(5)
		current = sample(102, 2)
		controller:update(6)

		assert(
			table.concat(observations.logicalPositions, ",") == "0,2,2,2,3,3,5",
			"logical phase did not hold/rebase correctly"
		)
		for _, batch in backend.batches do
			assert(batch[1].speed == 3, "logical phase affected signed physical speed")
			assert(batch[1].deltaTime == nil, "legacy deltaTime leaked into a request")
		end
	end)

	test("rejects invalid or backward controller coordinates before mutation", function(): ()
		local backend = newBackend()
		local readerCalls = 0
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				readerCalls += 1
				return sample(0)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base", "idle", 1))
		for _, invalid in { 0 / 0, math.huge, -math.huge } do
			expectError(function()
				controller:update(invalid)
			end, "invalid sampleTime was accepted")
		end
		assert(readerCalls == 0 and backend.applyCount == 0, "invalid coordinate reached reader or backend")

		controller:update(5)
		controller:setFloat("speed", 7)
		expectError(function()
			controller:update(4)
		end, "backward sampleTime was accepted")
		assert(readerCalls == 1 and controller:getFloat("speed", -1) == -1, "rejected update committed graph intent")
		controller:update(6)
		assert(controller:getFloat("speed") == 7, "pending command was lost after rejected update")
	end)

	test("rejects invalid reader batches atomically and preserves queued intent", function(): ()
		local backend = newBackend()
		local base = sample(1)
		local action: any = sample(1)
		local baseObservations = { evaluations = 0, logicalPositions = {} :: { number } }
		local actionObservations = { evaluations = 0, logicalPositions = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				return base
			end,
			layers = {
				{ id = "base" },
				{ id = "action", logicalTimeReader = function(_sampleTime: number): any
					return action
				end },
			},
		})
		controller:play("base", makeMotion("base", "idle", 1, baseObservations))
		controller:play("action", makeMotion("action", "wave", 1, actionObservations))
		controller:setBool("armed", true)
		action = { position = math.huge, addressRevision = 0 }
		expectError(function()
			controller:update(1)
		end, "invalid reader sample was accepted")
		action = { position = 2, addressRevision = 0 / 0 }
		expectError(function()
			controller:update(1)
		end, "invalid reader revision was accepted")
		assert(backend.applyCount == 0, "invalid reader batch reached backend")
		assert(controller:getParameter("armed") == nil, "invalid reader batch committed parameters")
		assert(not controller:getDebugSnapshot().layers[1].isPlaying, "invalid reader batch committed play")

		action = sample(2)
		controller:update(1)
		assert(controller:getBool("armed"), "queued commands did not survive invalid reader batch")
		assert(baseObservations.logicalPositions[1] == 0 and actionObservations.logicalPositions[1] == 0, "first phase was not zero")
	end)

	test("stages controller-default reader replacement and rebases phase", function(): ()
		local backend = newBackend()
		local firstPosition = 0
		local secondPosition = 100
		local firstReader = function(_sampleTime: number): any
			return sample(firstPosition)
		end
		local secondReader = function(_sampleTime: number): any
			return sample(secondPosition)
		end
		local observations = { evaluations = 0, logicalPositions = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = firstReader,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base", "idle", 1, observations))
		controller:update(0)
		firstPosition = 2
		controller:update(1)
		controller:setDefaultLogicalTimeReader(secondReader)
		controller:update(1)
		secondPosition = 103
		controller:update(2)
		assert(table.concat(observations.logicalPositions, ",") == "0,2,2,5", "default reader did not rebase")
	end)

	test("stages graph intent and re-evaluates at the same coordinate", function(): ()
		local backend = newBackend()
		local observations = {
			evaluations = 0,
			logicalPositions = {} :: { number },
			parameter = "blend",
			parameterValues = {} :: { any },
		}
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				return sample(0)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base", "idle", 2, observations))
		controller:setFloat("blend", 0.25)
		controller:setLayerWeight("base", 0.5)
		controller:setLayerSpeed("base", -2)
		assert(controller:getParameter("blend") == nil, "parameter committed before update")
		assert(controller:getLayerWeight("base") == 1, "layer weight committed before update")

		controller:update(10)
		assert(observations.parameterValues[1] == 0.25, "parameter was not visible to the next evaluation")
		assert(backend.batches[1][1].weight == 0.5, "staged weight was not applied")
		assert(backend.batches[1][1].speed == -4, "staged signed speed was not applied")

		controller:setFloat("blend", 0.75)
		controller:update(10)
		assert(observations.logicalPositions[2] == 0, "same-coordinate evaluation advanced logical phase")
		assert(observations.parameterValues[2] == 0.75, "same-coordinate evaluation did not see new intent")
	end)

	test("defers commands issued by a reader until the following update", function(): ()
		local backend = newBackend()
		local controller: any = nil
		local queued = false
		local observations = {
			evaluations = 0,
			logicalPositions = {} :: { number },
			parameter = "fromReader",
			parameterValues = {} :: { any },
		}
		controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				if not queued then
					queued = true
					controller:setBool("fromReader", true)
				end
				return sample(0)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base", "idle", 1, observations))
		controller:update(0)
		controller:update(0)
		assert(observations.parameterValues[1] == nil, "reader-issued command affected the in-flight update")
		assert(observations.parameterValues[2] == true, "reader-issued command was not retained for the next update")
	end)

	test("reader changes hold phase and take effect transactionally", function(): ()
		local backend = newBackend()
		local defaultPosition = 0
		local layerPosition = 100
		local playPosition = 200
		local defaultReader = function(_sampleTime: number): any
			return sample(defaultPosition)
		end
		local layerReader = function(_sampleTime: number): any
			return sample(layerPosition)
		end
		local playReader = function(_sampleTime: number): any
			return sample(playPosition)
		end
		local observations = { evaluations = 0, logicalPositions = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = defaultReader,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base", "idle", 1, observations))
		controller:update(0)
		defaultPosition = 2
		controller:update(1)
		controller:setLayerLogicalTimeReader("base", layerReader)
		controller:update(1)
		layerPosition = 103
		controller:update(2)
		controller:setActivePlayLogicalTimeReader("base", playReader)
		controller:update(2)
		playPosition = 204
		controller:update(3)
		controller:setActivePlayLogicalTimeReader("base", nil)
		controller:update(3)
		layerPosition = 105
		controller:update(4)

		assert(
			table.concat(observations.logicalPositions, ",") == "0,2,2,5,5,9,9,11",
			"reader changes did not hold/rebase phase"
		)
	end)

	test("transition progress derives from logical position anchors", function(): ()
		local backend = newBackend()
		local logicalPosition = 20
		local machine = StateMachineRuntime.new({
			initialState = "idle",
			states = {
				{ id = "idle", motion = ClipNode.new("idle") },
				{ id = "run", motion = ClipNode.new("run") },
			},
			transitions = { { from = "idle", to = "run", duration = 2 } },
		})
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				return sample(logicalPosition)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", machine)
		controller:update(0)
		assert(machine:getDebugSnapshot().details.transition.progress == 0, "transition did not start at its phase anchor")
		logicalPosition = 21
		controller:update(1)
		assert(machine:getDebugSnapshot().details.transition.progress == 0.5, "transition did not sample absolute phase")
		controller:setFloat("irrelevant", 1)
		controller:update(1)
		assert(machine:getDebugSnapshot().details.transition.progress == 0.5, "same-coordinate command advanced transition")
	end)

	test("keeps physical positioning synchronous and phase-neutral", function(): ()
		local backend = newBackend()
		local logicalPosition = 4
		local observations = { evaluations = 0, logicalPositions = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				return sample(logicalPosition)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base/idle", "idle", 1, observations))
		controller:update(0)
		assert(controller:setTrackPosition("base/idle", { kind = "seconds", value = 3 }), "position was rejected")
		assert(controller:offsetTrackPosition("base/idle", -1.25), "offset was rejected")
		assert(#backend.positionCalls == 1 and #backend.offsetCalls == 1, "physical command was staged")
		logicalPosition = 6
		controller:update(1)
		assert(observations.logicalPositions[2] == 2, "physical positioning rewrote logical phase")
	end)

	test("validates assembled requests before backend apply", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				return sample(0)
			end,
			layers = { { id = "base" }, { id = "action" } },
		})
		controller:play("base", makeMotion("duplicate", "idle", 1))
		controller:play("action", makeMotion("duplicate", "wave", 1))
		expectError(function()
			controller:update(0)
		end, "duplicate track keys were accepted")
		assert(backend.applyCount == 0, "invalid request batch reached backend")
	end)

	test("consumes one-shot play positioning only after emission", function(): ()
		local backend = newBackend()
		local observations = { evaluations = 0, logicalPositions = {} :: { number }, emitAfter = 2 }
		local logicalPosition = 0
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				return sample(logicalPosition)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("delayed", "idle", 1, observations), {
			initialPosition = { kind = "normalized", value = 0.5 },
			forceRestart = true,
		})
		controller:update(0)
		logicalPosition = 1
		controller:update(1)
		logicalPosition = 2
		controller:update(2)
		assert(backend.batches[2][1].initialPosition.value == 0.5, "initial position was consumed too early")
		assert(backend.batches[3][1].initialPosition == nil, "initial position was emitted twice")
	end)

	test("stages stopLayer with its resolved fade", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				return sample(0)
			end,
			layers = { { id = "base", defaultFadeOut = 0.75 } },
		})
		controller:play("base", makeMotion("base", "idle", 1))
		controller:update(0)
		controller:stopLayer("base")
		assert(#backend.stopCalls == 0, "stop reached backend before update")
		controller:update(1)
		assert(#backend.stopCalls == 1 and backend.stopCalls[1].fadeTime == 0.75, "staged stop used wrong fade")
		assert(#backend.batches[2] == 0, "stopped layer emitted requests")
	end)

	test("forwards backend completion and releases ownership", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			logicalTimeReader = function(_sampleTime: number): any
				return sample(0)
			end,
		})
		local events = {} :: { any }
		controller:on("trackCompleted", function(event)
			events[#events + 1] = event
		end)
		backend:emitTrackCompleted({ name = "trackCompleted", trackKey = "base", layer = "base", state = "idle" })
		assert(#events == 1 and backend.bindCount == 1, "completion was not forwarded")
		controller:destroy()
		backend:emitTrackCompleted({ name = "trackCompleted", trackKey = "stale", layer = "base", state = "idle" })
		assert(#events == 1 and backend.bindingReleaseCount == 1, "destroy leaked completion binding")
		assert(backend.clearCount == 1 and backend.destroyCount == 1, "destroy ownership was incorrect")
	end)

	test("validates clip positions at command construction", function(): ()
		ClipNode.new("validSeconds", { initialPosition = { kind = "seconds", value = 0 } })
		ClipNode.new("validNormalized", { initialPosition = { kind = "normalized", value = 1 } })
		expectError(function()
			ClipNode.new("invalid", { initialPosition = { kind = "frames", value = 1 } })
		end, "invalid ClipNode position was accepted")
	end)

	return testCount
end)

transformed.cleanup()
assert(ok, result)

return result

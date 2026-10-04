--!strict
--!optimize 2

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

local function sample(position: number, rate: number?): any
	return {
		position = position,
		rate = if rate ~= nil then rate else 1,
	}
end

local function makeMotion(trackKey: string, clip: string, speed: number, observations: any?): any
	local state = observations
		or {
			evaluations = 0,
			timePositions = {} :: { number },
			timeRates = {} :: { number },
		}

	return {
		evaluate = function(_, context)
			state.evaluations += 1
			state.timePositions = state.timePositions or {}
			state.timeRates = state.timeRates or {}
			state.timePositions[#state.timePositions + 1] = context.timePosition
			state.timeRates[#state.timeRates + 1] = context.timeRate
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
					timePosition = context.timePosition,
					timeRate = context.timeRate,
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
	local AnimationController = transformed.requireModule(
		"animGraph/controller/animationController/shared/animationController/init.luau"
	) :: any
	local ClipNode = transformed.requireModule("animGraph/motions/clipNode/shared/clipNode.luau") :: any
	local StateMachineRuntime =
		transformed.requireModule("animGraph/runtime/stateMachineRuntime/shared/stateMachineRuntime.luau") :: any
	local testCount = 0

	local function test(name: string, callback: () -> ()): ()
		local passed, failure = pcall(callback)
		if not passed then
			error(`controller: {name}: {failure}`, 0)
		end
		testCount += 1
		print(`PASS controller: {name}`)
	end

	test("parameter defaults are available to the first evaluation and owned per controller", function(): ()
		local defaults = { speed = 2, grounded = true, stance = "standing", attack = true }
		local config = {
			backend = newBackend(),
			timeReader = function(time): any
				return sample(time)
			end,
			layers = { { id = "base" } },
			parameterDefaults = defaults,
		}
		local first = AnimationController.new(config)
		config.backend = newBackend()
		local second = AnimationController.new(config)
		defaults.speed = 99
		local observed = { parameter = "speed", evaluations = 0 }
		local motion = makeMotion("base/idle", "idle", 1, observed)
		local evaluate = motion.evaluate
		motion.evaluate = function(self, context)
			assert(context.getParameter("grounded") == true, "boolean default missing")
			assert(context.getParameter("stance") == "standing", "string default missing")
			assert(not context.consumeTrigger("attack"), "boolean default armed a trigger")
			return evaluate(self, context)
		end
		first:play("base", motion)
		first:update(0)
		assert(observed.parameterValues[1] == 2, "defaults were aliased or unavailable on first evaluation")
		first:setFloat("speed", 5)
		first:update(1)
		assert(observed.parameterValues[2] == 5, "queued setter did not override default")
		assert(second:getDebugSnapshot().parameters.speed == 2, "controllers share parameter values")
		assert(defaults.speed == 99, "controller mutated caller defaults")
		first:clear()
		assert(next(first:getDebugSnapshot().parameters) == nil, "clear restored construction defaults")
		first:destroy()
		second:destroy()
	end)

	test("omitted parameter defaults keep the store empty", function(): ()
		local controller = AnimationController.new({
			backend = newBackend(),
			timeReader = function(time): any
				return sample(time)
			end,
		})
		assert(next(controller:getDebugSnapshot().parameters) == nil, "omitted defaults seeded values")
		controller:destroy()
	end)

	test("samples each distinct reader once at the explicit coordinate", function(): ()
		local backend = newBackend()
		local calls = 0
		local observedTimes = {} :: { number }
		local timePosition = 5
		local reader = function(sampleTime: number): any
			calls += 1
			observedTimes[#observedTimes + 1] = sampleTime
			return sample(timePosition, -0.5)
		end
		local controller = AnimationController.new({
			backend = backend,
			timeReader = reader,
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
		assert(backend.batches[1][1].timePosition == 5 and backend.batches[1][1].timeRate == -0.5, "sample was split")
		assert(
			backend.batches[1][2].timePosition == 5 and backend.batches[1][2].timeRate == -0.5,
			"sample was not shared"
		)
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
			timeReader = defaultReader,
			layers = {
				{ id = "default" },
				{ id = "layer", timeReader = layerReader },
				{ id = "play", timeReader = shadowReader },
			},
		})
		controller:play("default", makeMotion("default", "idle", 1))
		controller:play("layer", makeMotion("layer", "idle", 1))
		controller:play("play", makeMotion("play", "idle", 1), { timeReader = playReader })
		controller:update(10)

		assert(calls.default == 1 and calls.layer == 1 and calls.play == 1, "selected readers were not sampled")
		assert(calls.shadow == 0, "active-play reader did not shadow the layer reader")
	end)

	test("uses reader position and rate literally without discontinuity policy", function(): ()
		local backend = newBackend()
		local current = sample(10, 1)
		local observations = { evaluations = 0, timePositions = {} :: { number }, timeRates = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
				return current
			end,
			layers = { { id = "base", speed = 2 } },
		})
		controller:play("base", makeMotion("base", "idle", 1.5, observations))
		controller:update(0)
		current = sample(12, -0.5)
		controller:update(1)
		current = sample(5, 0)
		controller:update(2)
		current = sample(100, 2)
		controller:update(3)

		assert(table.concat(observations.timePositions, ",") == "10,12,5,100", "reader position was rewritten")
		assert(table.concat(observations.timeRates, ",") == "1,-0.5,0,2", "reader rate was rewritten")
		for index, batch in backend.batches do
			assert(batch[1].speed == 3, "time sampling changed request speed")
			assert(batch[1].timePosition == observations.timePositions[index], "request lost literal time position")
			assert(batch[1].timeRate == observations.timeRates[index], "request lost literal time rate")
			assert(batch[1].deltaTime == nil, "legacy deltaTime leaked into a request")
		end
	end)

	test("rejects invalid or backward controller coordinates before mutation", function(): ()
		local backend = newBackend()
		local readerCalls = 0
		local controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
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
		local baseObservations = { evaluations = 0, timePositions = {} :: { number } }
		local actionObservations = { evaluations = 0, timePositions = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
				return base
			end,
			layers = {
				{ id = "base" },
				{
					id = "action",
					timeReader = function(_sampleTime: number): any
						return action
					end,
				},
			},
		})
		controller:play("base", makeMotion("base", "idle", 1, baseObservations))
		controller:play("action", makeMotion("action", "wave", 1, actionObservations))
		controller:setBool("armed", true)
		action = { position = math.huge, rate = 1 }
		expectError(function()
			controller:update(1)
		end, "invalid reader sample was accepted")
		action = { position = 2, rate = 0 / 0 }
		expectError(function()
			controller:update(1)
		end, "invalid reader rate was accepted")
		assert(backend.applyCount == 0, "invalid reader batch reached backend")
		assert(controller:getParameter("armed") == nil, "invalid reader batch committed parameters")
		assert(not controller:getDebugSnapshot().layers[1].isPlaying, "invalid reader batch committed play")

		action = sample(2)
		controller:update(1)
		assert(controller:getBool("armed"), "queued commands did not survive invalid reader batch")
		assert(
			baseObservations.timePositions[1] == 1 and actionObservations.timePositions[1] == 2,
			"reader positions were not literal"
		)
	end)

	test("stages controller-default reader replacement and uses its literal coordinate", function(): ()
		local backend = newBackend()
		local firstPosition = 0
		local secondPosition = 100
		local firstReader = function(_sampleTime: number): any
			return sample(firstPosition)
		end
		local secondReader = function(_sampleTime: number): any
			return sample(secondPosition)
		end
		local observations = { evaluations = 0, timePositions = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			timeReader = firstReader,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base", "idle", 1, observations))
		controller:update(0)
		firstPosition = 2
		controller:update(1)
		controller:setDefaultTimeReader(secondReader)
		controller:update(1)
		secondPosition = 103
		controller:update(2)
		assert(table.concat(observations.timePositions, ",") == "0,2,100,103", "replacement reader was not literal")
	end)

	test("stages graph intent and re-evaluates at the same coordinate", function(): ()
		local backend = newBackend()
		local observations = {
			evaluations = 0,
			timePositions = {} :: { number },
			parameter = "blend",
			parameterValues = {} :: { any },
		}
		local controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
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
		assert(observations.timePositions[2] == 0, "same-coordinate evaluation changed time position")
		assert(observations.parameterValues[2] == 0.75, "same-coordinate evaluation did not see new intent")
	end)

	test("defers commands issued by a reader until the following update", function(): ()
		local backend = newBackend()
		local controller: any = nil
		local queued = false
		local observations = {
			evaluations = 0,
			timePositions = {} :: { number },
			parameter = "fromReader",
			parameterValues = {} :: { any },
		}
		controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
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

	test("reader clear invalidates the update and preserves post-clear intent", function(): ()
		local backend = newBackend()
		local controller: any = nil
		local cleared = false
		controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
				if not cleared then
					cleared = true
					controller:clear()
					controller:play("base", makeMotion("replacement", "wave", 1))
				end
				return sample(0)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("stale", "idle", 1))

		controller:update(0)
		assert(backend.clearCount == 1 and backend.applyCount == 0, "clear was undone by the active update")
		assert(not controller:getDebugSnapshot().layers[1].isPlaying, "stale play committed after clear")

		controller:update(0)
		assert(backend.applyCount == 1, "post-clear play was not retained for the next update")
		assert(backend.batches[1][1].clip == "wave", "the stale pre-clear play was resurrected")
	end)

	test("reader destroy invalidates the update permanently", function(): ()
		local backend = newBackend()
		local controller: any = nil
		controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
				controller:destroy()
				return sample(0)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("stale", "idle", 1))

		controller:update(0)
		assert(backend.clearCount == 1 and backend.destroyCount == 1, "reader destroy did not tear down the backend")
		assert(backend.applyCount == 0, "destroyed controller reached backend apply")
		assert(not controller:getDebugSnapshot().layers[1].isPlaying, "play committed after destroy")
	end)

	test("state-machine event clear discards requests from the invalidated evaluation", function(): ()
		local backend = newBackend()
		local machine = StateMachineRuntime.new({
			initialState = "idle",
			states = {
				{ id = "idle", motion = ClipNode.new("idle") },
				{ id = "run", motion = ClipNode.new("run") },
			},
			transitions = { { from = "idle", to = "run", duration = 1 } },
		})
		local controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
				return sample(0)
			end,
			layers = { { id = "base" } },
		})
		controller:on("transitionStarted", function()
			controller:clear()
		end)
		controller:play("base", machine)

		controller:update(0)
		assert(backend.clearCount == 1 and backend.applyCount == 0, "event clear rematerialized tracks")
		assert(not controller:getDebugSnapshot().layers[1].isPlaying, "event clear left the layer active")
	end)

	test("reader changes take effect transactionally at their literal coordinates", function(): ()
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
		local observations = { evaluations = 0, timePositions = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			timeReader = defaultReader,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base", "idle", 1, observations))
		controller:update(0)
		defaultPosition = 2
		controller:update(1)
		controller:setLayerTimeReader("base", layerReader)
		controller:update(1)
		layerPosition = 103
		controller:update(2)
		controller:setActivePlayTimeReader("base", playReader)
		controller:update(2)
		playPosition = 204
		controller:update(3)
		controller:setActivePlayTimeReader("base", nil)
		controller:update(3)
		layerPosition = 105
		controller:update(4)

		assert(
			table.concat(observations.timePositions, ",") == "0,2,100,103,200,204,103,105",
			"reader changes did not expose literal positions"
		)
	end)

	test("transition progress derives from time-position anchors", function(): ()
		local backend = newBackend()
		local timePosition = 20
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
			timeReader = function(_sampleTime: number): any
				return sample(timePosition)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", machine)
		controller:update(0)
		assert(
			machine:getDebugSnapshot().details.transition.progress == 0,
			"transition did not start at its time anchor"
		)
		timePosition = 21
		controller:update(1)
		assert(machine:getDebugSnapshot().details.transition.progress == 0.5, "transition did not sample time position")
		controller:setFloat("irrelevant", 1)
		controller:update(1)
		assert(
			machine:getDebugSnapshot().details.transition.progress == 0.5,
			"same-coordinate command advanced transition"
		)
		timePosition = 10
		controller:update(2)
		assert(machine:getDebugSnapshot().details.transition.progress == 0.5, "backward time rolled transition back")
		timePosition = 10.5
		controller:update(3)
		assert(
			machine:getDebugSnapshot().details.transition.progress == 0.75,
			"transition stalled behind its old anchor"
		)
	end)

	test("replaying an active state machine does not regress transition progress", function(): ()
		local backend = newBackend()
		local sourcePosition = 20
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
			timeReader = function(_sampleTime: number): any
				return sample(sourcePosition)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", machine)
		controller:update(0)
		sourcePosition = 21
		controller:update(1)
		assert(machine:getDebugSnapshot().details.transition.progress == 0.5, "transition did not reach midpoint")

		controller:play("base", machine)
		controller:update(1)
		assert(machine:getDebugSnapshot().details.transition.progress == 0.5, "replay moved transition backward")

		sourcePosition = 21.5
		controller:update(2)
		assert(machine:getDebugSnapshot().details.transition.progress == 0.75, "replayed transition did not continue")
	end)

	test("keeps physical positioning synchronous and graph-neutral", function(): ()
		local backend = newBackend()
		local timePosition = 4
		local observations = { evaluations = 0, timePositions = {} :: { number } }
		local controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
				return sample(timePosition)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base/idle", "idle", 1, observations))
		controller:update(0)
		assert(controller:setTrackPosition("base/idle", { kind = "seconds", value = 3 }), "position was rejected")
		assert(controller:offsetTrackPosition("base/idle", -1.25), "offset was rejected")
		assert(#backend.positionCalls == 1 and #backend.offsetCalls == 1, "physical command was staged")
		timePosition = 6
		controller:update(1)
		assert(observations.timePositions[2] == 6, "physical positioning changed graph time")
	end)

	test("validates assembled requests before backend apply", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
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
		local observations = { evaluations = 0, timePositions = {} :: { number }, emitAfter = 2 }
		local timePosition = 0
		local controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
				return sample(timePosition)
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("delayed", "idle", 1, observations), {
			initialPosition = { kind = "normalized", value = 0.5 },
			forceRestart = true,
		})
		controller:update(0)
		timePosition = 1
		controller:update(1)
		timePosition = 2
		controller:update(2)
		assert(backend.batches[2][1].initialPosition.value == 0.5, "initial position was consumed too early")
		assert(backend.batches[3][1].initialPosition == nil, "initial position was emitted twice")
	end)

	test("stages stopLayer with its resolved fade", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			timeReader = function(_sampleTime: number): any
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
			timeReader = function(_sampleTime: number): any
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

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
		stopCount = 0,
		stopCalls = {} :: { any },
		clearCount = 0,
		destroyCount = 0,
		bindCount = 0,
		bindingReleaseCount = 0,
		positionCalls = {} :: { any },
		offsetCalls = {} :: { any },
		completionListeners = {} :: { any },
	}

	function backend:apply(requests): ()
		self.applyCount += 1
		self.batches[#self.batches + 1] = requests
	end

	function backend:stopLayer(layer, fadeTime): ()
		self.stopCount += 1
		self.stopCalls[#self.stopCalls + 1] = { layer = layer, fadeTime = fadeTime }
	end

	function backend:setTrackPosition(trackKey, position): boolean
		self.positionCalls[#self.positionCalls + 1] = {
			trackKey = trackKey,
			position = position,
		}
		return self.positionResult ~= false
	end

	function backend:offsetTrackPosition(trackKey, deltaSeconds): boolean
		self.offsetCalls[#self.offsetCalls + 1] = {
			trackKey = trackKey,
			deltaSeconds = deltaSeconds,
		}
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

local function makeMotion(trackKey: string, clip: string, speed: number, observations: any?): any
	local state = observations or {
		evaluations = 0,
		elapsed = 0,
	}

	return {
		evaluate = function(_, context)
			state.evaluations += 1
			state.elapsed += context.dt
			if state.emitAfter ~= nil and state.evaluations < state.emitAfter then
				return {}
			end

			local overrides = context.overrides
			return {
				{
					trackKey = if overrides ~= nil and overrides.trackKey ~= nil
						then overrides.trackKey
						else trackKey,
					layer = context.layer,
					state = context.state,
					clip = clip,
					weight = if overrides ~= nil and overrides.weight ~= nil then overrides.weight else 1,
					speed = if overrides ~= nil and overrides.speed ~= nil then overrides.speed else speed,
					deltaTime = -1,
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

	test("samples the source once and a shared reader once while applying every successful sample", function(): ()
		local backend = newBackend()
		local sampleTime = 40
		local logicalPosition = 5
		local sourceCalls = 0
		local readerCalls = 0
		local observedSampleTime = nil
		local sharedReader = function(time: number): number
			readerCalls += 1
			observedSampleTime = time
			return logicalPosition
		end
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				sourceCalls += 1
				return sampleTime
			end,
			logicalPositionReader = sharedReader,
			layers = {
				{ id = "base" },
				{ id = "action" },
			},
		})
		controller:play("base", makeMotion("base/clip", "idle", 1))
		controller:play("action", makeMotion("action/clip", "wave", 1))

		controller:update()
		assert(sourceCalls == 1, "timeSource was not sampled exactly once")
		assert(readerCalls == 1, "shared reader was not sampled exactly once")
		assert(observedSampleTime == 40, "reader did not receive the sampled time")
		assert(backend.applyCount == 1, "first successful sample did not apply")
		assert(backend.batches[1][1].deltaTime == 0 and backend.batches[1][2].deltaTime == 0, "first deltas were not zero")

		sampleTime = 41
		controller:update()
		assert(sourceCalls == 2 and readerCalls == 2, "second update oversampled source or reader")
		assert(backend.applyCount == 2, "unchanged logical sample skipped backend apply")
		assert(backend.batches[2][1].deltaTime == 0 and backend.batches[2][2].deltaTime == 0, "held deltas were not zero")
	end)

	test("uses play then layer then controller reader precedence with one sample time", function(): ()
		local backend = newBackend()
		local sampleTime = 100
		local defaultPosition = 10
		local layerPosition = 20
		local playPosition = 30
		local observedTimes = {} :: { number }
		local calls = { default = 0, layer = 0, play = 0, shadow = 0 }
		local defaultReader = function(time: number): number
			calls.default += 1
			observedTimes[#observedTimes + 1] = time
			return defaultPosition
		end
		local layerReader = function(time: number): number
			calls.layer += 1
			observedTimes[#observedTimes + 1] = time
			return layerPosition
		end
		local shadowReader = function(_time: number): number
			calls.shadow += 1
			return 999
		end
		local playReader = function(time: number): number
			calls.play += 1
			observedTimes[#observedTimes + 1] = time
			return playPosition
		end
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return sampleTime
			end,
			logicalPositionReader = defaultReader,
			layers = {
				{ id = "default" },
				{ id = "layer", logicalPositionReader = layerReader },
				{ id = "play", logicalPositionReader = shadowReader },
			},
		})
		controller:play("default", makeMotion("default/clip", "idle", 1))
		controller:play("layer", makeMotion("layer/clip", "idle", 1))
		controller:play("play", makeMotion("play/clip", "idle", 1), {
			logicalPositionReader = playReader,
		})

		controller:update()
		assert(calls.default == 1 and calls.layer == 1 and calls.play == 1, "selected readers were not sampled once")
		assert(calls.shadow == 0, "play reader did not replace the layer reader")
		for _, observed in observedTimes do
			assert(observed == 100, "readers did not receive the same sample time")
		end

		sampleTime = 101
		defaultPosition += 0.5
		layerPosition += 1
		playPosition += 2
		controller:update()
		local batch = backend.batches[2]
		assert(batch[1].deltaTime == 0.5, "controller reader delta was wrong")
		assert(batch[2].deltaTime == 1, "layer reader delta was wrong")
		assert(batch[3].deltaTime == 2, "play reader delta was wrong")
	end)

	test("creates a fresh first-sample baseline for every replacement play", function(): ()
		local backend = newBackend()
		local logicalPosition = 10
		local reader = function(_time: number): number
			return logicalPosition
		end
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = reader,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("first", "idle", 1))
		controller:update()
		logicalPosition = 12
		controller:update()
		assert(backend.batches[1][1].deltaTime == 0, "first sample was not zero")
		assert(backend.batches[2][1].deltaTime == 2, "forward sample difference was wrong")

		controller:play("base", makeMotion("replacement", "wave", 1), {
			logicalPositionReader = reader,
		})
		logicalPosition = 20
		controller:update()
		logicalPosition = 23
		controller:update()
		assert(backend.batches[3][1].deltaTime == 0, "replacement play reused the old baseline")
		assert(backend.batches[4][1].deltaTime == 3, "replacement baseline did not advance exactly")
	end)

	test("holds and advances layers independently while keeping logical delta and speed separate", function(): ()
		local backend = newBackend()
		local basePosition = 5
		local actionPosition = 8
		local baseState = { evaluations = 0, elapsed = 0 }
		local actionState = { evaluations = 0, elapsed = 0 }
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 50
			end,
			logicalPositionReader = function(_time: number): number
				return basePosition
			end,
			layers = {
				{ id = "base", speed = 2 },
				{
					id = "action",
					logicalPositionReader = function(_time: number): number
						return actionPosition
					end,
				},
			},
		})
		controller:play("base", makeMotion("base/clip", "idle", 1.75, baseState))
		controller:play("action", makeMotion("action/clip", "wave", 1.75, actionState))
		controller:update()
		basePosition = 5
		actionPosition = 8.25
		controller:update()

		assert(baseState.elapsed == 0, "held base reader advanced graph state")
		assert(actionState.elapsed == 0.25, "advancing action reader used the wrong delta")
		local batch = backend.batches[2]
		assert(batch[1].deltaTime == 0 and batch[2].deltaTime == 0.25, "request deltas were not independent")
		assert(batch[1].speed == 3.5 and batch[2].speed == 1.75, "native speed composition was incorrect")

		controller:setLayerSpeed("base", 4)
		basePosition = 5.5
		controller:update()
		local changedSpeedBatch = backend.batches[3]
		assert(changedSpeedBatch[1].deltaTime == 0.5, "native speed change rewrote logical delta")
		assert(changedSpeedBatch[1].speed == 7, "layer speed did not remain an independent native input")
	end)

	test("state-machine transitions use independently sampled logical deltas", function(): ()
		local backend = newBackend()
		local basePosition = 0
		local actionPosition = 0
		local function newMachine(prefix: string): any
			return StateMachineRuntime.new({
				initialState = "idle",
				states = {
					{ id = "idle", motion = ClipNode.new(prefix .. "Idle") },
					{ id = "run", motion = ClipNode.new(prefix .. "Run") },
				},
				transitions = {
					{ from = "idle", to = "run", duration = 1 },
				},
			})
		end

		local baseMachine = newMachine("base")
		local actionMachine = newMachine("action")
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 10
			end,
			logicalPositionReader = function(_time: number): number
				return basePosition
			end,
			layers = {
				{ id = "base" },
				{
					id = "action",
					logicalPositionReader = function(_time: number): number
						return actionPosition
					end,
				},
			},
		})
		controller:play("base", baseMachine)
		controller:play("action", actionMachine)
		controller:update()
		actionPosition = 0.25
		controller:update()

		assert(baseMachine:getDebugSnapshot().details.transition.progress == 0, "held base transition advanced")
		assert(actionMachine:getDebugSnapshot().details.transition.progress == 0.25, "action transition delta was wrong")
		basePosition = 0.5
		controller:update()
		assert(baseMachine:getDebugSnapshot().details.transition.progress == 0.5, "base transition did not advance")
		assert(actionMachine:getDebugSnapshot().details.transition.progress == 0.25, "held action transition advanced")
	end)

	test("rejects non-finite source and reader samples before package mutation", function(): ()
		for _, invalidSource in { 0 / 0, math.huge, -math.huge } do
			local backend = newBackend()
			local readerCalls = 0
			local observations = { evaluations = 0, elapsed = 0 }
			local controller = AnimationController.new({
				backend = backend,
				timeSource = function(): number
					return invalidSource
				end,
				logicalPositionReader = function(_time: number): number
					readerCalls += 1
					return 0
				end,
				layers = { { id = "base" } },
			})
			controller:play("base", makeMotion("base/clip", "idle", 1, observations))
			expectError(function()
				controller:update()
			end, "non-finite timeSource sample was accepted")
			assert(readerCalls == 0 and observations.evaluations == 0, "invalid source reached reader or graph")
			assert(backend.applyCount == 0, "invalid source reached backend")
		end

		for _, invalidPosition in { 0 / 0, math.huge, -math.huge } do
			local backend = newBackend()
			local observations = { evaluations = 0, elapsed = 0 }
			local controller = AnimationController.new({
				backend = backend,
				timeSource = function(): number
					return 1
				end,
				logicalPositionReader = function(_time: number): number
					return invalidPosition
				end,
				layers = { { id = "base" } },
			})
			controller:play("base", makeMotion("base/clip", "idle", 1, observations))
			expectError(function()
				controller:update()
			end, "non-finite reader sample was accepted")
			assert(observations.evaluations == 0 and backend.applyCount == 0, "invalid reader mutated graph or backend")
		end
	end)

	test("rejects backward samples atomically and preserves every prior baseline", function(): ()
		local backend = newBackend()
		local basePosition = 1
		local actionPosition = 1
		local baseState = { evaluations = 0, elapsed = 0 }
		local actionState = { evaluations = 0, elapsed = 0 }
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return basePosition
			end,
			layers = {
				{ id = "base" },
				{
					id = "action",
					logicalPositionReader = function(_time: number): number
						return actionPosition
					end,
				},
			},
		})
		controller:play("base", makeMotion("base/clip", "idle", 1, baseState))
		controller:play("action", makeMotion("action/clip", "wave", 1, actionState))
		controller:update()

		basePosition = 2
		actionPosition = 0.5
		expectError(function()
			controller:update()
		end, "backward reader sample was accepted")
		assert(baseState.evaluations == 1 and actionState.evaluations == 1, "rejected sample evaluated graph state")
		assert(backend.applyCount == 1, "rejected sample reached backend")

		basePosition = 3
		actionPosition = 2
		controller:update()
		local recoveryBatch = backend.batches[2]
		assert(recoveryBatch[1].deltaTime == 2, "earlier valid reader was partially committed")
		assert(recoveryBatch[2].deltaTime == 1, "backward reader replaced its prior baseline")
	end)

	test("integrates an exact large forward sample without discontinuity policy", function(): ()
		local backend = newBackend()
		local logicalPosition = 1
		local observations = { evaluations = 0, elapsed = 0 }
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 0
			end,
			logicalPositionReader = function(_time: number): number
				return logicalPosition
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base/clip", "idle", 1, observations))
		controller:update()
		logicalPosition = 1_000_001
		controller:update()
		assert(observations.elapsed == 1_000_000, "large logical delta was not integrated exactly")
		assert(backend.batches[2][1].deltaTime == 1_000_000, "request did not retain the large exact delta")
	end)

	test("duplicate track keys reject the assembled batch before backend apply", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return 1
			end,
			layers = {
				{ id = "base" },
				{ id = "action" },
			},
		})
		controller:play("base", makeMotion("duplicate", "idle", 1))
		controller:play("action", makeMotion("duplicate", "wave", 1))
		expectError(function()
			controller:update()
		end, "duplicate controller batch was accepted")
		assert(backend.applyCount == 0, "duplicate controller batch reached the backend")
	end)

	test("layer-play initial position validates before replacing the active motion", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return 1
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("original", "idle", 1), {
			initialPosition = { kind = "seconds", value = 1 },
		})
		expectError(function()
			controller:play("base", makeMotion("replacement", "wave", 1), {
				initialPosition = { kind = "normalized", value = 1.1 },
			})
		end, "invalid layer-play position was accepted")
		controller:update()
		assert(backend.batches[1][1].trackKey == "original", "invalid play mutated the active motion")
	end)

	test("assembled invalid positions reject before backend mutation", function(): ()
		local backend = newBackend()
		local invalidMotion = makeMotion("invalid", "idle", 1)
		local originalEvaluate = invalidMotion.evaluate
		invalidMotion.evaluate = function(self, context)
			local requests = originalEvaluate(self, context)
			requests[1].initialPosition = { kind = "seconds", value = math.huge }
			return requests
		end
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return 1
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", invalidMotion)
		expectError(function()
			controller:update()
		end, "invalid assembled position was accepted")
		assert(backend.applyCount == 0, "invalid assembled position reached the backend")
	end)

	test("layer-play initial position waits for and is consumed by the first emitted batch", function(): ()
		local backend = newBackend()
		local observations = { evaluations = 0, elapsed = 0, emitAfter = 2 }
		local logicalPosition = 0
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return logicalPosition
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("delayed", "idle", 1, observations), {
			initialPosition = { kind = "normalized", value = 0.5 },
			forceRestart = true,
		})
		controller:update()
		assert(#backend.batches[1] == 0, "delayed motion emitted too early")
		logicalPosition = 0.1
		controller:update()
		assert(backend.batches[2][1].initialPosition.value == 0.5, "initial override was consumed before emission")
		assert(backend.batches[2][1].forceRestart == true, "restart was consumed before emission")
		logicalPosition = 0.2
		controller:update()
		assert(backend.batches[3][1].initialPosition == nil, "initial override was emitted more than once")
		assert(backend.batches[3][1].forceRestart == false, "restart was emitted more than once")
	end)

	test("clip-node positions validate at construction", function(): ()
		ClipNode.new("validSeconds", { initialPosition = { kind = "seconds", value = 0 } })
		ClipNode.new("validNormalized", { initialPosition = { kind = "normalized", value = 1 } })
		expectError(function()
			ClipNode.new("invalid", { initialPosition = { kind = "frames", value = 1 } })
		end, "invalid ClipNode position was accepted")
	end)

	test("binds backend completion once, forwards it publicly, and releases on destroy", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return 1
			end,
			layers = { { id = "base" } },
		})
		local events = {} :: { any }
		controller:on("trackCompleted", function(event)
			events[#events + 1] = event
		end)
		backend:emitTrackCompleted({
			name = "trackCompleted",
			trackKey = "base/idle",
			layer = "base",
			state = "idle",
		})
		assert(backend.bindCount == 1, "controller did not bind the backend exactly once")
		assert(#events == 1 and events[1].trackKey == "base/idle", "controller did not forward completion")
		controller:destroy()
		backend:emitTrackCompleted({
			name = "trackCompleted",
			trackKey = "stale",
			layer = "base",
			state = "idle",
		})
		assert(backend.bindingReleaseCount == 1, "controller did not release its backend binding")
		assert(#events == 1, "destroyed controller forwarded a stale completion")
	end)

	test("failed construction does not acquire the backend completion binding", function(): ()
		local backend = newBackend()
		expectError(function()
			AnimationController.new({
				backend = backend,
				timeSource = function(): number
					return 1
				end,
				logicalPositionReader = function(_time: number): number
					return 1
				end,
				layers = {
					{ id = "base" },
					{ id = "base" },
				},
			})
		end, "duplicate layer configuration did not fail construction")
		assert(backend.bindCount == 0, "failed construction acquired a backend completion binding")
		assert(#backend.completionListeners == 0, "failed construction retained a backend completion listener")
		assert(backend.bindingReleaseCount == 0, "failed construction created a release obligation")
	end)

	test("validates and delegates live positions without touching logical baselines", function(): ()
		local backend = newBackend()
		local logicalPosition = 4
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return logicalPosition
			end,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("base/idle", "idle", 1))
		controller:update()
		assert(controller:setTrackPosition("base/idle", { kind = "seconds", value = 3 }), "valid controller position was rejected")
		assert(controller:offsetTrackPosition("base/idle", -1.25), "valid controller offset was rejected")
		expectError(function()
			controller:setTrackPosition("base/idle", { kind = "normalized", value = 2 })
		end, "controller accepted an invalid live position")
		for _, invalidOffset in { 0 / 0, math.huge, -math.huge } do
			expectError(function()
				controller:offsetTrackPosition("base/idle", invalidOffset)
			end, "controller accepted a non-finite relative offset")
		end
		assert(#backend.positionCalls == 1, "invalid controller position reached the backend")
		assert(#backend.offsetCalls == 1, "invalid controller offset reached the backend")
		backend.offsetResult = false
		assert(not controller:offsetTrackPosition("base/idle", 0), "controller changed the backend offset result")
		logicalPosition = 6
		controller:update()
		assert(backend.batches[2][1].deltaTime == 2, "live positioning rewrote the logical reader baseline")
		controller:destroy()
		assert(not controller:setTrackPosition("base/idle", { kind = "seconds", value = 1 }), "destroyed controller accepted a live position")
		assert(not controller:offsetTrackPosition("base/idle", 1), "destroyed controller accepted a relative position")
		assert(#backend.positionCalls == 1, "destroyed controller delegated a live position")
		assert(#backend.offsetCalls == 2, "destroyed controller delegated a relative position")
	end)

	test("completion callbacks may re-enter controller lifecycle operations", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return 1
			end,
			layers = { { id = "base" } },
		})
		local calls = 0
		controller:on("trackCompleted", function(event)
			if event.name ~= "trackCompleted" then
				return
			end
			calls += 1
			controller:play("base", makeMotion("replacement", "wave", 1))
			controller:stopLayer("base", 0)
			assert(controller:setTrackPosition("replacement", { kind = "seconds", value = 1 }), "re-entrant position delegation failed")
			controller:clear()
			controller:destroy()
		end)
		backend:emitTrackCompleted({
			name = "trackCompleted",
			trackKey = "base/idle",
			layer = "base",
			state = "idle",
		})
		assert(calls == 1, "re-entrant controller completion duplicated")
		assert(backend.stopCount == 1, "re-entrant stopLayer did not reach the backend")
		assert(backend.clearCount == 2 and backend.destroyCount == 1, "re-entrant clear/destroy ownership was wrong")
		assert(backend.bindingReleaseCount == 1, "re-entrant destroy leaked the completion binding")
	end)

	test("controller event dispatch snapshots listener mutation", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return 1
			end,
		})
		local calls = {} :: { string }
		local releaseFirst = function() end
		local releaseSecond = function() end
		local added = false
		releaseFirst = controller:on("trackCompleted", function()
			calls[#calls + 1] = "first"
			releaseFirst()
			releaseSecond()
			if not added then
				added = true
				controller:on("trackCompleted", function()
					calls[#calls + 1] = "added"
				end)
			end
		end)
		releaseSecond = controller:on("trackCompleted", function()
			calls[#calls + 1] = "second"
		end)
		local event = {
			name = "trackCompleted",
			trackKey = "key",
			layer = "base",
			state = "idle",
		}
		backend:emitTrackCompleted(event)
		backend:emitTrackCompleted(event)
		assert(table.concat(calls, ",") == "first,second,added", "controller listener mutation changed a dispatch snapshot")
	end)

	test("stopLayer resolves the layer default unless an explicit fade is supplied", function(): ()
		local backend = newBackend()
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalPositionReader = function(_time: number): number
				return 1
			end,
			layers = { { id = "base", defaultFadeOut = 0.75 } },
		})
		controller:play("base", makeMotion("base/idle", "idle", 1))
		controller:stopLayer("base")
		controller:play("base", makeMotion("base/idle", "idle", 1))
		controller:stopLayer("base", 0.35)
		assert(backend.stopCalls[1].fadeTime == 0.75, "stopLayer did not use the resolved layer default")
		assert(backend.stopCalls[2].fadeTime == 0.35, "stopLayer ignored its explicit fade")
	end)

	return testCount
end)

transformed.cleanup()
assert(ok, result)

return result

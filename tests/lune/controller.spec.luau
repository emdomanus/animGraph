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
		clearCount = 0,
		destroyCount = 0,
	}

	function backend:apply(requests): ()
		self.applyCount += 1
		self.batches[#self.batches + 1] = requests
	end

	function backend:stopLayer(_layer, _fadeTime): ()
		self.stopCount += 1
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
		local frameNow = 40
		local logicalPosition = 5
		local sourceCalls = 0
		local readerCalls = 0
		local observedFrameNow = nil
		local sharedReader = function(sampleFrameNow: number): number
			readerCalls += 1
			observedFrameNow = sampleFrameNow
			return logicalPosition
		end
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				sourceCalls += 1
				return frameNow
			end,
			logicalTimeReader = sharedReader,
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
		assert(observedFrameNow == 40, "reader did not receive the sampled frameNow")
		assert(backend.applyCount == 1, "first successful sample did not apply")
		assert(backend.batches[1][1].deltaTime == 0 and backend.batches[1][2].deltaTime == 0, "first deltas were not zero")

		frameNow = 41
		controller:update()
		assert(sourceCalls == 2 and readerCalls == 2, "second update oversampled source or reader")
		assert(backend.applyCount == 2, "unchanged logical sample skipped backend apply")
		assert(backend.batches[2][1].deltaTime == 0 and backend.batches[2][2].deltaTime == 0, "held deltas were not zero")
	end)

	test("uses play then layer then controller reader precedence with one frame coordinate", function(): ()
		local backend = newBackend()
		local frameNow = 100
		local defaultPosition = 10
		local layerPosition = 20
		local playPosition = 30
		local observedFrames = {} :: { number }
		local calls = { default = 0, layer = 0, play = 0, shadow = 0 }
		local defaultReader = function(sampleFrameNow: number): number
			calls.default += 1
			observedFrames[#observedFrames + 1] = sampleFrameNow
			return defaultPosition
		end
		local layerReader = function(sampleFrameNow: number): number
			calls.layer += 1
			observedFrames[#observedFrames + 1] = sampleFrameNow
			return layerPosition
		end
		local shadowReader = function(_sampleFrameNow: number): number
			calls.shadow += 1
			return 999
		end
		local playReader = function(sampleFrameNow: number): number
			calls.play += 1
			observedFrames[#observedFrames + 1] = sampleFrameNow
			return playPosition
		end
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return frameNow
			end,
			logicalTimeReader = defaultReader,
			layers = {
				{ id = "default" },
				{ id = "layer", logicalTimeReader = layerReader },
				{ id = "play", logicalTimeReader = shadowReader },
			},
		})
		controller:play("default", makeMotion("default/clip", "idle", 1))
		controller:play("layer", makeMotion("layer/clip", "idle", 1))
		controller:play("play", makeMotion("play/clip", "idle", 1), {
			logicalTimeReader = playReader,
		})

		controller:update()
		assert(calls.default == 1 and calls.layer == 1 and calls.play == 1, "selected readers were not sampled once")
		assert(calls.shadow == 0, "play reader did not replace the layer reader")
		for _, observed in observedFrames do
			assert(observed == 100, "readers did not receive the same frameNow")
		end

		frameNow = 101
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
		local reader = function(_frameNow: number): number
			return logicalPosition
		end
		local controller = AnimationController.new({
			backend = backend,
			timeSource = function(): number
				return 1
			end,
			logicalTimeReader = reader,
			layers = { { id = "base" } },
		})
		controller:play("base", makeMotion("first", "idle", 1))
		controller:update()
		logicalPosition = 12
		controller:update()
		assert(backend.batches[1][1].deltaTime == 0, "first sample was not zero")
		assert(backend.batches[2][1].deltaTime == 2, "forward sample difference was wrong")

		controller:play("base", makeMotion("replacement", "wave", 1), {
			logicalTimeReader = reader,
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
			logicalTimeReader = function(_frameNow: number): number
				return basePosition
			end,
			layers = {
				{ id = "base", speed = 2 },
				{
					id = "action",
					logicalTimeReader = function(_frameNow: number): number
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
			logicalTimeReader = function(_frameNow: number): number
				return basePosition
			end,
			layers = {
				{ id = "base" },
				{
					id = "action",
					logicalTimeReader = function(_frameNow: number): number
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
				logicalTimeReader = function(_frameNow: number): number
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
				logicalTimeReader = function(_frameNow: number): number
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
			logicalTimeReader = function(_frameNow: number): number
				return basePosition
			end,
			layers = {
				{ id = "base" },
				{
					id = "action",
					logicalTimeReader = function(_frameNow: number): number
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
			logicalTimeReader = function(_frameNow: number): number
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
			logicalTimeReader = function(_frameNow: number): number
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
			logicalTimeReader = function(_frameNow: number): number
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
			logicalTimeReader = function(_frameNow: number): number
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
			logicalTimeReader = function(_frameNow: number): number
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

	return testCount
end)

transformed.cleanup()
assert(ok, result)

return result

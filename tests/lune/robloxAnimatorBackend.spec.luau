--!strict

local requireAny = require :: any
local process = requireAny("@lune/process")
local ModuleLoader = requireAny(process.cwd .. "/tests/lune/lib/moduleLoader.luau")
local fakeRobloxPath = (process.cwd:gsub("\\", "/")) .. "/tests/lune/fixtures/fakeRoblox.luau"
local FakeRoblox = requireAny(fakeRobloxPath)

local transformed = ModuleLoader.write({
	sourceRoot = "src",
	tempDir = ".tmp/lune-roblox-backend",
	preamble = "local __fakeRoblox = require([["
		.. fakeRobloxPath
		.. "]])\nlocal Instance = __fakeRoblox.Instance\nlocal Enum = __fakeRoblox.Enum",
})

local function expectError(callback: () -> (), message: string): ()
	local ok = pcall(callback)
	assert(not ok, message)
end

local function newRequest(overrides: any?): any
	local request = {
		trackKey = "base/idle",
		layer = "base",
		state = "idle",
		clip = "idle",
		weight = 1,
		speed = 1,
		deltaTime = 0.25,
		initialPosition = nil,
		looped = false,
		logicalPriority = 0,
		layerBackend = nil,
		fadeTime = 0.2,
		forceRestart = false,
	}
	if overrides ~= nil then
		for key, value in overrides do
			request[key] = value
		end
	end
	return request
end

local ok, result = pcall(function(): number
	local RobloxAnimatorBackend = transformed.requireModule("animGraph/backends/robloxAnimatorBackend/init.luau") :: any
	local testCount = 0

	local function test(name: string, callback: () -> ()): ()
		local passed, failure = pcall(callback)
		if not passed then
			error(`roblox backend: {name}: {failure}`, 0)
		end
		testCount += 1
		print(`PASS roblox backend: {name}`)
	end

	local function newBackend(length: number?): (any, any)
		local animator = FakeRoblox.newAnimator(length)
		local backend = RobloxAnimatorBackend.new({
			animator = animator,
			resolveAssetId = function(_clip): number
				return 123
			end,
		})
		return backend, animator
	end

	test("duplicate keys reject the whole direct batch before materialization", function(): ()
		local backend, animator = newBackend()
		expectError(function()
			backend:apply({
				newRequest(),
				newRequest({ clip = "wave" }),
			})
		end, "duplicate direct batch was accepted")
		assert(animator.loadCount == 0, "duplicate direct batch materialized a track")
	end)

	test("invalid positions reject the whole direct batch before mutation", function(): ()
		local invalidPositions = {
			{ kind = "frames", value = 1 },
			{ kind = "seconds", value = -0.1 },
			{ kind = "seconds", value = 0 / 0 },
			{ kind = "seconds", value = math.huge },
			{ kind = "seconds", value = -math.huge },
			{ kind = "normalized", value = -0.1 },
			{ kind = "normalized", value = 1.1 },
			{ kind = "normalized", value = 0 / 0 },
			{ kind = "normalized", value = math.huge },
			{ kind = "normalized", value = -math.huge },
		}

		for _, position in invalidPositions do
			local backend, animator = newBackend()
			expectError(function()
				backend:apply({
					newRequest({ trackKey = "valid", initialPosition = { kind = "seconds", value = 1 } }),
					newRequest({ trackKey = "invalid", initialPosition = position }),
				})
			end, "invalid direct position was accepted")
			assert(animator.loadCount == 0, "invalid direct position partially mutated the batch")
		end
	end)

	test("seconds and normalized initial positions resolve once", function(): ()
		local secondsBackend, secondsAnimator = newBackend(10)
		local secondsRequest = newRequest({ initialPosition = { kind = "seconds", value = 3 } })
		secondsBackend:apply({ secondsRequest })
		secondsBackend:apply({ secondsRequest })
		local secondsTrack = secondsAnimator.tracks[1]
		assert(#secondsTrack.calls.positionWrites == 1 and secondsTrack.calls.positionWrites[1] == 3, "seconds position was not one-shot")

		local normalizedBackend, normalizedAnimator = newBackend(10)
		local normalizedRequest = newRequest({ initialPosition = { kind = "normalized", value = 0.25 } })
		normalizedBackend:apply({ normalizedRequest })
		normalizedBackend:apply({ normalizedRequest })
		local normalizedTrack = normalizedAnimator.tracks[1]
		assert(
			#normalizedTrack.calls.positionWrites == 1 and normalizedTrack.calls.positionWrites[1] == 2.5,
			"normalized position was not one-shot"
		)
	end)

	test("pending initial position resolves once after length becomes positive", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest({ initialPosition = { kind = "normalized", value = 0.25 } })
		backend:apply({ request })
		local track = animator.tracks[1]
		assert(track.calls.play == 1 and #track.calls.positionWrites == 0, "zero length applied the pending position")
		backend:apply({ request })
		assert(track.calls.play == 1 and #track.calls.positionWrites == 0, "pending poll mutated unchanged playback")
		track:setLength(8)
		backend:apply({ request })
		backend:apply({ request })
		assert(#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 2, "pending position did not resolve exactly once")
	end)

	test("pending terminal position latches completion when positive length resolves", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest({ initialPosition = { kind = "normalized", value = 1 } })
		backend:apply({ request })
		local track = animator.tracks[1]
		track:setLength(8)
		backend:apply({ request })
		backend:apply({ request })
		assert(#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 8, "pending terminal position was wrong")
		assert(track.calls.play == 1, "resolved terminal materialization replayed")
		assert(backend:getDebugSnapshot().tracks[1].isPlaying == false, "resolved terminal position did not latch completion")
	end)

	test("a later desired initial position cannot snap a live generation", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 2 } })
		backend:apply({ request })
		request.initialPosition = { kind = "seconds", value = 7 }
		backend:apply({ request })
		backend:apply({ request })
		local track = animator.tracks[1]
		assert(#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 2, "live generation snapped back")
	end)

	test("non-looping terminal positions clamp and latch without replay", function(): ()
		for _, position in {
			{ kind = "seconds", value = 10 },
			{ kind = "seconds", value = 12 },
			{ kind = "normalized", value = 1 },
		} do
			local backend, animator = newBackend(10)
			local request = newRequest({ initialPosition = position })
			backend:apply({ request })
			backend:apply({ request })
			local track = animator.tracks[1]
			assert(track.calls.positionWrites[1] == 10, "terminal position did not clamp to length")
			assert(track.calls.play == 1, "completed materialization replayed")
			assert(backend:getDebugSnapshot().tracks[1].isPlaying == false, "completed materialization remained logically playing")
		end
	end)

	test("looping boundaries wrap without completion", function(): ()
		for _, case in {
			{ position = { kind = "seconds", value = 20 }, expected = 0 },
			{ position = { kind = "seconds", value = 12 }, expected = 2 },
			{ position = { kind = "normalized", value = 1 }, expected = 0 },
		} do
			local backend, animator = newBackend(10)
			local request = newRequest({ looped = true, initialPosition = case.position })
			backend:apply({ request })
			backend:apply({ request })
			local track = animator.tracks[1]
			assert(track.calls.positionWrites[1] == case.expected, "looping position boundary was wrong")
			assert(track.calls.play == 1, "looping boundary restarted playback")
			assert(backend:getDebugSnapshot().tracks[1].isPlaying == true, "looping boundary latched completion")
		end
	end)

	test("unchanged apply and logical-delta-only changes are native-idempotent", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ weight = 0.75, speed = 1.75, fadeTime = 0.6 })
		backend:apply({ request })
		backend:apply({ request })
		request.deltaTime = 0
		backend:apply({ request })
		request.fadeTime = 1.2
		backend:apply({ request })
		local track = animator.tracks[1]
		assert(animator.loadCount == 1, "unchanged apply rematerialized the track")
		assert(track.calls.play == 1, "unchanged apply replayed the track")
		assert(track.calls.adjustWeight == 0, "unchanged weight or fade target restarted a fade")
		assert(track.calls.adjustSpeed == 0, "unchanged speed was reapplied")
		assert(track.calls.loopedWrites == 1 and track.calls.priorityWrites == 1, "unchanged properties were rewritten")

		backend:apply({})
		backend:apply({})
		assert(track.calls.adjustWeight == 1, "repeated zero fade target restarted the fade")
		backend:apply({ request })
		backend:apply({ request })
		assert(track.calls.adjustWeight == 2, "repeated restored fade target was not idempotent")
		assert(track.calls.play == 1, "reappearing live generation replayed")
	end)

	test("changed native values update only their effective properties", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply({ request })
		local track = animator.tracks[1]
		request.weight = 0.5
		backend:apply({ request })
		assert(track.calls.adjustWeight == 1 and track.calls.adjustSpeed == 0, "weight change touched the wrong property")
		request.speed = 2
		backend:apply({ request })
		assert(track.calls.adjustWeight == 1 and track.calls.adjustSpeed == 1, "speed change touched the wrong property")
		request.looped = true
		backend:apply({ request })
		assert(track.calls.loopedWrites == 2 and track.calls.play == 1, "loop change restarted playback")
	end)

	test("natural non-loop completion latches before an unchanged request can replay", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply({ request })
		local track = animator.tracks[1]
		track:setEnginePlaying(false)
		backend:apply({ request })
		backend:apply({ request })
		assert(track.calls.play == 1, "natural completion replayed")
		assert(backend:getDebugSnapshot().tracks[1].isPlaying == false, "natural completion was not latched")
	end)

	test("forceRestart without a position starts one new generation at zero", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply({ request })
		local track = animator.tracks[1]
		track:setEngineTimePosition(4)
		request.forceRestart = true
		backend:apply({ request })
		request.forceRestart = false
		backend:apply({ request })
		backend:apply({ request })
		assert(track.calls.play == 2 and track.calls.stop == 1, "forceRestart did not create exactly one generation")
		assert(#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 0, "default restart did not start at zero")
		assert(animator.loadCount == 1, "forceRestart rematerialized the physical track")
	end)

	test("forceRestart with a position uses it once instead of the zero default", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply({ request })
		local track = animator.tracks[1]
		track:setEngineTimePosition(4)
		request.forceRestart = true
		request.initialPosition = { kind = "normalized", value = 0.6 }
		backend:apply({ request })
		request.forceRestart = false
		backend:apply({ request })
		backend:apply({ request })
		assert(track.calls.play == 2 and track.calls.stop == 1, "positioned forceRestart was repeated")
		assert(#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 6, "explicit restart position lost precedence")
	end)

	test("declarative initial position reapplies once to a new forced generation", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 2 } })
		backend:apply({ request })
		backend:apply({ request })
		request.forceRestart = true
		backend:apply({ request })
		request.forceRestart = false
		backend:apply({ request })
		local track = animator.tracks[1]
		assert(track.calls.play == 2, "forced materialization generation did not restart exactly once")
		assert(#track.calls.positionWrites == 2, "initial position did not apply once per generation")
		assert(track.calls.positionWrites[1] == 2 and track.calls.positionWrites[2] == 2, "generation positions were wrong")
	end)

	return testCount
end)

transformed.cleanup()
assert(ok, result)

return result

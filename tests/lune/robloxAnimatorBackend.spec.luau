--!strict
--!optimize 2

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
		timePosition = 0,
		timeRate = 1,
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
	local RobloxAnimatorBackend = transformed.requireModule(
		"animGraph/backends/robloxAnimatorBackend/shared/robloxAnimatorBackend/init.luau"
	) :: any
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
			backend:apply(0, {
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
				backend:apply(0, {
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
		secondsBackend:apply(0, { secondsRequest })
		secondsBackend:apply(0, { secondsRequest })
		local secondsTrack = secondsAnimator.tracks[1]
		assert(
			#secondsTrack.calls.positionWrites == 1 and secondsTrack.calls.positionWrites[1] == 3,
			"seconds position was not one-shot"
		)

		local normalizedBackend, normalizedAnimator = newBackend(10)
		local normalizedRequest = newRequest({ initialPosition = { kind = "normalized", value = 0.25 } })
		normalizedBackend:apply(0, { normalizedRequest })
		normalizedBackend:apply(0, { normalizedRequest })
		local normalizedTrack = normalizedAnimator.tracks[1]
		assert(
			#normalizedTrack.calls.positionWrites == 1 and normalizedTrack.calls.positionWrites[1] == 2.5,
			"normalized position was not one-shot"
		)
	end)

	test("pending initial position resolves once after length becomes positive", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest({ initialPosition = { kind = "normalized", value = 0.25 } })
		backend:apply(0, { request })
		local track = animator.tracks[1]
		assert(track.calls.play == 1 and #track.calls.positionWrites == 0, "zero length applied the pending position")
		backend:apply(0, { request })
		assert(track.calls.play == 1 and #track.calls.positionWrites == 0, "pending poll mutated unchanged playback")
		track:setLength(8)
		backend:apply(0, { request })
		backend:apply(0, { request })
		assert(
			#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 2,
			"pending position did not resolve exactly once"
		)
	end)

	test("pending terminal position latches completion when positive length resolves", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest({ initialPosition = { kind = "normalized", value = 1 } })
		backend:apply(0, { request })
		local track = animator.tracks[1]
		track:setLength(8)
		backend:apply(0, { request })
		backend:apply(0, { request })
		assert(
			#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 8,
			"pending terminal position was wrong"
		)
		assert(track.calls.play == 1, "resolved terminal materialization replayed")
		assert(
			backend:getDebugSnapshot().tracks[1].isPlaying == false,
			"resolved terminal position did not latch completion"
		)
	end)

	test("a later desired initial position cannot snap a live generation", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 2 } })
		backend:apply(0, { request })
		request.initialPosition = { kind = "seconds", value = 7 }
		backend:apply(0, { request })
		backend:apply(0, { request })
		local track = animator.tracks[1]
		assert(#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 2, "live generation snapped back")
	end)

	test("non-looping terminal positions clamp and latch without replay", function(): ()
		for _, position in
			{
				{ kind = "seconds", value = 10 },
				{ kind = "seconds", value = 12 },
				{ kind = "normalized", value = 1 },
			}
		do
			local backend, animator = newBackend(10)
			local request = newRequest({ initialPosition = position })
			backend:apply(0, { request })
			backend:apply(0, { request })
			local track = animator.tracks[1]
			assert(track.calls.positionWrites[1] == 10, "terminal position did not clamp to length")
			assert(track.calls.play == 1, "completed materialization replayed")
			assert(
				backend:getDebugSnapshot().tracks[1].isPlaying == false,
				"completed materialization remained logically playing"
			)
		end
	end)

	test("looping boundaries wrap without completion", function(): ()
		for _, case in
			{
				{ position = { kind = "seconds", value = 20 }, expected = 0 },
				{ position = { kind = "seconds", value = 12 }, expected = 2 },
				{ position = { kind = "normalized", value = 1 }, expected = 0 },
			}
		do
			local backend, animator = newBackend(10)
			local request = newRequest({ looped = true, initialPosition = case.position })
			backend:apply(0, { request })
			backend:apply(0, { request })
			local track = animator.tracks[1]
			assert(track.calls.positionWrites[1] == case.expected, "looping position boundary was wrong")
			assert(track.calls.play == 1, "looping boundary restarted playback")
			assert(backend:getDebugSnapshot().tracks[1].isPlaying == true, "looping boundary latched completion")
		end
	end)

	test("signed non-looping boundaries classify by desired direction", function(): ()
		for _, case in
			{
				{
					name = "upper inward",
					position = { kind = "normalized", value = 1 },
					speed = -1,
					expected = 10,
					completed = false,
				},
				{
					name = "upper outward",
					position = { kind = "normalized", value = 1 },
					speed = 1,
					expected = 10,
					completed = true,
				},
				{
					name = "upper held",
					position = { kind = "normalized", value = 1 },
					speed = 0,
					expected = 10,
					completed = false,
				},
				{
					name = "lower inward",
					position = { kind = "seconds", value = 0 },
					speed = 1,
					expected = 0,
					completed = false,
				},
				{
					name = "lower outward",
					position = { kind = "seconds", value = 0 },
					speed = -1,
					expected = 0,
					completed = true,
				},
				{
					name = "lower held",
					position = { kind = "seconds", value = 0 },
					speed = 0,
					expected = 0,
					completed = false,
				},
			}
		do
			local backend, animator = newBackend(10)
			local events = 0
			local committed = false
			backend:bindToTrackCompleted(function()
				events += 1
				local snapshot = backend:getDebugSnapshot()
				committed = #snapshot.tracks == 1 and snapshot.tracks[1].details.lifecycle == "completed"
			end)
			local request = newRequest({ initialPosition = case.position, speed = case.speed })
			backend:apply(0, { request })

			local track = animator.tracks[1]
			local snapshot = backend:getDebugSnapshot()
			assert(
				#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == case.expected,
				case.name .. " wrote the wrong boundary"
			)
			assert(events == (if case.completed then 1 else 0), case.name .. " emitted the wrong completion count")
			assert(not case.completed or committed, case.name .. " dispatched before committing completion")
			assert(
				snapshot.tracks[1].details.lifecycle == (if case.completed then "completed" else "active"),
				case.name .. " had the wrong lifecycle"
			)
			assert(
				animator.loadCount == 1 and track.calls.play == 1,
				case.name .. " replayed or replaced its generation"
			)

			local liveBackend, liveAnimator = newBackend(10)
			local liveEvents = 0
			local liveCommitted = false
			liveBackend:bindToTrackCompleted(function()
				liveEvents += 1
				liveCommitted = liveBackend:getDebugSnapshot().tracks[1].details.lifecycle == "completed"
			end)
			local liveRequest = newRequest({ speed = case.speed })
			liveBackend:apply(0, { liveRequest })
			local liveTrack = liveAnimator.tracks[1]
			liveTrack:setEngineTimePosition(5)
			assert(
				liveBackend:setTrackPosition(liveRequest.trackKey, case.position),
				case.name .. " live boundary was rejected"
			)
			local liveSnapshot = liveBackend:getDebugSnapshot()
			assert(
				#liveTrack.calls.positionWrites == 1 and liveTrack.calls.positionWrites[1] == case.expected,
				case.name .. " live boundary was wrong"
			)
			assert(
				liveEvents == (if case.completed then 1 else 0),
				case.name .. " live boundary emitted the wrong completion count"
			)
			assert(not case.completed or liveCommitted, case.name .. " live boundary dispatched before commit")
			assert(
				liveSnapshot.tracks[1].details.lifecycle == (if case.completed then "completed" else "active"),
				case.name .. " live boundary had the wrong lifecycle"
			)
			assert(
				liveAnimator.loadCount == 1 and liveTrack.calls.play == 1,
				case.name .. " live boundary replayed or replaced its generation"
			)
		end
	end)

	test("pending reverse start holds Play until one upper write then adopts retained speed", function(): ()
		local backend, animator = newBackend(0)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({
			speed = -0.75,
			initialPosition = { kind = "normalized", value = 1 },
		})
		backend:apply(0, { request })
		local track = animator.tracks[1]
		local generation = backend:getDebugSnapshot().tracks[1].details.generation

		assert(track.calls.playSpeeds[1] == 0, "pending reverse start did not Play at zero speed")
		assert(
			#track.calls.positionWrites == 0 and track.calls.adjustSpeed == 0,
			"pending reverse start moved before length resolved"
		)
		assert(
			#track.calls.order == 1 and track.calls.order[1].operation == "Play",
			"pending reverse start emitted an early native operation"
		)
		backend:apply(0, { request })
		assert(#track.calls.order == 1 and events == 0, "unchanged pending reverse start churned or completed")

		track:setLength(8)
		backend:apply(0, { request })
		backend:apply(0, { request })
		local snapshot = backend:getDebugSnapshot().tracks[1]
		assert(
			#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 8,
			"pending reverse start did not write the upper position once"
		)
		assert(
			track.calls.adjustSpeed == 1 and track.calls.speeds[1] == -0.75,
			"pending reverse start did not adopt retained negative speed once"
		)
		assert(#track.calls.order == 3, "pending reverse start emitted extra native operations")
		assert(
			track.calls.order[2].operation == "TimePosition" and track.calls.order[2].value == 8,
			"pending reverse start did not position before speed"
		)
		assert(
			track.calls.order[3].operation == "AdjustSpeed" and track.calls.order[3].value == -0.75,
			"pending reverse start applied the wrong retained speed order"
		)
		assert(
			animator.loadCount == 1 and track.calls.play == 1,
			"pending reverse start replayed or replaced the track"
		)
		assert(
			snapshot.details.generation == generation and snapshot.details.lifecycle == "active",
			"pending reverse start changed generation or completed"
		)
		assert(
			snapshot.speed == -0.75 and events == 0,
			"pending reverse start lost desired speed or signaled completion"
		)

		local pivotBackend, pivotAnimator = newBackend(0)
		local pivotEvents = 0
		pivotBackend:bindToTrackCompleted(function()
			pivotEvents += 1
		end)
		local pivotRequest = newRequest({
			speed = 0,
			initialPosition = { kind = "normalized", value = 1 },
		})
		pivotBackend:apply(0, { pivotRequest })
		local pivotTrack = pivotAnimator.tracks[1]
		local pivotGeneration = pivotBackend:getDebugSnapshot().tracks[1].details.generation

		assert(pivotTrack.calls.playSpeeds[1] == 0, "zero-speed pending start did not Play at zero speed")
		pivotRequest.speed = -1
		pivotBackend:apply(0, { pivotRequest })
		pivotBackend:apply(0, { pivotRequest })
		assert(#pivotTrack.calls.order == 1, "zero-to-negative pending start escaped its zero-speed hold")
		assert(pivotTrack.calls.adjustSpeed == 0, "zero-to-negative pending start adjusted before length resolved")
		assert(pivotEvents == 0, "zero-to-negative pending start completed before length resolved")

		pivotTrack:setLength(6)
		pivotBackend:apply(0, { pivotRequest })
		pivotBackend:apply(0, { pivotRequest })
		local pivotSnapshot = pivotBackend:getDebugSnapshot().tracks[1]
		assert(
			#pivotTrack.calls.positionWrites == 1 and pivotTrack.calls.positionWrites[1] == 6,
			"zero-to-negative pending start did not write the upper position once"
		)
		assert(
			pivotTrack.calls.adjustSpeed == 1 and pivotTrack.calls.speeds[1] == -1,
			"zero-to-negative pending start did not adopt retained negative speed once"
		)
		assert(#pivotTrack.calls.order == 3, "zero-to-negative pending start emitted extra native operations")
		assert(
			pivotTrack.calls.order[2].operation == "TimePosition" and pivotTrack.calls.order[2].value == 6,
			"zero-to-negative pending start did not position before speed"
		)
		assert(
			pivotTrack.calls.order[3].operation == "AdjustSpeed" and pivotTrack.calls.order[3].value == -1,
			"zero-to-negative pending start applied the wrong retained speed order"
		)
		assert(
			pivotAnimator.loadCount == 1 and pivotTrack.calls.play == 1,
			"zero-to-negative pending start replayed or replaced the track"
		)
		assert(
			pivotSnapshot.details.generation == pivotGeneration and pivotSnapshot.details.lifecycle == "active",
			"zero-to-negative pending start changed generation or completed"
		)
		assert(
			pivotSnapshot.speed == -1 and pivotEvents == 0,
			"zero-to-negative pending start lost desired speed or signaled completion"
		)
	end)

	test("known-length reverse start activates signed speed before one upper write", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ speed = -1, initialPosition = { kind = "normalized", value = 1 } })
		backend:apply(0, { request })
		backend:apply(0, { request })

		local track = animator.tracks[1]
		local snapshot = backend:getDebugSnapshot().tracks[1]
		assert(#track.calls.order == 2, "known-length reverse start emitted extra native operations")
		assert(
			track.calls.order[1].operation == "Play" and track.calls.order[1].value == -1,
			"known-length reverse start did not Play at signed speed"
		)
		assert(
			track.calls.order[2].operation == "TimePosition" and track.calls.order[2].value == 10,
			"known-length reverse start did not position after Play"
		)
		assert(
			track.calls.adjustSpeed == 0 and #track.calls.positionWrites == 1,
			"known-length reverse start reapplied speed or position"
		)
		assert(
			snapshot.details.lifecycle == "active" and snapshot.speed == -1,
			"known-length reverse start did not remain active inward"
		)
	end)

	test("interior sign pivots use only AdjustSpeed on one generation", function(): ()
		local backend, animator = newBackend(10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest()
		backend:apply(0, { request })
		local track = animator.tracks[1]
		track:setEngineTimePosition(4)
		local generation = backend:getDebugSnapshot().tracks[1].details.generation

		for _, speed in { -1, 0, 0.5 } do
			request.speed = speed
			backend:apply(0, { request })
		end

		local snapshot = backend:getDebugSnapshot().tracks[1]
		assert(track.calls.adjustSpeed == 3, "interior sign pivots did not use exactly one speed adjustment each")
		assert(
			track.calls.speeds[1] == -1 and track.calls.speeds[2] == 0 and track.calls.speeds[3] == 0.5,
			"interior sign pivots applied the wrong speeds"
		)
		assert(#track.calls.positionWrites == 0 and track.calls.play == 1, "interior sign pivots sought or replayed")
		assert(
			animator.loadCount == 1 and snapshot.details.generation == generation,
			"interior sign pivots replaced the generation"
		)
		assert(snapshot.details.lifecycle == "active" and events == 0, "interior sign pivots completed playback")
	end)

	test("boundary sign pivots hold or move inward and complete only when outward", function(): ()
		for _, case in
			{
				{
					name = "upper",
					position = { kind = "normalized", value = 1 },
					initialSpeed = -1,
					inwardSpeed = -0.5,
					outwardSpeed = 1,
				},
				{
					name = "lower",
					position = { kind = "seconds", value = 0 },
					initialSpeed = 1,
					inwardSpeed = 0.5,
					outwardSpeed = -1,
				},
			}
		do
			local backend, animator = newBackend(10)
			local events = 0
			local committed = false
			backend:bindToTrackCompleted(function()
				events += 1
				committed = backend:getDebugSnapshot().tracks[1].details.lifecycle == "completed"
			end)
			local request = newRequest({ initialPosition = case.position, speed = case.initialSpeed })
			backend:apply(0, { request })
			local track = animator.tracks[1]
			local generation = backend:getDebugSnapshot().tracks[1].details.generation

			request.speed = 0
			backend:apply(0, { request })
			assert(
				events == 0 and backend:getDebugSnapshot().tracks[1].details.lifecycle == "active",
				case.name .. " zero pivot completed"
			)
			request.speed = case.inwardSpeed
			backend:apply(0, { request })
			assert(
				events == 0 and backend:getDebugSnapshot().tracks[1].details.lifecycle == "active",
				case.name .. " inward pivot completed"
			)
			request.speed = case.outwardSpeed
			backend:apply(0, { request })
			backend:apply(0, { request })
			track:fireStopped()

			local snapshot = backend:getDebugSnapshot().tracks[1]
			assert(events == 1 and committed, case.name .. " outward pivot did not complete once after commit")
			assert(track.calls.adjustSpeed == 3, case.name .. " pivots did not adjust speed exactly once each")
			assert(
				#track.calls.positionWrites == 1 and track.calls.play == 1,
				case.name .. " pivots sought or replayed"
			)
			assert(
				animator.loadCount == 1 and snapshot.details.generation == generation,
				case.name .. " pivots changed generation"
			)
		end
	end)

	test("natural reverse lower end completes exactly once", function(): ()
		local backend, animator = newBackend(10)
		local events = 0
		local committed = false
		backend:bindToTrackCompleted(function()
			events += 1
			committed = backend:getDebugSnapshot().tracks[1].details.lifecycle == "completed"
		end)
		local request = newRequest({ speed = -1, initialPosition = { kind = "normalized", value = 1 } })
		backend:apply(0, { request })
		local track = animator.tracks[1]
		track:setEngineTimePosition(0)
		track:fireStopped()
		track:fireStopped()
		backend:apply(0, { request })

		assert(events == 1 and committed, "natural reverse end did not complete exactly once after commit")
		assert(animator.loadCount == 1 and track.calls.play == 1, "natural reverse end replayed")
		track:fireEnded()
		track:fireStopped()
		assert(
			events == 1 and track.calls.destroy == 1,
			"natural reverse stale signals duplicated completion or cleanup"
		)
	end)

	test("reverse loop positions wrap without terminal completion", function(): ()
		local backend, animator = newBackend(10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({
			speed = -1,
			looped = true,
			initialPosition = { kind = "normalized", value = 1 },
		})
		backend:apply(0, { request })
		assert(
			backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 22 }),
			"reverse loop seconds position was rejected"
		)
		assert(
			backend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 }),
			"reverse loop normalized position was rejected"
		)

		local track = animator.tracks[1]
		local writes = track.calls.positionWrites
		local snapshot = backend:getDebugSnapshot().tracks[1]
		assert(writes[1] == 0 and writes[2] == 2 and writes[3] == 0, "reverse loop did not wrap and canonicalize")
		assert(events == 0 and snapshot.details.lifecycle == "active", "reverse loop addressing completed playback")
		assert(
			track.calls.playSpeeds[1] == -1 and track.calls.play == 1,
			"reverse loop did not retain native reverse playback"
		)
	end)

	test("reverse rematerialization preserves position and speed while ignoring stale signals", function(): ()
		local backend, animator = newBackend(10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({ speed = -1, initialPosition = { kind = "seconds", value = 10 } })
		backend:apply(0, { request })
		local oldTrack = animator.tracks[1]
		local oldGeneration = backend:getDebugSnapshot().tracks[1].details.generation
		backend:apply(0, {})
		backend:apply(0, { request })
		local newTrack = animator.tracks[2]
		local replacement: any = nil
		for _, playback in backend:getDebugSnapshot().tracks do
			if playback.details.lifecycle == "active" then
				replacement = playback
				break
			end
		end
		assert(replacement ~= nil, "reverse rematerialization did not create an active generation")

		assert(
			oldTrack.calls.playSpeeds[1] == -1 and newTrack.calls.playSpeeds[1] == -1,
			"reverse rematerialization lost signed speed"
		)
		assert(
			oldTrack.calls.positionWrites[1] == 10 and newTrack.calls.positionWrites[1] == 10,
			"reverse rematerialization lost absolute position"
		)
		assert(
			replacement.details.generation > oldGeneration and replacement.details.lifecycle == "active",
			"reverse rematerialization reused or completed its generation"
		)
		oldTrack:fireStopped()
		oldTrack:fireEnded()
		assert(
			events == 0 and oldTrack.calls.destroy == 1,
			"stale reverse signals completed or leaked the old generation"
		)
		assert(
			newTrack.calls.destroy == 0 and newTrack.TimePosition == 10,
			"stale reverse signals mutated the new generation"
		)
		assert(
			backend:getDebugSnapshot().tracks[1].details.generation == replacement.details.generation,
			"stale reverse signals changed active ownership"
		)
	end)

	test("unchanged apply and fade-only changes are native-idempotent", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ weight = 0.75, speed = 1.75, fadeTime = 0.6 })
		backend:apply(0, { request })
		backend:apply(0, { request })
		backend:apply(0, { request })
		request.fadeTime = 1.2
		backend:apply(0, { request })
		local track = animator.tracks[1]
		assert(animator.loadCount == 1, "unchanged apply rematerialized the track")
		assert(track.calls.play == 1, "unchanged apply replayed the track")
		assert(track.calls.adjustWeight == 0, "unchanged weight or fade target restarted a fade")
		assert(track.calls.adjustSpeed == 0, "unchanged speed was reapplied")
		assert(track.calls.loopedWrites == 1 and track.calls.priorityWrites == 1, "unchanged properties were rewritten")

		backend:apply(0, {})
		backend:apply(0, {})
		assert(track.calls.stop == 1, "repeated disappearance restarted retirement")
		assert(track.calls.stopFades[1] == 0.2, "disappearance used the wrong fade")
		backend:apply(0, { request })
		backend:apply(0, { request })
		assert(animator.loadCount == 2, "reappearance did not materialize exactly one new generation")
		assert(animator.tracks[2].calls.play == 1, "unchanged reappearing generation replayed")
	end)

	test("changed native values update only their effective properties", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply(0, { request })
		local track = animator.tracks[1]
		request.weight = 0.5
		backend:apply(0, { request })
		assert(
			track.calls.adjustWeight == 1 and track.calls.adjustSpeed == 0,
			"weight change touched the wrong property"
		)
		request.speed = 2
		backend:apply(0, { request })
		assert(
			track.calls.adjustWeight == 1 and track.calls.adjustSpeed == 1,
			"speed change touched the wrong property"
		)
		request.looped = true
		backend:apply(0, { request })
		assert(track.calls.loopedWrites == 2 and track.calls.play == 1, "loop change restarted playback")
	end)

	test("natural non-loop completion latches before an unchanged request can replay", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply(0, { request })
		local track = animator.tracks[1]
		track:fireStopped()
		backend:apply(0, { request })
		backend:apply(0, { request })
		assert(track.calls.play == 1, "natural completion replayed")
		assert(backend:getDebugSnapshot().tracks[1].isPlaying == false, "natural completion was not latched")
	end)

	test("forceRestart without a position starts one new generation at zero", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply(0, { request })
		local oldTrack = animator.tracks[1]
		oldTrack:setEngineTimePosition(4)
		request.forceRestart = true
		backend:apply(0, { request })
		request.forceRestart = false
		backend:apply(0, { request })
		backend:apply(0, { request })
		local newTrack = animator.tracks[2]
		assert(oldTrack.calls.play == 1 and oldTrack.calls.stop == 1, "forceRestart did not retire the old generation")
		assert(newTrack.calls.play == 1 and newTrack.TimePosition == 0, "default restart did not start at zero")
		assert(animator.loadCount == 2, "forceRestart did not materialize exactly one new physical generation")
	end)

	test("forceRestart with a position uses it once instead of the zero default", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply(0, { request })
		local oldTrack = animator.tracks[1]
		oldTrack:setEngineTimePosition(4)
		request.forceRestart = true
		request.initialPosition = { kind = "normalized", value = 0.6 }
		backend:apply(0, { request })
		request.forceRestart = false
		backend:apply(0, { request })
		backend:apply(0, { request })
		local newTrack = animator.tracks[2]
		assert(oldTrack.calls.stop == 1 and newTrack.calls.play == 1, "positioned forceRestart was repeated")
		assert(
			#newTrack.calls.positionWrites == 1 and newTrack.calls.positionWrites[1] == 6,
			"explicit restart position lost precedence"
		)
	end)

	test("declarative initial position reapplies once to a new forced generation", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 2 } })
		backend:apply(0, { request })
		backend:apply(0, { request })
		request.forceRestart = true
		backend:apply(0, { request })
		request.forceRestart = false
		backend:apply(0, { request })
		assert(animator.loadCount == 2, "forced materialization generation did not restart exactly once")
		assert(#animator.tracks[1].calls.positionWrites == 1, "first generation position was not one-shot")
		assert(#animator.tracks[2].calls.positionWrites == 1, "second generation position was not one-shot")
		assert(animator.tracks[1].calls.positionWrites[1] == 2, "first generation position was wrong")
		assert(animator.tracks[2].calls.positionWrites[1] == 2, "second generation position was wrong")
	end)

	test("live positioning moves forward and backward without replacing the generation", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ weight = 0.7, speed = 1.5, looped = true, logicalPriority = 50 })
		backend:apply(0, { request })
		local before = backend:getDebugSnapshot().tracks[1]
		local generation = before.details.generation
		assert(
			backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 7 }),
			"forward position was rejected"
		)
		assert(
			backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 2 }),
			"backward position was rejected"
		)

		local track = animator.tracks[1]
		local after = backend:getDebugSnapshot().tracks[1]
		assert(
			animator.loadCount == 1 and track.calls.play == 1,
			"live positioning replaced or replayed the generation"
		)
		assert(after.details.generation == generation, "live positioning changed generation identity")
		assert(after.weight == 0.7 and after.speed == 1.5, "live positioning changed desired native state")
		assert(#track.calls.positionWrites == 2, "live positions were not written exactly once")
		assert(track.calls.positionWrites[1] == 7 and track.calls.positionWrites[2] == 2, "live positions were wrong")
	end)

	test("relative positioning validates finite deltas and reports active eligibility", function(): ()
		local backend, animator = newBackend(10)
		assert(not backend:offsetTrackPosition("missing", 1), "missing relative target was accepted")
		local request = newRequest()
		backend:apply(0, { request })
		local track = animator.tracks[1]
		track:setEngineTimePosition(4)

		for _, invalidOffset in { 0 / 0, math.huge, -math.huge } do
			expectError(function()
				backend:offsetTrackPosition(request.trackKey, invalidOffset)
			end, "non-finite relative offset was accepted")
		end
		assert(
			#track.calls.positionWrites == 0 and track.calls.positionReads == 0,
			"invalid relative offset mutated playback"
		)
		assert(backend:offsetTrackPosition(request.trackKey, 1), "active relative target was rejected")
		assert(track.calls.positionWrites[1] == 5, "accepted relative offset wrote the wrong position")

		backend:apply(0, {})
		assert(not backend:offsetTrackPosition(request.trackKey, 1), "retiring relative target was accepted")

		local completedBackend = newBackend(10)
		completedBackend:apply(0, { request })
		assert(completedBackend:offsetTrackPosition(request.trackKey, 10), "completing relative command was rejected")
		assert(not completedBackend:offsetTrackPosition(request.trackKey, -1), "completed relative target was accepted")

		local destroyedBackend = newBackend(10)
		destroyedBackend:apply(0, { request })
		destroyedBackend:destroy()
		assert(
			not destroyedBackend:offsetTrackPosition(request.trackKey, 1),
			"destroyed backend accepted a relative target"
		)
	end)

	test("known-length offsets compose on one generation without native property churn", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ weight = 0.7, speed = 1.5, logicalPriority = 50, fadeTime = 0.6 })
		backend:apply(0, { request })
		local track = animator.tracks[1]
		track:setEngineTimePosition(5)
		local before = backend:getDebugSnapshot().tracks[1]
		local generation = before.details.generation
		local wasPlaying = track.IsPlaying

		assert(backend:offsetTrackPosition(request.trackKey, 2), "positive known-length offset was rejected")
		assert(backend:offsetTrackPosition(request.trackKey, -3), "negative known-length offset was rejected")
		assert(backend:offsetTrackPosition(request.trackKey, 1.5), "ordered known-length offset was rejected")

		local after = backend:getDebugSnapshot().tracks[1]
		local writes = track.calls.positionWrites
		assert(
			#writes == 3 and writes[1] == 7 and writes[2] == 4 and writes[3] == 5.5,
			"known-length offsets did not compose in call order"
		)
		assert(
			track.calls.positionReads == 3,
			"known-length offsets did not read the physical base exactly once per command"
		)
		assert(animator.loadCount == 1 and track.calls.play == 1, "known-length offsets replayed or replaced playback")
		assert(
			track.calls.adjustWeight == 0 and track.calls.adjustSpeed == 0,
			"known-length offsets changed native weight or speed"
		)
		assert(
			track.calls.loopedWrites == 1 and track.calls.priorityWrites == 1,
			"known-length offsets rewrote loop or priority"
		)
		assert(track.IsPlaying == wasPlaying, "known-length offsets changed physical playing state")
		assert(
			after.details.generation == generation and after.weight == 0.7 and after.speed == 1.5,
			"known-length offsets changed generation or desired properties"
		)
	end)

	test("forward and reverse looping offsets wrap without completion", function(): ()
		for _, case in
			{
				{
					name = "forward",
					speed = 1,
					start = 9,
					first = 3,
					firstExpected = 2,
					second = -4,
					secondExpected = 8,
				},
				{
					name = "reverse",
					speed = -1,
					start = 1,
					first = -3,
					firstExpected = 8,
					second = 4,
					secondExpected = 2,
				},
			}
		do
			local backend, animator = newBackend(10)
			local events = 0
			backend:bindToTrackCompleted(function()
				events += 1
			end)
			local request = newRequest({ speed = case.speed, looped = true })
			backend:apply(0, { request })
			local track = animator.tracks[1]
			track:setEngineTimePosition(case.start)
			assert(
				backend:offsetTrackPosition(request.trackKey, case.first),
				case.name .. " first loop offset was rejected"
			)
			assert(
				backend:offsetTrackPosition(request.trackKey, case.second),
				case.name .. " second loop offset was rejected"
			)
			local writes = track.calls.positionWrites
			assert(
				#writes == 2 and writes[1] == case.firstExpected and writes[2] == case.secondExpected,
				case.name .. " loop offsets wrapped incorrectly"
			)
			assert(track.calls.positionReads == 2, case.name .. " loop offsets read the physical position incorrectly")
			assert(
				events == 0 and backend:getDebugSnapshot().tracks[1].details.lifecycle == "active",
				case.name .. " loop offsets completed playback"
			)
		end
	end)

	test("relative terminal classification uses desired speed rather than offset sign", function(): ()
		for _, case in
			{
				{ name = "upper outward", speed = 1, start = 9, delta = 2, expected = 10, completed = true },
				{ name = "lower outward", speed = -1, start = 1, delta = -2, expected = 0, completed = true },
				{
					name = "upper outward zero delta",
					speed = 1,
					start = 10,
					delta = 0,
					expected = 10,
					completed = true,
				},
				{ name = "lower outward zero delta", speed = -1, start = 0, delta = 0, expected = 0, completed = true },
				{ name = "upper inward", speed = -1, start = 9, delta = 2, expected = 10, completed = false },
				{ name = "lower inward", speed = 1, start = 1, delta = -2, expected = 0, completed = false },
				{ name = "upper held", speed = 0, start = 9, delta = 2, expected = 10, completed = false },
				{ name = "lower held", speed = 0, start = 1, delta = -2, expected = 0, completed = false },
			}
		do
			local backend, animator = newBackend(10)
			local events = 0
			local committed = false
			backend:bindToTrackCompleted(function()
				events += 1
				committed = backend:getDebugSnapshot().tracks[1].details.lifecycle == "completed"
			end)
			local request = newRequest({ speed = case.speed })
			backend:apply(0, { request })
			local track = animator.tracks[1]
			track:setEngineTimePosition(case.start)
			assert(backend:offsetTrackPosition(request.trackKey, case.delta), case.name .. " offset was rejected")

			local snapshot = backend:getDebugSnapshot().tracks[1]
			assert(
				#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == case.expected,
				case.name .. " wrote the wrong terminal"
			)
			assert(events == (if case.completed then 1 else 0), case.name .. " emitted the wrong completion count")
			assert(not case.completed or committed, case.name .. " dispatched before lifecycle commit")
			assert(
				snapshot.details.lifecycle == (if case.completed then "completed" else "active"),
				case.name .. " had the wrong lifecycle"
			)
			if case.completed then
				assert(not backend:offsetTrackPosition(request.trackKey, -case.delta), case.name .. " completed twice")
				track:fireStopped()
				assert(events == 1, case.name .. " stale Stopped duplicated completion")
			end
		end
	end)

	test("unresolved offsets accumulate and use the physical base observed at resolution", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest()
		backend:apply(0, { request })
		local track = animator.tracks[1]
		assert(backend:offsetTrackPosition(request.trackKey, 3), "first unresolved offset was rejected")
		assert(backend:offsetTrackPosition(request.trackKey, -1), "second unresolved offset was rejected")
		track:setEngineTimePosition(4)
		assert(
			#track.calls.positionWrites == 0 and track.calls.positionReads == 0,
			"unresolved offsets observed or wrote position early"
		)

		track:setLength(10)
		backend:apply(0, { request })
		backend:apply(0, { request })
		assert(
			#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 6,
			"unresolved offsets did not use the resolution-time physical base"
		)
		assert(track.calls.positionReads == 1, "unresolved offsets did not observe the physical base exactly once")
		assert(
			track.calls.play == 1 and animator.loadCount == 1,
			"unresolved offset resolution replayed or replaced playback"
		)
	end)

	test("unresolved offset accumulation rejects overflow without poisoning the generation", function(): ()
		local function resolveLoopOffset(basePosition: number, deltaSeconds: number, length: number): number
			local wrappedBase = basePosition % length
			local wrappedDelta = deltaSeconds % length
			local distanceToEnd = length - wrappedBase
			return if wrappedDelta >= distanceToEnd then wrappedDelta - distanceToEnd else wrappedBase + wrappedDelta
		end

		local backend, animator = newBackend(0)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({ looped = true })
		backend:apply(0, { request })
		local track = animator.tracks[1]
		local before = backend:getDebugSnapshot().tracks[1]
		local generation = before.details.generation
		local validOffset = 1e308
		assert(backend:offsetTrackPosition(request.trackKey, validOffset), "large finite offset was rejected")

		local callsBeforeOverflow = {
			play = track.calls.play,
			adjustWeight = track.calls.adjustWeight,
			adjustSpeed = track.calls.adjustSpeed,
			stop = track.calls.stop,
			destroy = track.calls.destroy,
			loopedWrites = track.calls.loopedWrites,
			priorityWrites = track.calls.priorityWrites,
			positionReads = track.calls.positionReads,
			positionWrites = #track.calls.positionWrites,
			order = #track.calls.order,
			isPlaying = track.IsPlaying,
		}
		local accepted, resultOrError = pcall(function(): unknown
			backend:offsetTrackPosition(request.trackKey, validOffset)
			return nil
		end)
		assert(not accepted, "non-finite accumulated offset was accepted")
		assert(
			string.find(tostring(resultOrError), "accumulated pending offset must be finite", 1, true) ~= nil,
			"accumulated offset overflow raised the wrong validation error"
		)

		local afterOverflow = backend:getDebugSnapshot().tracks[1]
		assert(track.calls.play == callsBeforeOverflow.play, "rejected offset replayed the generation")
		assert(track.calls.adjustWeight == callsBeforeOverflow.adjustWeight, "rejected offset changed native weight")
		assert(track.calls.adjustSpeed == callsBeforeOverflow.adjustSpeed, "rejected offset changed native speed")
		assert(track.calls.stop == callsBeforeOverflow.stop, "rejected offset stopped the generation")
		assert(track.calls.destroy == callsBeforeOverflow.destroy, "rejected offset destroyed the generation")
		assert(track.calls.loopedWrites == callsBeforeOverflow.loopedWrites, "rejected offset rewrote Looped")
		assert(track.calls.priorityWrites == callsBeforeOverflow.priorityWrites, "rejected offset rewrote Priority")
		assert(track.calls.positionReads == callsBeforeOverflow.positionReads, "rejected offset read native position")
		assert(
			#track.calls.positionWrites == callsBeforeOverflow.positionWrites,
			"rejected offset wrote native position"
		)
		assert(#track.calls.order == callsBeforeOverflow.order, "rejected offset emitted a native ordered operation")
		assert(track.IsPlaying == callsBeforeOverflow.isPlaying, "rejected offset changed physical playing state")
		assert(events == 0, "rejected offset emitted completion")
		assert(
			afterOverflow.details.generation == generation and afterOverflow.details.lifecycle == "active",
			"rejected offset changed generation ownership or lifecycle"
		)
		assert(
			afterOverflow.weight == before.weight and afterOverflow.speed == before.speed,
			"rejected offset changed desired native properties"
		)

		local resolvedLength = 10
		local expectedResolved = resolveLoopOffset(0, validOffset, resolvedLength)
		track:setLength(resolvedLength)
		backend:apply(0, { request })
		backend:apply(0, { request })
		assert(
			#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == expectedResolved,
			"valid pending offset was not resolved exactly once after rejected overflow"
		)
		assert(track.calls.positionReads == 1, "pending offset did not observe its physical base exactly once")

		local ordinaryOffset = 1.25
		local expectedOrdinary = resolveLoopOffset(expectedResolved, ordinaryOffset, resolvedLength)
		assert(
			backend:offsetTrackPosition(request.trackKey, ordinaryOffset),
			"generation remained poisoned after overflow rejection"
		)
		backend:apply(0, { request })
		assert(
			#track.calls.positionWrites == 2 and track.calls.positionWrites[2] == expectedOrdinary,
			"ordinary offset failed after overflow rejection"
		)

		local cancellationBackend, cancellationAnimator = newBackend(0)
		local cancellationRequest = newRequest({ looped = true })
		cancellationBackend:apply(0, { cancellationRequest })
		assert(
			cancellationBackend:offsetTrackPosition(cancellationRequest.trackKey, validOffset),
			"cancellation base was rejected"
		)
		assert(
			cancellationBackend:offsetTrackPosition(cancellationRequest.trackKey, -validOffset),
			"finite cancellation was rejected"
		)
		local cancellationTrack = cancellationAnimator.tracks[1]
		local cancellationSum = validOffset + -validOffset
		local expectedCancellation = resolveLoopOffset(0, cancellationSum, resolvedLength)
		cancellationTrack:setLength(resolvedLength)
		cancellationBackend:apply(0, { cancellationRequest })
		cancellationBackend:apply(0, { cancellationRequest })
		assert(
			#cancellationTrack.calls.positionWrites == 1
				and cancellationTrack.calls.positionWrites[1] == expectedCancellation,
			"representable cancellation did not resolve exactly once"
		)
	end)

	test("pending normalized initial position composes offsets into one idempotent write", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest({ initialPosition = { kind = "normalized", value = 0.25 } })
		backend:apply(0, { request })
		local track = animator.tracks[1]
		assert(backend:offsetTrackPosition(request.trackKey, 3), "pending initial positive offset was rejected")
		assert(backend:offsetTrackPosition(request.trackKey, -1), "pending initial negative offset was rejected")
		assert(#track.calls.positionWrites == 0, "pending initial plus offsets wrote before length resolved")

		track:setLength(8)
		backend:apply(0, { request })
		backend:apply(0, { request })
		assert(
			#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 4,
			"pending normalized base plus offsets resolved incorrectly"
		)
		assert(track.calls.positionReads == 0, "pending absolute base incorrectly read physical position")
		assert(track.calls.play == 1 and track.calls.adjustSpeed == 0, "pending initial plus offsets churned playback")
	end)

	test("relative completion resolved during apply waits for the complete batch", function(): ()
		local backend, animator = newBackend(0)
		local terminal = newRequest({
			trackKey = "terminal",
			initialPosition = { kind = "seconds", value = 9 },
		})
		local companion = newRequest({ trackKey = "companion", clip = "wave" })
		local sawCommittedBatch = false
		backend:bindToTrackCompleted(function()
			local lifecycles = {} :: { [string]: string }
			local weights = {} :: { [string]: number }
			for _, playback in backend:getDebugSnapshot().tracks do
				lifecycles[playback.trackKey] = playback.details.lifecycle
				weights[playback.trackKey] = playback.weight
			end
			sawCommittedBatch = lifecycles.terminal == "completed" and weights.companion == 0.5
		end)
		backend:apply(0, { terminal, companion })
		assert(backend:offsetTrackPosition(terminal.trackKey, 2), "pending relative terminal was rejected")
		animator.tracks[1]:setLength(10)
		companion.weight = 0.5
		backend:apply(0, { terminal, companion })
		assert(sawCommittedBatch, "relative completion dispatched before the batch committed")
	end)

	test("unresolved absolute and relative commands preserve supersession order", function(): ()
		local firstBackend, firstAnimator = newBackend(0)
		local firstRequest = newRequest()
		firstBackend:apply(0, { firstRequest })
		assert(firstBackend:offsetTrackPosition(firstRequest.trackKey, 4), "offset-before-absolute was rejected")
		assert(
			firstBackend:setTrackPosition(firstRequest.trackKey, { kind = "normalized", value = 0.5 }),
			"absolute supersession was rejected"
		)
		assert(firstBackend:offsetTrackPosition(firstRequest.trackKey, 1), "offset-after-absolute was rejected")
		firstAnimator.tracks[1]:setLength(10)
		firstBackend:apply(0, { firstRequest })
		firstBackend:apply(0, { firstRequest })
		assert(
			#firstAnimator.tracks[1].calls.positionWrites == 1 and firstAnimator.tracks[1].calls.positionWrites[1] == 6,
			"absolute did not supersede the earlier offset or retain the later offset"
		)

		local secondBackend, secondAnimator = newBackend(0)
		local secondRequest = newRequest()
		secondBackend:apply(0, { secondRequest })
		assert(
			secondBackend:setTrackPosition(secondRequest.trackKey, { kind = "seconds", value = 4 }),
			"unresolved absolute was rejected"
		)
		assert(secondBackend:offsetTrackPosition(secondRequest.trackKey, 2), "first post-absolute offset was rejected")
		assert(
			secondBackend:offsetTrackPosition(secondRequest.trackKey, -1),
			"second post-absolute offset was rejected"
		)
		secondAnimator.tracks[1]:setLength(10)
		secondBackend:apply(0, { secondRequest })
		assert(
			#secondAnimator.tracks[1].calls.positionWrites == 1
				and secondAnimator.tracks[1].calls.positionWrites[1] == 5,
			"post-absolute offsets did not compose from the new base"
		)

		local thirdBackend, thirdAnimator = newBackend(0)
		local thirdRequest = newRequest()
		thirdBackend:apply(0, { thirdRequest })
		assert(thirdBackend:offsetTrackPosition(thirdRequest.trackKey, 7), "superseded unresolved offset was rejected")
		assert(
			thirdBackend:setTrackPosition(thirdRequest.trackKey, { kind = "seconds", value = 3 }),
			"final unresolved absolute was rejected"
		)
		thirdAnimator.tracks[1]:setLength(10)
		thirdBackend:apply(0, { thirdRequest })
		assert(
			#thirdAnimator.tracks[1].calls.positionWrites == 1 and thirdAnimator.tracks[1].calls.positionWrites[1] == 3,
			"final absolute retained a superseded offset"
		)
	end)

	test("unresolved reverse start applies combined offset before retained speed", function(): ()
		local backend, animator = newBackend(0)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({ speed = -1, initialPosition = { kind = "normalized", value = 1 } })
		backend:apply(0, { request })
		local track = animator.tracks[1]
		local generation = backend:getDebugSnapshot().tracks[1].details.generation
		assert(backend:offsetTrackPosition(request.trackKey, -2), "first unresolved reverse offset was rejected")
		assert(backend:offsetTrackPosition(request.trackKey, 0.5), "second unresolved reverse offset was rejected")
		backend:apply(0, { request })
		assert(
			#track.calls.order == 1 and track.calls.order[1].operation == "Play" and track.calls.order[1].value == 0,
			"unresolved reverse offsets escaped the zero-speed hold"
		)

		track:setLength(10)
		backend:apply(0, { request })
		backend:apply(0, { request })
		local snapshot = backend:getDebugSnapshot().tracks[1]
		assert(#track.calls.order == 3, "unresolved reverse offset resolution emitted extra native operations")
		assert(
			track.calls.order[2].operation == "TimePosition" and track.calls.order[2].value == 8.5,
			"unresolved reverse offsets did not position once before speed"
		)
		assert(
			track.calls.order[3].operation == "AdjustSpeed" and track.calls.order[3].value == -1,
			"unresolved reverse offsets adopted the wrong retained speed"
		)
		assert(
			#track.calls.positionWrites == 1 and track.calls.adjustSpeed == 1,
			"unresolved reverse offsets reapplied position or speed"
		)
		assert(
			animator.loadCount == 1 and track.calls.play == 1,
			"unresolved reverse offsets replayed or replaced playback"
		)
		assert(
			snapshot.details.generation == generation and snapshot.details.lifecycle == "active" and events == 0,
			"unresolved reverse offsets changed generation or completed"
		)
	end)

	test("pending offsets cannot escape a replaced generation", function(): ()
		local backend, animator = newBackend(0)
		local oldRequest = newRequest({ initialPosition = { kind = "normalized", value = 0.5 } })
		backend:apply(0, { oldRequest })
		local oldTrack = animator.tracks[1]
		local oldGeneration = backend:getDebugSnapshot().tracks[1].details.generation
		assert(backend:offsetTrackPosition(oldRequest.trackKey, 2), "old generation pending offset was rejected")

		local replacement = newRequest({ clip = "wave", initialPosition = { kind = "normalized", value = 0.25 } })
		backend:apply(0, { replacement })
		local newTrack = animator.tracks[2]
		local newGeneration = backend:getDebugSnapshot().tracks[2].details.generation
		assert(newGeneration > oldGeneration, "replacement reused the pending-offset generation")
		assert(backend:offsetTrackPosition(replacement.trackKey, 1), "replacement generation offset was rejected")
		oldTrack:setLength(10)
		oldTrack:fireStopped()
		oldTrack:fireEnded()
		assert(
			#oldTrack.calls.positionWrites == 0 and oldTrack.calls.destroy == 1,
			"retired pending offset wrote or leaked"
		)

		newTrack:setLength(8)
		backend:apply(0, { replacement })
		backend:apply(0, { replacement })
		local snapshot = backend:getDebugSnapshot().tracks[1]
		assert(
			#newTrack.calls.positionWrites == 1 and newTrack.calls.positionWrites[1] == 3,
			"replacement did not resolve only its own base and offset"
		)
		assert(
			snapshot.details.generation == newGeneration and snapshot.details.lifecycle == "active",
			"stale pending offset changed replacement ownership"
		)
	end)

	test("relative completion callback may replace offset clear and destroy", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		local replacement = newRequest({ clip = "wave", speed = 0, initialPosition = { kind = "seconds", value = 2 } })
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
			assert(
				not backend:offsetTrackPosition(request.trackKey, -1),
				"relative completion callback revived its tombstone"
			)
			backend:apply(0, { replacement })
			assert(
				backend:offsetTrackPosition(replacement.trackKey, 1),
				"relative completion callback could not offset its replacement"
			)
			backend:clear()
			backend:destroy()
		end)
		backend:apply(0, { request })
		animator.tracks[1]:setEngineTimePosition(9)
		assert(backend:offsetTrackPosition(request.trackKey, 2), "relative completion command was rejected")

		assert(events == 1 and animator.loadCount == 2, "relative completion reentry duplicated or missed replacement")
		assert(
			animator.tracks[2].calls.positionWrites[1] == 2 and animator.tracks[2].calls.positionWrites[2] == 3,
			"relative completion reentry positioned the replacement incorrectly"
		)
		assert(
			animator.tracks[1].calls.destroy == 1 and animator.tracks[2].calls.destroy == 1,
			"relative completion reentry leaked physical generations"
		)
	end)

	test("throwing relative completion subscriber preserves cleanup and later dispatch", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		local failedCalls = 0
		local releaseFailing = backend:bindToTrackCompleted(function()
			failedCalls += 1
			error("expected relative completion failure")
		end)
		backend:apply(0, { request })
		local oldTrack = animator.tracks[1]
		oldTrack:setEngineTimePosition(9)
		local completed, resultOrError = pcall(function(): unknown
			backend:offsetTrackPosition(request.trackKey, 2)
			return nil
		end)
		assert(not completed, "throwing relative completion subscriber did not propagate")
		assert(
			string.find(tostring(resultOrError), "expected relative completion failure", 1, true) ~= nil,
			"relative completion propagated the wrong error"
		)
		assert(
			failedCalls == 1 and backend:getDebugSnapshot().tracks[1].details.lifecycle == "completed",
			"throwing relative completion lost committed state"
		)

		releaseFailing()
		oldTrack:fireEnded()
		assert(
			oldTrack.calls.destroy == 1 and animator.animations[1].destroyed,
			"throwing relative completion prevented physical cleanup"
		)
		local laterEvents = 0
		backend:bindToTrackCompleted(function()
			laterEvents += 1
		end)
		local replacement = newRequest({ clip = "wave", state = "later" })
		backend:apply(0, { replacement })
		local replacementTrack = animator.tracks[2]
		replacementTrack:setEngineTimePosition(9)
		assert(backend:offsetTrackPosition(replacement.trackKey, 2), "later relative completion was rejected")
		oldTrack:fireStopped()
		oldTrack:fireEnded()
		assert(
			laterEvents == 1 and replacementTrack.calls.destroy == 0,
			"stale failed generation affected later relative completion"
		)
	end)

	test("pending live positioning resolves and permanently supersedes a pending initial position", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest({ initialPosition = { kind = "normalized", value = 0.25 } })
		backend:apply(0, { request })
		local track = animator.tracks[1]
		assert(
			backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 6 }),
			"pending live position was rejected"
		)
		assert(#track.calls.positionWrites == 0, "zero-length live position wrote early")
		track:setLength(10)
		backend:apply(0, { request })
		backend:apply(0, { request })
		assert(
			#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 6,
			"pending initial position won after live supersession"
		)
	end)

	test("invalid live positions reject before changing pending state", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 2 } })
		backend:apply(0, { request })
		expectError(function()
			backend:setTrackPosition(request.trackKey, { kind = "seconds", value = -1 })
		end, "invalid live position was accepted")
		animator.tracks[1]:setLength(10)
		backend:apply(0, { request })
		assert(
			animator.tracks[1].calls.positionWrites[1] == 2,
			"invalid live command mutated the pending initial position"
		)
	end)

	test("terminal live positioning completes once after committing its tombstone", function(): ()
		for _, value in { 10, 12 } do
			local backend, animator = newBackend(10)
			local request = newRequest()
			local events = 0
			local committed = false
			backend:bindToTrackCompleted(function(event)
				events += 1
				local snapshot = backend:getDebugSnapshot()
				committed = event.trackKey == request.trackKey
					and #snapshot.tracks == 1
					and snapshot.tracks[1].details.lifecycle == "completed"
			end)
			backend:apply(0, { request })
			assert(
				backend:setTrackPosition(request.trackKey, { kind = "seconds", value = value }),
				"terminal position was rejected"
			)
			assert(events == 1 and committed, "terminal completion dispatched before tombstone commit")
			assert(
				not backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }),
				"completed key was revived"
			)
			backend:apply(0, { request })
			animator.tracks[1]:fireStopped()
			assert(events == 1 and animator.loadCount == 1, "completed request replayed or emitted twice")
			animator.tracks[1]:fireEnded()
			local tombstone = backend:getDebugSnapshot().tracks[1]
			assert(
				tombstone.details.lifecycle == "completed" and not tombstone.details.physicalPresent,
				"Ended removed the tombstone or retained physics"
			)
		end
	end)

	test("looping live positions wrap and canonicalize without completion", function(): ()
		local backend, animator = newBackend(10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({ looped = true })
		backend:apply(0, { request })
		assert(
			backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 22 }),
			"loop seconds position was rejected"
		)
		assert(
			backend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 }),
			"loop normalized position was rejected"
		)
		local writes = animator.tracks[1].calls.positionWrites
		assert(writes[1] == 2 and writes[2] == 0, "loop positions did not wrap or canonicalize")
		assert(
			events == 0 and backend:getDebugSnapshot().tracks[1].details.lifecycle == "active",
			"loop position completed playback"
		)
	end)

	test("active looped Ended cleans ownership and rematerializes a guarded generation", function(): ()
		local backend, animator = newBackend(10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({ looped = true })
		backend:apply(0, { request })
		local oldTrack = animator.tracks[1]
		local oldGeneration = backend:getDebugSnapshot().tracks[1].details.generation

		oldTrack:fireEnded()
		assert(events == 0, "active looped Ended emitted completion")
		assert(
			oldTrack.calls.destroy == 1 and animator.animations[1].destroyed,
			"active looped Ended did not clean physical ownership once"
		)
		assert(oldTrack.Stopped:getConnectionCount() == 0, "active looped Ended leaked Stopped")
		assert(oldTrack.Ended:getConnectionCount() == 0, "active looped Ended leaked Ended")
		assert(#backend:getDebugSnapshot().tracks == 0, "active looped Ended left stale lifecycle or debug ownership")

		backend:apply(0, { request })
		local newTrack = animator.tracks[2]
		local replacement = backend:getDebugSnapshot().tracks[1]
		assert(animator.loadCount == 2, "unchanged looped request did not rematerialize")
		assert(replacement.details.lifecycle == "active", "rematerialized looped generation was not active")
		assert(replacement.details.physicalPresent, "rematerialized looped generation had no physical ownership")
		assert(replacement.details.generation > oldGeneration, "rematerialized looped request reused its generation")

		oldTrack:fireStopped()
		oldTrack:fireEnded()
		local afterStaleSignals = backend:getDebugSnapshot().tracks[1]
		assert(
			events == 0 and oldTrack.calls.destroy == 1,
			"stale looped signals completed or recleaned the old generation"
		)
		assert(newTrack.calls.destroy == 0, "stale looped signals cleaned the replacement")
		assert(
			afterStaleSignals.details.generation == replacement.details.generation,
			"stale looped signals replaced active ownership"
		)
	end)

	test("positioning returns false for missing, retiring, completed, and destroyed keys", function(): ()
		local backend = newBackend(10)
		assert(not backend:setTrackPosition("missing", { kind = "seconds", value = 1 }), "missing key was accepted")
		local request = newRequest()
		backend:apply(0, { request })
		backend:apply(0, {})
		assert(
			not backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }),
			"retiring key was accepted"
		)

		local completedBackend = newBackend(10)
		completedBackend:apply(0, { request })
		completedBackend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 })
		assert(
			not completedBackend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }),
			"completed key was accepted"
		)
		completedBackend:destroy()
		assert(
			not completedBackend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }),
			"destroyed backend accepted a key"
		)
	end)

	test("natural completion dispatches once, cleans physics on Ended, and retains a tombstone", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		local events = {} :: { any }
		backend:bindToTrackCompleted(function(event)
			events[#events + 1] = event
		end)
		backend:apply(0, { request })
		local track = animator.tracks[1]
		track:fireStopped()
		track:fireStopped()
		assert(#events == 1, "natural completion did not dispatch exactly once")
		assert(events[1].layer == request.layer and events[1].state == request.state, "completion identity was wrong")
		track:fireEnded()
		assert(track.calls.destroy == 1 and animator.animations[1].destroyed, "Ended did not clean physical ownership")
		backend:apply(0, { request })
		assert(animator.loadCount == 1 and #events == 1, "unchanged tombstoned request replayed")
	end)

	test("Ended-before-Stopped cleans completion before rethrowing listener errors", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		local callbacks = 0
		local releaseFailing = backend:bindToTrackCompleted(function()
			callbacks += 1
			error("expected Ended completion failure")
		end)
		backend:apply(0, { request })
		local track = animator.tracks[1]
		local ended, resultOrError = pcall(function(): unknown
			track:fireEnded()
			return nil
		end)
		assert(not ended, "Ended completion listener error did not propagate")
		assert(
			string.find(tostring(resultOrError), "expected Ended completion failure", 1, true) ~= nil,
			"Ended propagated the wrong completion listener error"
		)
		assert(callbacks == 1, "Ended completion listener ran more than once")

		local snapshot = backend:getDebugSnapshot()
		assert(#snapshot.tracks == 1, "Ended completion did not preserve exactly one tombstone")
		assert(snapshot.tracks[1].details.lifecycle == "completed", "Ended completion lost its tombstone lifecycle")
		assert(
			not snapshot.tracks[1].details.physicalPresent,
			"Ended completion retained physical ownership after error"
		)
		assert(
			track.calls.destroy == 1 and animator.animations[1].destroyed,
			"Ended completion did not destroy physical objects once"
		)
		assert(track.Stopped:getConnectionCount() == 0, "Ended completion leaked Stopped after error")
		assert(track.Ended:getConnectionCount() == 0, "Ended completion leaked Ended after error")
		local oldGeneration = snapshot.tracks[1].details.generation

		releaseFailing()
		local laterEvents = {} :: { any }
		backend:bindToTrackCompleted(function(event)
			laterEvents[#laterEvents + 1] = event
		end)
		local replacementRequest = newRequest({ clip = "wave", state = "replacement" })
		backend:apply(0, { replacementRequest })
		local replacementTrack = animator.tracks[2]
		local replacementSnapshot = backend:getDebugSnapshot()
		assert(animator.loadCount == 2, "different-clip presence did not materialize a replacement generation")
		assert(#replacementSnapshot.tracks == 1, "replacement generation did not own exactly one lifecycle entry")
		assert(replacementSnapshot.tracks[1].trackKey == request.trackKey, "replacement changed the track key")
		assert(replacementSnapshot.tracks[1].details.lifecycle == "active", "replacement generation was not active")
		assert(
			replacementSnapshot.tracks[1].details.physicalPresent,
			"replacement generation had no physical ownership"
		)
		assert(
			replacementSnapshot.tracks[1].details.generation > oldGeneration,
			"replacement reused the failed generation"
		)
		assert(#laterEvents == 0, "replacement materialization emitted completion")

		track:fireStopped()
		track:fireEnded()
		local afterStaleSignals = backend:getDebugSnapshot()
		assert(
			callbacks == 1 and track.calls.destroy == 1,
			"stale signals redispatched or recleaned the failed generation"
		)
		assert(#laterEvents == 0, "stale old signals completed the replacement")
		assert(
			replacementTrack.calls.destroy == 0 and replacementTrack.IsPlaying,
			"stale old signals mutated or cleaned the replacement"
		)
		assert(
			afterStaleSignals.tracks[1].details.generation == replacementSnapshot.tracks[1].details.generation,
			"stale old signals changed replacement ownership"
		)
		assert(afterStaleSignals.tracks[1].details.physicalPresent, "stale old signals removed replacement physics")

		replacementTrack:fireEnded()
		assert(#laterEvents == 1, "replacement completion did not dispatch exactly once")
		assert(
			laterEvents[1].trackKey == request.trackKey and laterEvents[1].state == "replacement",
			"replacement completion identity was wrong"
		)
		local replacementCompleted = backend:getDebugSnapshot()
		assert(
			replacementCompleted.tracks[1].details.lifecycle == "completed",
			"replacement completion did not commit a tombstone"
		)
		assert(
			not replacementCompleted.tracks[1].details.physicalPresent,
			"replacement completion retained physical ownership"
		)
		assert(
			replacementTrack.calls.destroy == 1 and animator.animations[2].destroyed,
			"replacement completion did not clean physical objects once"
		)
		replacementTrack:fireStopped()
		replacementTrack:fireEnded()
		assert(
			#laterEvents == 1 and replacementTrack.calls.destroy == 1,
			"replacement stale signals duplicated completion or cleanup"
		)
	end)

	test("completion produced during apply waits for the complete batch", function(): ()
		local backend = newBackend(10)
		local terminal = newRequest({ trackKey = "terminal", initialPosition = { kind = "normalized", value = 1 } })
		local companion = newRequest({ trackKey = "companion", clip = "wave" })
		local sawCommittedBatch = false
		backend:bindToTrackCompleted(function()
			local snapshot = backend:getDebugSnapshot()
			local lifecycles = {} :: { [string]: string }
			for _, track in snapshot.tracks do
				lifecycles[track.trackKey] = track.details.lifecycle
			end
			sawCommittedBatch = lifecycles.terminal == "completed" and lifecycles.companion == "active"
		end)
		backend:apply(0, { terminal, companion })
		assert(sawCommittedBatch, "initial terminal completion dispatched before the batch committed")
	end)

	test("tombstones retire on omission, different clip, force restart, clear, and destroy", function(): ()
		local request = newRequest({ initialPosition = { kind = "normalized", value = 1 } })

		local omissionBackend, omissionAnimator = newBackend(10)
		omissionBackend:apply(0, { request })
		omissionBackend:apply(0, { request })
		assert(omissionAnimator.loadCount == 1, "same tombstoned request replayed")
		omissionBackend:apply(0, {})
		omissionBackend:apply(0, { request })
		assert(omissionAnimator.loadCount == 2, "omission did not retire the tombstone")

		local replacementBackend, replacementAnimator = newBackend(10)
		replacementBackend:apply(0, { request })
		replacementBackend:apply(0, { newRequest({ clip = "wave" }) })
		assert(replacementAnimator.loadCount == 2, "different clip did not replace the tombstone")

		local restartBackend, restartAnimator = newBackend(10)
		restartBackend:apply(0, { request })
		restartBackend:apply(0, { newRequest({ forceRestart = true }) })
		assert(restartAnimator.loadCount == 2, "force restart did not replace the tombstone")

		local clearBackend, clearAnimator = newBackend(10)
		clearBackend:apply(0, { request })
		clearBackend:clear()
		assert(
			#clearBackend:getDebugSnapshot().tracks == 0 and clearAnimator.tracks[1].calls.destroy == 1,
			"clear retained tombstone or physics"
		)

		local destroyBackend, destroyAnimator = newBackend(10)
		destroyBackend:apply(0, { request })
		destroyBackend:destroy()
		assert(
			#destroyBackend:getDebugSnapshot().tracks == 0 and destroyAnimator.tracks[1].calls.destroy == 1,
			"destroy retained tombstone or physics"
		)
	end)

	test("explicit retirement suppresses completion for every retirement cause", function(): ()
		local function runCase(action: (backend: any, request: any) -> (), label: string): ()
			local backend, animator = newBackend(10)
			local events = 0
			backend:bindToTrackCompleted(function()
				events += 1
			end)
			local request = newRequest()
			backend:apply(0, { request })
			local oldTrack = animator.tracks[1]
			action(backend, request)
			oldTrack:fireStopped()
			assert(events == 0, label .. " emitted completion")
		end

		runCase(function(backend, _request)
			backend:stopLayer("base", 0.4)
		end, "stopLayer")
		runCase(function(backend, _request)
			backend:apply(0, {})
		end, "disappearance")
		runCase(function(backend, _request)
			backend:apply(0, { newRequest({ clip = "wave" }) })
		end, "replacement")
		runCase(function(backend, _request)
			backend:apply(0, { newRequest({ forceRestart = true }) })
		end, "forceRestart")
		runCase(function(backend, _request)
			backend:clear()
		end, "clear")
		runCase(function(backend, _request)
			backend:destroy()
		end, "destroy")
	end)

	test("same-key replacement and reappearance coexist safely with old fading generations", function(): ()
		local backend, animator = newBackend(10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest()
		backend:apply(0, { request })
		local oldTrack = animator.tracks[1]
		backend:apply(0, {})
		backend:apply(0, { request })
		local newTrack = animator.tracks[2]
		assert(
			backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 3 }),
			"new active generation was not addressable"
		)
		oldTrack:fireStopped()
		oldTrack:fireEnded()
		assert(
			events == 0 and oldTrack.calls.destroy == 1,
			"stale old signals completed or leaked the retired generation"
		)
		assert(
			newTrack.calls.destroy == 0 and newTrack.TimePosition == 3,
			"stale old signals mutated the new generation"
		)

		local replacement = newRequest({ clip = "wave", fadeTime = 0.6 })
		backend:apply(0, { replacement })
		assert(
			animator.loadCount == 3 and newTrack.calls.stopFades[1] == 0.6,
			"different-clip replacement did not use incoming fade"
		)
	end)

	test("non-zero fade waits for Ended while zero fade and inactive retirement clean immediately", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply(0, { request })
		local fadingTrack = animator.tracks[1]
		backend:stopLayer("base", 0.5)
		assert(
			fadingTrack.calls.stopFades[1] == 0.5 and fadingTrack.calls.destroy == 0,
			"non-zero fade cleaned before Ended"
		)
		assert(
			fadingTrack.Stopped:getConnectionCount() == 0 and fadingTrack.Ended:getConnectionCount() == 1,
			"retirement retained the wrong signal ownership"
		)
		fadingTrack:fireEnded()
		assert(fadingTrack.calls.destroy == 1 and animator.animations[1].destroyed, "Ended did not own final cleanup")
		assert(fadingTrack.Ended:getConnectionCount() == 0, "Ended connection leaked after cleanup")

		local zeroBackend, zeroAnimator = newBackend(10)
		zeroBackend:apply(0, { request })
		zeroBackend:stopLayer("base", 0)
		assert(zeroAnimator.tracks[1].calls.destroy == 1, "zero-fade retirement did not clean immediately")

		local inactiveBackend, inactiveAnimator = newBackend(10)
		inactiveBackend:apply(0, { request })
		inactiveAnimator.tracks[1]:setEnginePlaying(false)
		inactiveBackend:stopLayer("base", 0.5)
		assert(inactiveAnimator.tracks[1].calls.destroy == 1, "inactive retirement did not clean immediately")
	end)

	test("completion listener dispatch snapshots additions and removals", function(): ()
		local backend = newBackend(10)
		local calls = {} :: { string }
		local releaseFirst = function() end
		local releaseSecond = function() end
		local added = false
		releaseFirst = backend:bindToTrackCompleted(function()
			calls[#calls + 1] = "first"
			releaseFirst()
			releaseSecond()
			if not added then
				added = true
				backend:bindToTrackCompleted(function()
					calls[#calls + 1] = "added"
				end)
			end
		end)
		releaseSecond = backend:bindToTrackCompleted(function()
			calls[#calls + 1] = "second"
		end)

		local request = newRequest()
		backend:apply(0, { request })
		backend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 })
		request.forceRestart = true
		request.initialPosition = { kind = "normalized", value = 1 }
		backend:apply(0, { request })
		assert(
			table.concat(calls, ",") == "first,second,added",
			"listener mutation changed the active dispatch snapshot"
		)
	end)

	test("throwing completion listener propagates without wedging later dispatch", function(): ()
		local backend = newBackend(10)
		local request = newRequest()
		local failedCalls = 0
		local releaseFailing = backend:bindToTrackCompleted(function()
			failedCalls += 1
			error("expected completion callback failure")
		end)
		backend:apply(0, { request })
		local completed, resultOrError = pcall(function(): unknown
			backend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 })
			return nil
		end)
		assert(not completed, "throwing completion listener did not propagate its error")
		assert(
			string.find(tostring(resultOrError), "expected completion callback failure", 1, true) ~= nil,
			"completion callback propagated the wrong error"
		)
		assert(failedCalls == 1, "failed completion event was duplicated")

		releaseFailing()
		local laterEvents = {} :: { any }
		backend:bindToTrackCompleted(function(event)
			laterEvents[#laterEvents + 1] = event
		end)
		local laterRequest = newRequest({ state = "later", forceRestart = true })
		backend:apply(0, { laterRequest })
		assert(#laterEvents == 0, "failed completion event remained queued")
		backend:setTrackPosition(laterRequest.trackKey, { kind = "normalized", value = 1 })
		assert(
			#laterEvents == 1 and laterEvents[1].state == "later",
			"later completed generation did not dispatch exactly once"
		)
	end)

	test("completion callback may position, clear, and destroy without duplicates or leaks", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
			assert(
				not backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }),
				"callback revived its completed key"
			)
			backend:stopLayer("base", 0)
			backend:clear()
			backend:destroy()
		end)
		backend:apply(0, { request })
		backend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 })
		animator.tracks[1]:fireStopped()
		animator.tracks[1]:fireEnded()
		assert(events == 1, "re-entrant cleanup duplicated completion")
		assert(
			animator.tracks[1].calls.destroy == 1 and animator.animations[1].destroyed,
			"re-entrant cleanup leaked physics"
		)
		assert(animator.tracks[1].Stopped:getConnectionCount() == 0, "re-entrant cleanup leaked Stopped")
		assert(animator.tracks[1].Ended:getConnectionCount() == 0, "re-entrant cleanup leaked Ended")
	end)

	return testCount
end)

transformed.cleanup()
assert(ok, result)

return result

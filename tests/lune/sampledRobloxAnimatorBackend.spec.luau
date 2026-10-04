--!strict
--!optimize 2

local requireAny = require :: any
local process = requireAny("@lune/process")
local ModuleLoader = requireAny(process.cwd .. "/tests/lune/lib/moduleLoader.luau")
local fakeRobloxPath = (process.cwd:gsub("\\", "/")) .. "/tests/lune/fixtures/fakeRoblox.luau"
local FakeRoblox = requireAny(fakeRobloxPath)

local transformed = ModuleLoader.write({
	sourceRoot = "src",
	tempDir = ".tmp/lune-sampled-roblox-backend",
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

local function at(request: any, position: number, rate: number?): any
	request.timePosition = position
	request.timeRate = if rate ~= nil then rate else 1
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
			error(`sampled roblox backend: {name}: {failure}`, 0)
		end
		testCount += 1
		print(`PASS sampled roblox backend: {name}`)
	end

	local function newBackend(mode: string?, length: number?): (any, any)
		local animator = FakeRoblox.newAnimator(length)
		local backend = RobloxAnimatorBackend.new({
			animator = animator,
			positionMode = mode,
			resolveAssetId = function(_clip): number
				return 123
			end,
		})
		return backend, animator
	end

	test("reports a fixed backend-level position strategy", function(): ()
		local nativeBackend = newBackend(nil)
		local sampledBackend = newBackend("sampledPosition")
		assert(nativeBackend:getCapabilities().positionMode == "nativeRate", "nativeRate was not the default")
		assert(sampledBackend:getCapabilities().positionMode == "sampledPosition", "sampled mode was not reported")
		expectError(function()
			newBackend("contentOption")
		end, "invalid position strategy was accepted")
	end)

	test("samples forward held reverse and nonlinear positions literally", function(): ()
		local backend, animator = newBackend("sampledPosition", 100)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 2 }, speed = 2 })
		backend:apply(10, { at(request, 10, 1) })
		backend:apply(11, { at(request, 12, 1) })
		backend:apply(12, { at(request, 12, 0) })
		backend:apply(13, { at(request, 11, -1) })
		backend:apply(14, { at(request, 14, 3) })
		local track = animator.tracks[1]
		assert(track.calls.playSpeeds[1] == 0, "sampled playback started with a native rate")
		assert(track.calls.adjustSpeed == 0, "sampled playback delegated phase to AdjustSpeed")
		assert(table.concat(track.calls.positionWrites, ",") == "2,6,6,4,10", "sampled position was not literal")
	end)

	test("rebases before changing signed speed", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 1 }, speed = 1 })
		backend:apply(0, { at(request, 0) })
		backend:apply(2, { at(request, 2) })
		request.speed = -2
		backend:apply(3, { at(request, 2) })
		backend:apply(4, { at(request, 2.5) })
		local writes = animator.tracks[1].calls.positionWrites
		assert(writes[#writes - 1] == 3 and writes[#writes] == 2, "speed pivot did not preserve then reverse phase")
	end)

	test("classifies sampled boundaries with composed time direction", function(): ()
		local inwardBackend, inwardAnimator = newBackend("sampledPosition", 10)
		local inwardEvents = 0
		inwardBackend:bindToTrackCompleted(function()
			inwardEvents += 1
		end)
		local inwardRequest = newRequest({ initialPosition = { kind = "seconds", value = 9 }, speed = 1 })
		inwardBackend:apply(0, { at(inwardRequest, 0, 1) })
		inwardBackend:apply(1, { at(inwardRequest, 1, -1) })
		inwardBackend:apply(2, { at(inwardRequest, 0, -1) })
		assert(inwardEvents == 0, "inward boundary completed without composed direction")
		assert(
			inwardAnimator.tracks[1].calls.positionWrites[#inwardAnimator.tracks[1].calls.positionWrites] == 9,
			"reverse time did not leave the boundary"
		)

		local outwardBackend = newBackend("sampledPosition", 10)
		local outwardEvents = 0
		outwardBackend:bindToTrackCompleted(function()
			outwardEvents += 1
		end)
		local outwardRequest = newRequest({ initialPosition = { kind = "normalized", value = 1 }, timeRate = 0 })
		outwardBackend:apply(0, { outwardRequest })
		outwardBackend:apply(0, { at(outwardRequest, 0, 1) })
		assert(outwardEvents == 1, "outward boundary did not use composed time direction")
	end)

	test("wraps looping phase without completing", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({
			looped = true,
			speed = 2,
			initialPosition = { kind = "seconds", value = 9 },
		})
		backend:apply(0, { at(request, 0) })
		backend:apply(1, { at(request, 1) })
		local writes = animator.tracks[1].calls.positionWrites
		assert(writes[#writes] == 1, "looping sampled phase did not wrap")
		assert(events == 0 and #backend:getDebugSnapshot().tracks == 1, "looping sampled phase completed")
	end)

	test("latches non-looping completion from sampled phase", function(): ()
		local backend, animator = newBackend("sampledPosition", 5)
		local events = {} :: { any }
		backend:bindToTrackCompleted(function(event)
			events[#events + 1] = event
		end)
		local request = newRequest({ speed = 1 })
		backend:apply(0, { at(request, 0) })
		backend:apply(5, { at(request, 5) })
		backend:apply(5, { at(request, 5) })
		assert(#events == 1 and events[1].trackKey == request.trackKey, "sampled completion was not exactly once")
		assert(#animator.tracks[1].calls.positionWrites == 2, "completed tombstone was sampled again")
		local completedTrack = backend:getDebugSnapshot().tracks[1]
		assert(completedTrack.details.lifecycle == "completed", "completion did not tombstone")
		assert(completedTrack.details.physicalPresent == false, "sampled completion retained a frozen physical track")
	end)

	test("synchronous position commands rebase the active physical generation", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local request = newRequest()
		backend:apply(0, { at(request, 0) })
		backend:apply(2, { at(request, 2) })
		assert(backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 5 }), "set position was rejected")
		backend:apply(3, { at(request, 3) })
		assert(backend:offsetTrackPosition(request.trackKey, -2), "offset position was rejected")
		backend:apply(3, { at(request, 3) })
		backend:apply(4, { at(request, 4) })
		local writes = animator.tracks[1].calls.positionWrites
		assert(
			writes[#writes - 2] == 4 and writes[#writes - 1] == 4 and writes[#writes] == 5,
			"physical command anchor drifted"
		)
	end)

	test("accrues phase while clip length is unresolved", function(): ()
		local backend, animator = newBackend("sampledPosition", 0)
		local request = newRequest({ speed = 1 })
		backend:apply(0, { at(request, 0) })
		backend:apply(2, { at(request, 2) })
		request.speed = 2
		backend:apply(3, { at(request, 2) })
		assert(#animator.tracks[1].calls.positionWrites == 0, "unknown length received a physical write")
		animator.tracks[1]:setLength(10)
		backend:apply(4, { at(request, 3) })
		assert(animator.tracks[1].calls.positionWrites[1] == 4, "unresolved phase was not rebased across speed change")

		local positionedBackend, positionedAnimator = newBackend("sampledPosition", 0)
		local positionedRequest = newRequest()
		positionedBackend:apply(0, { at(positionedRequest, 0) })
		positionedBackend:apply(2, { at(positionedRequest, 2) })
		assert(
			positionedBackend:setTrackPosition(positionedRequest.trackKey, { kind = "seconds", value = 5 }),
			"unresolved position command was rejected"
		)
		positionedAnimator.tracks[1]:setLength(10)
		positionedBackend:apply(3, { at(positionedRequest, 3) })
		assert(
			positionedAnimator.tracks[1].calls.positionWrites[1] == 6,
			"unresolved position command did not anchor at the last accepted time position"
		)
	end)

	test("ignores native stop signals and restores sampled playback", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local request = newRequest()
		backend:apply(0, { at(request, 0) })
		local track = animator.tracks[1]
		track:fireStopped()
		assert(
			backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 2 }),
			"native stop stole active ownership"
		)
		backend:apply(1, { at(request, 1) })
		assert(
			track.calls.play == 2 and track.calls.playSpeeds[2] == 0,
			"sampled playback was not restored at zero rate"
		)
		assert(
			track.calls.positionWrites[#track.calls.positionWrites] == 3,
			"restored sampled phase used the wrong anchor"
		)
	end)

	test("rejects invalid and backward backend coordinates before mutation", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local request = newRequest()
		for _, invalid in { 0 / 0, math.huge, -math.huge } do
			expectError(function()
				backend:apply(invalid, { request })
			end, "invalid backend coordinate was accepted")
		end
		assert(animator.loadCount == 0, "invalid coordinate materialized playback")
		backend:apply(5, { at(request, 5) })
		expectError(function()
			backend:apply(4, { at(request, 4) })
		end, "backward backend coordinate was accepted")
		assert(#animator.tracks[1].calls.positionWrites == 1, "backward coordinate changed physical phase")
	end)

	test("rejects derived sampled overflow atomically and keeps completion dispatch live", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({ speed = 1 })
		backend:apply(-1e308, { at(request, -1e308) })
		expectError(function()
			backend:apply(1e308, { at(request, 1e308) })
		end, "overflowing sampled elapsed value was accepted")
		assert(#animator.tracks[1].calls.positionWrites == 1, "overflowing sample mutated physical position")

		backend:apply(0, { at(request, 0) })
		assert(events == 1, "failed sampled arithmetic poisoned the accepted coordinate or completion dispatch")
	end)

	test("restores apply depth after resolver failures", function(): ()
		local animator = FakeRoblox.newAnimator(1)
		local failResolution = true
		local backend = RobloxAnimatorBackend.new({
			animator = animator,
			positionMode = "sampledPosition",
			resolveAssetId = function(_clip): number
				if failResolution then
					failResolution = false
					error("injected resolver failure")
				end
				return 123
			end,
		})
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest()
		expectError(function()
			backend:apply(0, { request })
		end, "resolver failure did not escape apply")

		backend:apply(0, { at(request, 0) })
		backend:apply(1, { at(request, 1) })
		assert(events == 1, "resolver failure permanently suppressed later completion dispatch")
	end)

	test("resolver clear invalidates in-flight materialization", function(): ()
		local animator = FakeRoblox.newAnimator(10)
		local backend: any = nil
		local clearDuringResolution = true
		backend = RobloxAnimatorBackend.new({
			animator = animator,
			positionMode = "sampledPosition",
			resolveAssetId = function(_clip): number
				if clearDuringResolution then
					clearDuringResolution = false
					backend:clear()
				end
				return 123
			end,
		})
		local request = newRequest()

		backend:apply(0, { request })
		assert(
			animator.loadCount == 0 and #backend:getDebugSnapshot().tracks == 0,
			"clear was undone by materialization"
		)
		backend:apply(0, { request })
		assert(animator.loadCount == 1, "backend did not recover after resolver clear")
	end)

	test("nativeRate composes signed and zero time rates without position churn", function(): ()
		local backend, animator = newBackend("nativeRate", 10)
		local request =
			newRequest({ speed = -1, timeRate = -0.5, initialPosition = { kind = "normalized", value = 0.5 } })
		backend:apply(0, { request })
		backend:apply(1, { request })
		local track = animator.tracks[1]
		assert(track.calls.playSpeeds[1] == 0.5, "nativeRate did not compose -1 * -0.5")
		assert(track.calls.adjustSpeed == 0, "unchanged effective native speed churned properties")
		assert(#track.calls.positionWrites == 1, "nativeRate set position every update")
		request.timeRate = 0
		backend:apply(2, { request })
		assert(track.calls.adjustSpeed == 1 and track.calls.speeds[1] == 0, "zero time rate did not pause natively")
		assert(#track.calls.positionWrites == 1, "native rate change wrote TimePosition")
	end)

	return testCount
end)

transformed.cleanup()
assert(ok, result)

return result

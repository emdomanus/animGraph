--!strict

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

	test("samples physical position from one phase anchor every update", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 2 }, speed = 2 })
		backend:apply(10, { request })
		backend:apply(11, { request })
		backend:apply(11, { request })
		local track = animator.tracks[1]
		assert(track.calls.playSpeeds[1] == 0, "sampled playback started with a native rate")
		assert(track.calls.adjustSpeed == 0, "sampled playback delegated phase to AdjustSpeed")
		assert(table.concat(track.calls.positionWrites, ",") == "2,4,4", "sampled phase did not use its anchor")
	end)

	test("rebases before changing signed speed", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 1 }, speed = 1 })
		backend:apply(0, { request })
		backend:apply(2, { request })
		request.speed = -2
		backend:apply(2, { request })
		backend:apply(2.5, { request })
		local writes = animator.tracks[1].calls.positionWrites
		assert(writes[#writes - 1] == 3 and writes[#writes] == 2, "speed pivot did not preserve then reverse phase")
	end)

	test("classifies a rebased boundary with the new desired direction", function(): ()
		local inwardBackend, inwardAnimator = newBackend("sampledPosition", 10)
		local inwardEvents = 0
		inwardBackend:bindToTrackCompleted(function()
			inwardEvents += 1
		end)
		local inwardRequest = newRequest({ initialPosition = { kind = "seconds", value = 9 }, speed = 1 })
		inwardBackend:apply(0, { inwardRequest })
		inwardRequest.speed = -1
		inwardBackend:apply(1, { inwardRequest })
		inwardBackend:apply(2, { inwardRequest })
		assert(inwardEvents == 0, "inward boundary pivot completed using the old speed")
		assert(inwardAnimator.tracks[1].calls.positionWrites[#inwardAnimator.tracks[1].calls.positionWrites] == 9, "inward pivot did not leave the boundary")

		local outwardBackend = newBackend("sampledPosition", 10)
		local outwardEvents = 0
		outwardBackend:bindToTrackCompleted(function()
			outwardEvents += 1
		end)
		local outwardRequest = newRequest({ initialPosition = { kind = "normalized", value = 1 }, speed = 0 })
		outwardBackend:apply(0, { outwardRequest })
		outwardRequest.speed = 1
		outwardBackend:apply(0, { outwardRequest })
		assert(outwardEvents == 1, "outward boundary pivot did not complete with the new speed")
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
		backend:apply(0, { request })
		backend:apply(1, { request })
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
		backend:apply(0, { request })
		backend:apply(5, { request })
		backend:apply(5, { request })
		assert(#events == 1 and events[1].trackKey == request.trackKey, "sampled completion was not exactly once")
		assert(#animator.tracks[1].calls.positionWrites == 2, "completed tombstone was sampled again")
		local completedTrack = backend:getDebugSnapshot().tracks[1]
		assert(completedTrack.details.lifecycle == "completed", "completion did not tombstone")
		assert(completedTrack.details.physicalPresent == false, "sampled completion retained a frozen physical track")
	end)

	test("synchronous position commands rebase the active physical generation", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local request = newRequest()
		backend:apply(0, { request })
		backend:apply(2, { request })
		assert(backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 5 }), "set position was rejected")
		backend:apply(3, { request })
		assert(backend:offsetTrackPosition(request.trackKey, -2), "offset position was rejected")
		backend:apply(3, { request })
		backend:apply(4, { request })
		local writes = animator.tracks[1].calls.positionWrites
		assert(writes[#writes - 2] == 4 and writes[#writes - 1] == 4 and writes[#writes] == 5, "physical command anchor drifted")
	end)

	test("accrues phase while clip length is unresolved", function(): ()
		local backend, animator = newBackend("sampledPosition", 0)
		local request = newRequest({ speed = 1 })
		backend:apply(0, { request })
		backend:apply(2, { request })
		request.speed = 2
		backend:apply(2, { request })
		assert(#animator.tracks[1].calls.positionWrites == 0, "unknown length received a physical write")
		animator.tracks[1]:setLength(10)
		backend:apply(3, { request })
		assert(animator.tracks[1].calls.positionWrites[1] == 4, "unresolved phase was not rebased across speed change")
	end)

	test("ignores native stop signals and restores sampled playback", function(): ()
		local backend, animator = newBackend("sampledPosition", 10)
		local request = newRequest()
		backend:apply(0, { request })
		local track = animator.tracks[1]
		track:fireStopped()
		assert(backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 2 }), "native stop stole active ownership")
		backend:apply(1, { request })
		assert(track.calls.play == 2 and track.calls.playSpeeds[2] == 0, "sampled playback was not restored at zero rate")
		assert(track.calls.positionWrites[#track.calls.positionWrites] == 3, "restored sampled phase used the wrong anchor")
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
		backend:apply(5, { request })
		expectError(function()
			backend:apply(4, { request })
		end, "backward backend coordinate was accepted")
		assert(#animator.tracks[1].calls.positionWrites == 1, "backward coordinate changed physical phase")
	end)

	test("nativeRate retains Roblox native advancement", function(): ()
		local backend, animator = newBackend("nativeRate", 10)
		local request = newRequest({ speed = -1, initialPosition = { kind = "normalized", value = 1 } })
		backend:apply(0, { request })
		backend:apply(1, { request })
		local track = animator.tracks[1]
		assert(track.calls.playSpeeds[1] == -1, "nativeRate did not retain signed Play speed")
		assert(#track.calls.positionWrites == 1, "nativeRate set position every update")
	end)

	return testCount
end)

transformed.cleanup()
assert(ok, result)

return result

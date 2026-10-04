--!strict
--!optimize 2

local requireAny = require :: any
local process = requireAny("@lune/process")
local ModuleLoader = requireAny(process.cwd .. "/tests/lune/lib/moduleLoader.luau")
local fakeRobloxPath = (process.cwd:gsub("\\", "/")) .. "/tests/lune/fixtures/fakeRoblox.luau"
local FakeRoblox = requireAny(fakeRobloxPath)
local transformed = ModuleLoader.write({
	sourceRoot = "src",
	tempDir = ".tmp/lune-track-markers",
	preamble = "local __fakeRoblox = require([["
		.. fakeRobloxPath
		.. "]])\nlocal Instance = __fakeRoblox.Instance\nlocal Enum = __fakeRoblox.Enum",
})

local ok, result = pcall(function(): number
	local AnimGraph = transformed.requireModule("animGraph/init.luau") :: any
	local count = 0
	local function test(name: string, callback: () -> ())
		local passed, failure = pcall(callback)
		assert(passed, `track markers: {name}: {failure}`)
		count += 1
		print(`PASS track markers: {name}`)
	end
	local function newController(mode: string?): (any, any, any)
		local animator = FakeRoblox.newAnimator(10)
		local backend = AnimGraph.robloxAnimatorBackend.new({
			animator = animator,
			positionMode = mode,
			resolveAssetId = function()
				return 123
			end,
		})
		local controller = AnimGraph.new({
			backend = backend,
			timeReader = function(time)
				return { position = time, rate = 1 }
			end,
			layers = { { id = "base" }, { id = "upper" } },
		})
		return controller, animator, backend
	end
	local function play(controller: any, layer: string?, trackKey: string?, restart: boolean?)
		controller:play(
			layer or "base",
			AnimGraph.clipNode.new("idle", {
				trackKey = trackKey or "feet",
				looped = true,
			}),
			{ state = "idle", forceRestart = restart }
		)
	end
	local function fire(track: any, name: string?, value: string?)
		track:GetMarkerReachedSignal(name or "Footstep"):Fire(value or "left")
	end
	local function expectError(callback: () -> ())
		assert(not pcall(callback), "expected rejection")
	end

	test("specific-track subscription forwards only the string parameter", function()
		local controller, animator, backend = newController()
		local values = {}
		assert(backend:getCapabilities().trackMarkers, "native markers must be supported")
		controller:onTrackMarker("feet", "Footstep", function(...)
			assert(select("#", ...) == 1, "specific callback received extra context")
			table.insert(values, ...)
		end)
		assert(animator.loadCount == 0, "subscription materialized a track")
		play(controller)
		controller:update(0)
		fire(animator.tracks[1], "Other")
		assert(#values == 0, "unrelated marker delivered")
		fire(animator.tracks[1])
		fire(animator.tracks[1], "Footstep", "")
		assert(#values == 2 and values[1] == "left" and values[2] == "", "parameter string changed")
		controller:destroy()
	end)

	test("late subscribers share one signal connection and release independently", function()
		local controller, animator = newController()
		play(controller)
		controller:update(0)
		local track = animator.tracks[1]
		assert(next(track.markerSignals) == nil, "unobserved tracks acquired marker signals")
		local calls = 0
		local callback = function()
			calls += 1
		end
		local releaseA = controller:onTrackMarker("feet", "Footstep", callback)
		local releaseB = controller:onTrackMarker("feet", "Footstep", callback)
		local signal = track:GetMarkerReachedSignal("Footstep")
		assert(signal:getConnectionCount() == 1, "Expected signal:getConnectionCount() == 1")
		fire(track)
		assert(calls == 2, "Expected calls == 2")
		releaseA()
		releaseA()
		fire(track)
		assert(
			calls == 3 and signal:getConnectionCount() == 1,
			"Expected calls == 3 and signal:getConnectionCount() == 1"
		)
		releaseB()
		assert(signal:getConnectionCount() == 0, "Expected signal:getConnectionCount() == 0")
		controller:destroy()
	end)

	test("unchanged updates do not reconnect or read or write native positions", function()
		local controller, animator = newController()
		controller:onTrackMarker("feet", "Footstep", function() end)
		play(controller)
		controller:update(0)
		local track = animator.tracks[1]
		local reads, writes = track.calls.positionReads, #track.calls.positionWrites
		for i = 1, 10 do
			controller:update(i)
		end
		assert(
			track.calls.positionReads == reads and #track.calls.positionWrites == writes,
			"Expected track.calls.positionReads == reads and #track.calls.positionWrites == writes"
		)
		assert(
			track:GetMarkerReachedSignal("Footstep"):getConnectionCount() == 1,
			'Expected track:GetMarkerReachedSignal("Footstep"):getConnectionCount() == 1'
		)
		assert(animator.loadCount == 1, "Expected animator.loadCount == 1")
		controller:destroy()
	end)

	test("all-track subscription distinguishes the same asset on two layers", function()
		local controller, animator = newController()
		local tracks, values = {}, {}
		controller:onMarker("Footstep", function(track, value)
			table.insert(tracks, track)
			table.insert(values, value)
		end)
		play(controller)
		play(controller, "upper", "hands")
		controller:update(0)
		fire(animator.tracks[1])
		fire(animator.tracks[2], "Footstep", "right")
		assert(#tracks == 2 and tracks[1]:getLayer() == "base" and tracks[2]:getLayer() == "upper", "layers conflated")
		assert(tracks[1]:getTrackKey() == "feet" and tracks[2]:getTrackKey() == "hands", "track keys conflated")
		assert(tracks[1]:getGeneration() ~= tracks[2]:getGeneration(), "generations conflated")
		assert(tracks[1]:getClip() == "idle" and tracks[1]:getState() == "idle", "source context missing")
		assert(values[1] == "left" and values[2] == "right", "marker parameters conflated")
		fire(animator.tracks[1])
		assert(tracks[1] == tracks[3], "callback allocated a fresh track view")
		controller:destroy()
	end)

	test("restarts disconnect old tracks and reject already captured stale callbacks", function()
		local controller, animator = newController()
		local tracks = {}
		controller:onMarker("Footstep", function(track)
			table.insert(tracks, track)
		end)
		play(controller)
		controller:update(0)
		local old = animator.tracks[1]
		fire(old)
		local stale = old:GetMarkerReachedSignal("Footstep"):capture()
		play(controller, nil, nil, true)
		controller:update(1)
		assert(old:GetMarkerReachedSignal("Footstep"):getConnectionCount() == 0, "old track still connected")
		stale("stale")
		fire(old)
		fire(animator.tracks[2])
		assert(#tracks == 2 and tracks[2]:getGeneration() == 2, "stale generation delivered")
		assert(tracks[1] ~= tracks[2] and tracks[1]:getGeneration() == 1, "old track view retargeted")
		controller:destroy()
	end)

	test("retirement suppresses markers during fade and subscriptions follow reappearance", function()
		local controller, animator = newController()
		local calls = 0
		controller:onTrackMarker("feet", "Footstep", function()
			calls += 1
		end)
		play(controller)
		controller:update(0)
		controller:stopLayer("base", 1)
		controller:update(1)
		fire(animator.tracks[1])
		assert(
			calls == 0 and animator.tracks[1]:GetMarkerReachedSignal("Footstep"):getConnectionCount() == 0,
			'Expected calls == 0 and animator.tracks[1]:GetMarkerReachedSignal("Footstep"):getConnectionCount() == 0'
		)
		play(controller)
		controller:update(2)
		fire(animator.tracks[2])
		assert(calls == 1, "Expected calls == 1")
		controller:destroy()
	end)

	test("clear retains logical subscriptions and destroy disconnects everything", function()
		local controller, animator = newController()
		local calls = 0
		local release = controller:onTrackMarker("feet", "Footstep", function()
			calls += 1
		end)
		play(controller)
		controller:update(0)
		controller:clear()
		fire(animator.tracks[1])
		assert(calls == 0, "Expected calls == 0")
		play(controller)
		controller:update(1)
		fire(animator.tracks[2])
		assert(calls == 1, "Expected calls == 1")
		local signal = animator.tracks[2]:GetMarkerReachedSignal("Footstep")
		local stale = signal:capture()
		controller:destroy()
		controller:destroy()
		stale("late")
		assert(
			calls == 1 and signal:getConnectionCount() == 0,
			"Expected calls == 1 and signal:getConnectionCount() == 0"
		)
		release()
		release()
		expectError(function()
			controller:onTrackMarker("feet", "Footstep", function() end)
		end)
	end)

	test("natural completion disconnects marker observation", function()
		local controller, animator = newController()
		local calls = 0
		controller:onTrackMarker("feet", "Footstep", function()
			calls += 1
		end)
		controller:play("base", AnimGraph.clipNode.new("idle", { trackKey = "feet", looped = false }))
		controller:update(0)
		local signal = animator.tracks[1]:GetMarkerReachedSignal("Footstep")
		animator.tracks[1]:fireStopped()
		signal:Fire("late")
		assert(
			calls == 0 and signal:getConnectionCount() == 0,
			"Expected calls == 0 and signal:getConnectionCount() == 0"
		)
		controller:destroy()
	end)

	test("listener changes use a snapshot and releases suppress pending delivery", function()
		local controller, animator = newController()
		local order = {}
		local releaseB = function() end
		local added = false
		controller:onTrackMarker("feet", "Footstep", function()
			table.insert(order, "A")
			releaseB()
			if not added then
				added = true
				controller:onTrackMarker("feet", "Footstep", function()
					table.insert(order, "C")
				end)
			end
		end)
		releaseB = controller:onTrackMarker("feet", "Footstep", function()
			table.insert(order, "B")
		end)
		play(controller)
		controller:update(0)
		fire(animator.tracks[1])
		assert(table.concat(order) == "A", 'Expected table.concat(order) == "A"')
		fire(animator.tracks[1])
		assert(table.concat(order) == "AAC", 'Expected table.concat(order) == "AAC"')
		controller:destroy()
	end)

	test("callback clear and destroy invalidate the rest of the dispatch", function()
		for _, operation in { "clear", "destroy" } do
			local controller, animator = newController()
			local calls = 0
			controller:onTrackMarker("feet", "Footstep", function()
				controller[operation](controller)
			end)
			controller:onTrackMarker("feet", "Footstep", function()
				calls += 1
			end)
			play(controller)
			controller:update(0)
			fire(animator.tracks[1])
			assert(calls == 0, "Expected calls == 0")
			controller:destroy()
		end
	end)

	test("callback restart suppresses remaining old-generation listeners", function()
		local controller, animator = newController()
		local generations = {}
		controller:onMarker("Footstep", function(track)
			if track:getGeneration() == 1 then
				play(controller, nil, nil, true)
				controller:update(1)
			end
		end)
		controller:onMarker("Footstep", function(track)
			table.insert(generations, track:getGeneration())
		end)
		play(controller)
		controller:update(0)
		fire(animator.tracks[1])
		fire(animator.tracks[2])
		assert(#generations == 1 and generations[1] == 2, "Expected #generations == 1 and generations[1] == 2")
		controller:destroy()
	end)

	test("recursive signals are queued and callback errors do not poison later dispatch", function()
		local controller, animator = newController()
		local depth, maxDepth, calls = 0, 0, 0
		local release = controller:onTrackMarker("feet", "Footstep", function()
			depth += 1
			maxDepth = math.max(maxDepth, depth)
			calls += 1
			if calls == 1 then
				fire(animator.tracks[1])
			end
			depth -= 1
		end)
		play(controller)
		controller:update(0)
		fire(animator.tracks[1])
		assert(calls == 2 and maxDepth == 1, "Expected calls == 2 and maxDepth == 1")
		release()
		release = controller:onTrackMarker("feet", "Footstep", function()
			error("consumer failure")
		end)
		expectError(function()
			fire(animator.tracks[1])
		end)
		release()
		controller:onTrackMarker("feet", "Footstep", function()
			calls += 1
		end)
		fire(animator.tracks[1])
		assert(calls == 3, "Expected calls == 3")
		controller:destroy()
	end)

	test("sampled mode rejects subscriptions without loading tracks", function()
		local controller, animator, backend = newController("sampledPosition")
		assert(
			backend:getCapabilities().trackMarkers == false,
			"Expected backend:getCapabilities().trackMarkers == false"
		)
		expectError(function()
			controller:onTrackMarker("feet", "Footstep", function() end)
		end)
		expectError(function()
			backend:bindToTrackMarker("feet", "Footstep", function() end)
		end)
		assert(animator.loadCount == 0, "Expected animator.loadCount == 0")
		play(controller)
		controller:update(0)
		controller:update(1)
		assert(#animator.tracks[1].calls.positionWrites >= 2, "Expected #animator.tracks[1].calls.positionWrites >= 2")
		controller:destroy()
	end)

	test("release before materialization avoids acquiring a signal", function()
		local controller, animator = newController()
		local release = controller:onTrackMarker("feet", "Footstep", function()
			error("released")
		end)
		release()
		release()
		play(controller)
		controller:update(0)
		assert(next(animator.tracks[1].markerSignals) == nil, "Expected next(animator.tracks[1].markerSignals) == nil")
		controller:destroy()
	end)

	test("signals raised during apply dispatch only after the complete batch", function()
		local controller, animator = newController()
		local loadAnimation = animator.LoadAnimation
		animator.LoadAnimation = function(self, animation)
			local track = loadAnimation(self, animation)
			track.onPlay = function()
				fire(track)
			end
			return track
		end
		local calls = 0
		controller:onTrackMarker("feet", "Footstep", function()
			assert(animator.loadCount == 2, "marker callback observed a partial batch")
			calls += 1
			controller:clear()
		end)
		play(controller)
		play(controller, "upper", "hands")
		controller:update(0)
		assert(calls == 1, "Expected calls == 1")
		for _, track in animator.tracks do
			assert(track.calls.destroy == 1, "callback clear leaked a track")
		end
		controller:destroy()
	end)

	test("failed apply discards queued markers instead of delivering them on recovery", function()
		local controller, animator = newController()
		local loadAnimation = animator.LoadAnimation
		animator.LoadAnimation = function(self, animation)
			if self.loadCount == 1 then
				error("load failed")
			end
			local track = loadAnimation(self, animation)
			track.onPlay = function()
				fire(track)
			end
			return track
		end
		local calls = 0
		controller:onTrackMarker("feet", "Footstep", function()
			calls += 1
		end)
		play(controller)
		play(controller, "upper", "hands")
		expectError(function()
			controller:update(0)
		end)
		animator.LoadAnimation = loadAnimation
		controller:update(1)
		assert(calls == 0, "failed apply leaked a queued marker into recovery")
		fire(animator.tracks[1])
		assert(calls == 1, "marker dispatch did not recover after apply failure")
		controller:destroy()
	end)

	test("seeking does not synthesize markers and loop notifications remain repeatable", function()
		local controller, animator = newController()
		local calls = 0
		controller:onTrackMarker("feet", "Footstep", function()
			calls += 1
		end)
		play(controller)
		controller:update(0)
		controller:setTrackPosition("feet", { kind = "seconds", value = 8 })
		controller:offsetTrackPosition("feet", -5)
		assert(calls == 0, "Expected calls == 0")
		fire(animator.tracks[1])
		fire(animator.tracks[1])
		assert(calls == 2, "Expected calls == 2")
		controller:destroy()
	end)

	test("controller forwards subscriptions to a backend without Roblox APIs", function()
		local calls, released = 0, 0
		local listener = nil
		local backend = {
			getCapabilities = function()
				return { trackMarkers = true }
			end,
			bindToTrackCompleted = function()
				return function() end
			end,
			bindToTrackMarker = function(_, key, name, callback)
				assert(key == "logical" and name == "Cue", 'Expected key == "logical" and name == "Cue"')
				listener = callback
				return function()
					released += 1
				end
			end,
			clear = function() end,
			destroy = function() end,
		}
		local controller = AnimGraph.new({
			backend = backend,
			timeReader = function(time)
				return { position = time, rate = 1 }
			end,
		})
		local release = controller:onTrackMarker("logical", "Cue", function(value)
			assert(value == "data", "parameter was not forwarded")
			calls += 1
		end)
		listener("data")
		release()
		assert(calls == 1 and released == 1, "Expected calls == 1 and released == 1")
		controller:destroy()
	end)

	test("global observation attaches to existing and future tracks and shares specific connections", function()
		local controller, animator = newController()
		play(controller)
		controller:update(0)
		local localCalls, globalCalls = 0, 0
		local releaseLocal = controller:onTrackMarker("feet", "Footstep", function()
			localCalls += 1
		end)
		local releaseGlobal = controller:onMarker("Footstep", function()
			globalCalls += 1
		end)
		local releaseOther = controller:onMarker("Hand", function()
			error("wrong marker delivered")
		end)
		local first = animator.tracks[1]:GetMarkerReachedSignal("Footstep")
		assert(first:getConnectionCount() == 1, "global and specific observers duplicated the signal connection")
		play(controller, "upper", "hands")
		controller:update(1)
		fire(animator.tracks[1])
		fire(animator.tracks[2])
		assert(localCalls == 1 and globalCalls == 2, "existing or future track was not observed")
		releaseGlobal()
		releaseGlobal()
		assert(first:getConnectionCount() == 1, "global release removed a specific observer's connection")
		assert(
			animator.tracks[2]:GetMarkerReachedSignal("Footstep"):getConnectionCount() == 0,
			"global connection leaked"
		)
		fire(animator.tracks[1])
		assert(localCalls == 2 and globalCalls == 2, "global release left callback active")
		releaseLocal()
		releaseOther()
		assert(first:getConnectionCount() == 0, "last observer did not release physical connection")
		controller:destroy()
	end)

	test("specific release preserves global observation and global observers share connections", function()
		local controller, animator = newController()
		local calls = 0
		local releaseLocal = controller:onTrackMarker("feet", "Footstep", function()
			error("released local")
		end)
		local releaseA = controller:onMarker("Footstep", function()
			calls += 1
		end)
		local releaseB = controller:onMarker("Footstep", function()
			calls += 1
		end)
		play(controller)
		controller:update(0)
		releaseLocal()
		fire(animator.tracks[1])
		assert(calls == 2, "specific release removed global observers")
		releaseA()
		fire(animator.tracks[1])
		assert(calls == 3, "global observers did not release independently")
		assert(
			animator.tracks[1]:GetMarkerReachedSignal("Footstep"):getConnectionCount() == 1,
			"shared connection changed"
		)
		releaseB()
		assert(
			animator.tracks[1]:GetMarkerReachedSignal("Footstep"):getConnectionCount() == 0,
			"global connection leaked"
		)
		controller:destroy()
	end)

	test("global clear stop and destroy preserve the intended subscription lifetime", function()
		local controller, animator = newController()
		local calls = 0
		local release = controller:onMarker("Footstep", function()
			calls += 1
		end)
		play(controller)
		controller:update(0)
		controller:stopLayer("base", 1)
		controller:update(1)
		fire(animator.tracks[1])
		assert(calls == 0, "retired track reached global observer")
		play(controller)
		controller:update(2)
		fire(animator.tracks[2])
		controller:clear()
		play(controller)
		controller:update(3)
		fire(animator.tracks[3])
		assert(calls == 2, "global observer did not survive clear and reappearance")
		local signal = animator.tracks[3]:GetMarkerReachedSignal("Footstep")
		local stale = signal:capture()
		controller:destroy()
		stale("late")
		release()
		release()
		assert(calls == 2 and signal:getConnectionCount() == 0, "destroy leaked global observation")
		expectError(function()
			controller:onMarker("Footstep", function() end)
		end)
	end)

	test("global and specific listener mutations share one event boundary", function()
		local controller, animator = newController()
		local calls, added = {}, false
		local releaseGlobal = controller:onMarker("Footstep", function()
			table.insert(calls, "old")
		end)
		controller:onTrackMarker("feet", "Footstep", function()
			table.insert(calls, "local")
			releaseGlobal()
			if not added then
				added = true
				controller:onMarker("Footstep", function()
					table.insert(calls, "new")
				end)
			end
		end)
		play(controller)
		controller:update(0)
		fire(animator.tracks[1])
		assert(table.concat(calls, ",") == "local", "new global observer saw an in-progress event")
		fire(animator.tracks[1])
		assert(table.concat(calls, ",") == "local,local,new", "observer mutation skipped or duplicated delivery")
		controller:destroy()
	end)

	test("clear during dispatch can queue a new generation without losing its payload", function()
		local controller, animator = newController()
		local values = {}
		controller:onMarker("Footstep", function(track, value)
			table.insert(values, value)
			if track:getGeneration() == 1 then
				controller:clear()
				play(controller)
				controller:update(1)
				fire(animator.tracks[2], "Footstep", "new")
			end
		end)
		play(controller)
		controller:update(0)
		fire(animator.tracks[1], "Footstep", "old")
		assert(table.concat(values, ",") == "old,new", "queue reset lost the new generation's event")
		controller:destroy()
	end)

	test("global callback failure restores listener compaction and later dispatch", function()
		local controller, animator = newController()
		local release = function() end
		release = controller:onMarker("Footstep", function()
			release()
			error("consumer failure")
		end)
		local calls = 0
		controller:onMarker("Footstep", function()
			calls += 1
		end)
		play(controller)
		controller:update(0)
		expectError(function()
			fire(animator.tracks[1])
		end)
		fire(animator.tracks[1])
		assert(calls == 1, "throwing subscriber poisoned future delivery")
		controller:destroy()
	end)

	test("sampled mode rejects global subscriptions and early release avoids all-track connections", function()
		local controller, animator, backend = newController("sampledPosition")
		expectError(function()
			controller:onMarker("Footstep", function() end)
		end)
		expectError(function()
			backend:bindToMarker("Footstep", function() end)
		end)
		assert(animator.loadCount == 0, "unsupported subscription loaded tracks")
		controller:destroy()
		controller, animator = newController()
		local release = controller:onMarker("Footstep", function()
			error("released")
		end)
		release()
		release()
		play(controller)
		controller:update(0)
		assert(next(animator.tracks[1].markerSignals) == nil, "released observer acquired a physical connection")
		controller:destroy()
	end)

	return count
end)
transformed.cleanup()
assert(ok, result)
return result

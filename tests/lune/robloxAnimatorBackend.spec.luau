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
		assert(track.calls.stop == 1, "repeated disappearance restarted retirement")
		assert(track.calls.stopFades[1] == 0.2, "disappearance used the wrong fade")
		backend:apply({ request })
		backend:apply({ request })
		assert(animator.loadCount == 2, "reappearance did not materialize exactly one new generation")
		assert(animator.tracks[2].calls.play == 1, "unchanged reappearing generation replayed")
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
		track:fireStopped()
		backend:apply({ request })
		backend:apply({ request })
		assert(track.calls.play == 1, "natural completion replayed")
		assert(backend:getDebugSnapshot().tracks[1].isPlaying == false, "natural completion was not latched")
	end)

	test("forceRestart without a position starts one new generation at zero", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply({ request })
		local oldTrack = animator.tracks[1]
		oldTrack:setEngineTimePosition(4)
		request.forceRestart = true
		backend:apply({ request })
		request.forceRestart = false
		backend:apply({ request })
		backend:apply({ request })
		local newTrack = animator.tracks[2]
		assert(oldTrack.calls.play == 1 and oldTrack.calls.stop == 1, "forceRestart did not retire the old generation")
		assert(newTrack.calls.play == 1 and newTrack.TimePosition == 0, "default restart did not start at zero")
		assert(animator.loadCount == 2, "forceRestart did not materialize exactly one new physical generation")
	end)

	test("forceRestart with a position uses it once instead of the zero default", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply({ request })
		local oldTrack = animator.tracks[1]
		oldTrack:setEngineTimePosition(4)
		request.forceRestart = true
		request.initialPosition = { kind = "normalized", value = 0.6 }
		backend:apply({ request })
		request.forceRestart = false
		backend:apply({ request })
		backend:apply({ request })
		local newTrack = animator.tracks[2]
		assert(oldTrack.calls.stop == 1 and newTrack.calls.play == 1, "positioned forceRestart was repeated")
		assert(#newTrack.calls.positionWrites == 1 and newTrack.calls.positionWrites[1] == 6, "explicit restart position lost precedence")
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
		assert(animator.loadCount == 2, "forced materialization generation did not restart exactly once")
		assert(#animator.tracks[1].calls.positionWrites == 1, "first generation position was not one-shot")
		assert(#animator.tracks[2].calls.positionWrites == 1, "second generation position was not one-shot")
		assert(animator.tracks[1].calls.positionWrites[1] == 2, "first generation position was wrong")
		assert(animator.tracks[2].calls.positionWrites[1] == 2, "second generation position was wrong")
	end)

	test("live positioning moves forward and backward without replacing the generation", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest({ weight = 0.7, speed = 1.5, looped = true, logicalPriority = 50 })
		backend:apply({ request })
		local before = backend:getDebugSnapshot().tracks[1]
		local generation = before.details.generation
		assert(backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 7 }), "forward position was rejected")
		assert(backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 2 }), "backward position was rejected")

		local track = animator.tracks[1]
		local after = backend:getDebugSnapshot().tracks[1]
		assert(animator.loadCount == 1 and track.calls.play == 1, "live positioning replaced or replayed the generation")
		assert(after.details.generation == generation, "live positioning changed generation identity")
		assert(after.weight == 0.7 and after.speed == 1.5, "live positioning changed desired native state")
		assert(#track.calls.positionWrites == 2, "live positions were not written exactly once")
		assert(track.calls.positionWrites[1] == 7 and track.calls.positionWrites[2] == 2, "live positions were wrong")
	end)

	test("pending live positioning resolves and permanently supersedes a pending initial position", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest({ initialPosition = { kind = "normalized", value = 0.25 } })
		backend:apply({ request })
		local track = animator.tracks[1]
		assert(backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 6 }), "pending live position was rejected")
		assert(#track.calls.positionWrites == 0, "zero-length live position wrote early")
		track:setLength(10)
		backend:apply({ request })
		backend:apply({ request })
		assert(#track.calls.positionWrites == 1 and track.calls.positionWrites[1] == 6, "pending initial position won after live supersession")
	end)

	test("invalid live positions reject before changing pending state", function(): ()
		local backend, animator = newBackend(0)
		local request = newRequest({ initialPosition = { kind = "seconds", value = 2 } })
		backend:apply({ request })
		expectError(function()
			backend:setTrackPosition(request.trackKey, { kind = "seconds", value = -1 })
		end, "invalid live position was accepted")
		animator.tracks[1]:setLength(10)
		backend:apply({ request })
		assert(animator.tracks[1].calls.positionWrites[1] == 2, "invalid live command mutated the pending initial position")
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
			backend:apply({ request })
			assert(backend:setTrackPosition(request.trackKey, { kind = "seconds", value = value }), "terminal position was rejected")
			assert(events == 1 and committed, "terminal completion dispatched before tombstone commit")
			assert(not backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }), "completed key was revived")
			backend:apply({ request })
			animator.tracks[1]:fireStopped()
			assert(events == 1 and animator.loadCount == 1, "completed request replayed or emitted twice")
			animator.tracks[1]:fireEnded()
			local tombstone = backend:getDebugSnapshot().tracks[1]
			assert(tombstone.details.lifecycle == "completed" and not tombstone.details.physicalPresent, "Ended removed the tombstone or retained physics")
		end
	end)

	test("looping live positions wrap and canonicalize without completion", function(): ()
		local backend, animator = newBackend(10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({ looped = true })
		backend:apply({ request })
		assert(backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 22 }), "loop seconds position was rejected")
		assert(backend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 }), "loop normalized position was rejected")
		local writes = animator.tracks[1].calls.positionWrites
		assert(writes[1] == 2 and writes[2] == 0, "loop positions did not wrap or canonicalize")
		assert(events == 0 and backend:getDebugSnapshot().tracks[1].details.lifecycle == "active", "loop position completed playback")
	end)

	test("active looped Ended cleans ownership and rematerializes a guarded generation", function(): ()
		local backend, animator = newBackend(10)
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
		end)
		local request = newRequest({ looped = true })
		backend:apply({ request })
		local oldTrack = animator.tracks[1]
		local oldGeneration = backend:getDebugSnapshot().tracks[1].details.generation

		oldTrack:fireEnded()
		assert(events == 0, "active looped Ended emitted completion")
		assert(oldTrack.calls.destroy == 1 and animator.animations[1].destroyed, "active looped Ended did not clean physical ownership once")
		assert(oldTrack.Stopped:getConnectionCount() == 0, "active looped Ended leaked Stopped")
		assert(oldTrack.Ended:getConnectionCount() == 0, "active looped Ended leaked Ended")
		assert(#backend:getDebugSnapshot().tracks == 0, "active looped Ended left stale lifecycle or debug ownership")

		backend:apply({ request })
		local newTrack = animator.tracks[2]
		local replacement = backend:getDebugSnapshot().tracks[1]
		assert(animator.loadCount == 2, "unchanged looped request did not rematerialize")
		assert(replacement.details.lifecycle == "active", "rematerialized looped generation was not active")
		assert(replacement.details.physicalPresent, "rematerialized looped generation had no physical ownership")
		assert(replacement.details.generation > oldGeneration, "rematerialized looped request reused its generation")

		oldTrack:fireStopped()
		oldTrack:fireEnded()
		local afterStaleSignals = backend:getDebugSnapshot().tracks[1]
		assert(events == 0 and oldTrack.calls.destroy == 1, "stale looped signals completed or recleaned the old generation")
		assert(newTrack.calls.destroy == 0, "stale looped signals cleaned the replacement")
		assert(afterStaleSignals.details.generation == replacement.details.generation, "stale looped signals replaced active ownership")
	end)

	test("positioning returns false for missing, retiring, completed, and destroyed keys", function(): ()
		local backend = newBackend(10)
		assert(not backend:setTrackPosition("missing", { kind = "seconds", value = 1 }), "missing key was accepted")
		local request = newRequest()
		backend:apply({ request })
		backend:apply({})
		assert(not backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }), "retiring key was accepted")

		local completedBackend = newBackend(10)
		completedBackend:apply({ request })
		completedBackend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 })
		assert(not completedBackend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }), "completed key was accepted")
		completedBackend:destroy()
		assert(not completedBackend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }), "destroyed backend accepted a key")
	end)

	test("natural completion dispatches once, cleans physics on Ended, and retains a tombstone", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		local events = {} :: { any }
		backend:bindToTrackCompleted(function(event)
			events[#events + 1] = event
		end)
		backend:apply({ request })
		local track = animator.tracks[1]
		track:fireStopped()
		track:fireStopped()
		assert(#events == 1, "natural completion did not dispatch exactly once")
		assert(events[1].layer == request.layer and events[1].state == request.state, "completion identity was wrong")
		track:fireEnded()
		assert(track.calls.destroy == 1 and animator.animations[1].destroyed, "Ended did not clean physical ownership")
		backend:apply({ request })
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
		backend:apply({ request })
		local track = animator.tracks[1]
		local ended, resultOrError = pcall(function(): unknown
			track:fireEnded()
			return nil
		end)
		assert(not ended, "Ended completion listener error did not propagate")
		assert(string.find(tostring(resultOrError), "expected Ended completion failure", 1, true) ~= nil, "Ended propagated the wrong completion listener error")
		assert(callbacks == 1, "Ended completion listener ran more than once")

		local snapshot = backend:getDebugSnapshot()
		assert(#snapshot.tracks == 1, "Ended completion did not preserve exactly one tombstone")
		assert(snapshot.tracks[1].details.lifecycle == "completed", "Ended completion lost its tombstone lifecycle")
		assert(not snapshot.tracks[1].details.physicalPresent, "Ended completion retained physical ownership after error")
		assert(track.calls.destroy == 1 and animator.animations[1].destroyed, "Ended completion did not destroy physical objects once")
		assert(track.Stopped:getConnectionCount() == 0, "Ended completion leaked Stopped after error")
		assert(track.Ended:getConnectionCount() == 0, "Ended completion leaked Ended after error")
		local oldGeneration = snapshot.tracks[1].details.generation

		releaseFailing()
		local laterEvents = {} :: { any }
		backend:bindToTrackCompleted(function(event)
			laterEvents[#laterEvents + 1] = event
		end)
		local replacementRequest = newRequest({ clip = "wave", state = "replacement" })
		backend:apply({ replacementRequest })
		local replacementTrack = animator.tracks[2]
		local replacementSnapshot = backend:getDebugSnapshot()
		assert(animator.loadCount == 2, "different-clip presence did not materialize a replacement generation")
		assert(#replacementSnapshot.tracks == 1, "replacement generation did not own exactly one lifecycle entry")
		assert(replacementSnapshot.tracks[1].trackKey == request.trackKey, "replacement changed the track key")
		assert(replacementSnapshot.tracks[1].details.lifecycle == "active", "replacement generation was not active")
		assert(replacementSnapshot.tracks[1].details.physicalPresent, "replacement generation had no physical ownership")
		assert(replacementSnapshot.tracks[1].details.generation > oldGeneration, "replacement reused the failed generation")
		assert(#laterEvents == 0, "replacement materialization emitted completion")

		track:fireStopped()
		track:fireEnded()
		local afterStaleSignals = backend:getDebugSnapshot()
		assert(callbacks == 1 and track.calls.destroy == 1, "stale signals redispatched or recleaned the failed generation")
		assert(#laterEvents == 0, "stale old signals completed the replacement")
		assert(replacementTrack.calls.destroy == 0 and replacementTrack.IsPlaying, "stale old signals mutated or cleaned the replacement")
		assert(afterStaleSignals.tracks[1].details.generation == replacementSnapshot.tracks[1].details.generation, "stale old signals changed replacement ownership")
		assert(afterStaleSignals.tracks[1].details.physicalPresent, "stale old signals removed replacement physics")

		replacementTrack:fireEnded()
		assert(#laterEvents == 1, "replacement completion did not dispatch exactly once")
		assert(laterEvents[1].trackKey == request.trackKey and laterEvents[1].state == "replacement", "replacement completion identity was wrong")
		local replacementCompleted = backend:getDebugSnapshot()
		assert(replacementCompleted.tracks[1].details.lifecycle == "completed", "replacement completion did not commit a tombstone")
		assert(not replacementCompleted.tracks[1].details.physicalPresent, "replacement completion retained physical ownership")
		assert(replacementTrack.calls.destroy == 1 and animator.animations[2].destroyed, "replacement completion did not clean physical objects once")
		replacementTrack:fireStopped()
		replacementTrack:fireEnded()
		assert(#laterEvents == 1 and replacementTrack.calls.destroy == 1, "replacement stale signals duplicated completion or cleanup")
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
		backend:apply({ terminal, companion })
		assert(sawCommittedBatch, "initial terminal completion dispatched before the batch committed")
	end)

	test("tombstones retire on omission, different clip, force restart, clear, and destroy", function(): ()
		local request = newRequest({ initialPosition = { kind = "normalized", value = 1 } })

		local omissionBackend, omissionAnimator = newBackend(10)
		omissionBackend:apply({ request })
		omissionBackend:apply({ request })
		assert(omissionAnimator.loadCount == 1, "same tombstoned request replayed")
		omissionBackend:apply({})
		omissionBackend:apply({ request })
		assert(omissionAnimator.loadCount == 2, "omission did not retire the tombstone")

		local replacementBackend, replacementAnimator = newBackend(10)
		replacementBackend:apply({ request })
		replacementBackend:apply({ newRequest({ clip = "wave" }) })
		assert(replacementAnimator.loadCount == 2, "different clip did not replace the tombstone")

		local restartBackend, restartAnimator = newBackend(10)
		restartBackend:apply({ request })
		restartBackend:apply({ newRequest({ forceRestart = true }) })
		assert(restartAnimator.loadCount == 2, "force restart did not replace the tombstone")

		local clearBackend, clearAnimator = newBackend(10)
		clearBackend:apply({ request })
		clearBackend:clear()
		assert(#clearBackend:getDebugSnapshot().tracks == 0 and clearAnimator.tracks[1].calls.destroy == 1, "clear retained tombstone or physics")

		local destroyBackend, destroyAnimator = newBackend(10)
		destroyBackend:apply({ request })
		destroyBackend:destroy()
		assert(#destroyBackend:getDebugSnapshot().tracks == 0 and destroyAnimator.tracks[1].calls.destroy == 1, "destroy retained tombstone or physics")
	end)

	test("explicit retirement suppresses completion for every retirement cause", function(): ()
		local function runCase(action: (backend: any, request: any) -> (), label: string): ()
			local backend, animator = newBackend(10)
			local events = 0
			backend:bindToTrackCompleted(function()
				events += 1
			end)
			local request = newRequest()
			backend:apply({ request })
			local oldTrack = animator.tracks[1]
			action(backend, request)
			oldTrack:fireStopped()
			assert(events == 0, label .. " emitted completion")
		end

		runCase(function(backend, _request)
			backend:stopLayer("base", 0.4)
		end, "stopLayer")
		runCase(function(backend, _request)
			backend:apply({})
		end, "disappearance")
		runCase(function(backend, _request)
			backend:apply({ newRequest({ clip = "wave" }) })
		end, "replacement")
		runCase(function(backend, _request)
			backend:apply({ newRequest({ forceRestart = true }) })
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
		backend:apply({ request })
		local oldTrack = animator.tracks[1]
		backend:apply({})
		backend:apply({ request })
		local newTrack = animator.tracks[2]
		assert(backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 3 }), "new active generation was not addressable")
		oldTrack:fireStopped()
		oldTrack:fireEnded()
		assert(events == 0 and oldTrack.calls.destroy == 1, "stale old signals completed or leaked the retired generation")
		assert(newTrack.calls.destroy == 0 and newTrack.TimePosition == 3, "stale old signals mutated the new generation")

		local replacement = newRequest({ clip = "wave", fadeTime = 0.6 })
		backend:apply({ replacement })
		assert(animator.loadCount == 3 and newTrack.calls.stopFades[1] == 0.6, "different-clip replacement did not use incoming fade")
	end)

	test("non-zero fade waits for Ended while zero fade and inactive retirement clean immediately", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		backend:apply({ request })
		local fadingTrack = animator.tracks[1]
		backend:stopLayer("base", 0.5)
		assert(fadingTrack.calls.stopFades[1] == 0.5 and fadingTrack.calls.destroy == 0, "non-zero fade cleaned before Ended")
		assert(fadingTrack.Stopped:getConnectionCount() == 0 and fadingTrack.Ended:getConnectionCount() == 1, "retirement retained the wrong signal ownership")
		fadingTrack:fireEnded()
		assert(fadingTrack.calls.destroy == 1 and animator.animations[1].destroyed, "Ended did not own final cleanup")
		assert(fadingTrack.Ended:getConnectionCount() == 0, "Ended connection leaked after cleanup")

		local zeroBackend, zeroAnimator = newBackend(10)
		zeroBackend:apply({ request })
		zeroBackend:stopLayer("base", 0)
		assert(zeroAnimator.tracks[1].calls.destroy == 1, "zero-fade retirement did not clean immediately")

		local inactiveBackend, inactiveAnimator = newBackend(10)
		inactiveBackend:apply({ request })
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
		backend:apply({ request })
		backend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 })
		request.forceRestart = true
		request.initialPosition = { kind = "normalized", value = 1 }
		backend:apply({ request })
		assert(table.concat(calls, ",") == "first,second,added", "listener mutation changed the active dispatch snapshot")
	end)

	test("throwing completion listener propagates without wedging later dispatch", function(): ()
		local backend = newBackend(10)
		local request = newRequest()
		local failedCalls = 0
		local releaseFailing = backend:bindToTrackCompleted(function()
			failedCalls += 1
			error("expected completion callback failure")
		end)
		backend:apply({ request })
		local completed, resultOrError = pcall(function(): unknown
			backend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 })
			return nil
		end)
		assert(not completed, "throwing completion listener did not propagate its error")
		assert(string.find(tostring(resultOrError), "expected completion callback failure", 1, true) ~= nil, "completion callback propagated the wrong error")
		assert(failedCalls == 1, "failed completion event was duplicated")

		releaseFailing()
		local laterEvents = {} :: { any }
		backend:bindToTrackCompleted(function(event)
			laterEvents[#laterEvents + 1] = event
		end)
		local laterRequest = newRequest({ state = "later", forceRestart = true })
		backend:apply({ laterRequest })
		assert(#laterEvents == 0, "failed completion event remained queued")
		backend:setTrackPosition(laterRequest.trackKey, { kind = "normalized", value = 1 })
		assert(#laterEvents == 1 and laterEvents[1].state == "later", "later completed generation did not dispatch exactly once")
	end)

	test("completion callback may position, clear, and destroy without duplicates or leaks", function(): ()
		local backend, animator = newBackend(10)
		local request = newRequest()
		local events = 0
		backend:bindToTrackCompleted(function()
			events += 1
			assert(not backend:setTrackPosition(request.trackKey, { kind = "seconds", value = 1 }), "callback revived its completed key")
			backend:stopLayer("base", 0)
			backend:clear()
			backend:destroy()
		end)
		backend:apply({ request })
		backend:setTrackPosition(request.trackKey, { kind = "normalized", value = 1 })
		animator.tracks[1]:fireStopped()
		animator.tracks[1]:fireEnded()
		assert(events == 1, "re-entrant cleanup duplicated completion")
		assert(animator.tracks[1].calls.destroy == 1 and animator.animations[1].destroyed, "re-entrant cleanup leaked physics")
		assert(animator.tracks[1].Stopped:getConnectionCount() == 0, "re-entrant cleanup leaked Stopped")
		assert(animator.tracks[1].Ended:getConnectionCount() == 0, "re-entrant cleanup leaked Ended")
	end)

	return testCount
end)

transformed.cleanup()
assert(ok, result)

return result

--!strict
--!optimize 2

-- Host benchmark: keep the runner identical for the before/after captures.
local requireAny = require :: any
local process = requireAny("@lune/process")
local fs = requireAny("@lune/fs")
local serde = requireAny("@lune/serde")
local ModuleLoader = requireAny(process.cwd .. "/tests/lune/lib/moduleLoader.luau")
local fakeRobloxPath = (process.cwd:gsub("\\", "/")) .. "/tests/lune/fixtures/fakeRoblox.luau"
local FakeRoblox = requireAny(fakeRobloxPath)
local transformed = ModuleLoader.write({
	sourceRoot = "src",
	tempDir = "evaluation-benchmark",
	preamble = "local __fakeRoblox = require([["
		.. fakeRobloxPath
		.. "]])\nlocal Instance = __fakeRoblox.Instance\nlocal Enum = __fakeRoblox.Enum",
})

local ok, failure = pcall(function(): unknown
	local AnimGraph = transformed.requireModule("init.luau") :: any
	local iterations = tonumber(process.env.ANIMGRAPH_BENCH_ITERATIONS) or 20000
	local rounds = tonumber(process.env.ANIMGRAPH_BENCH_ROUNDS) or 7
	local results = {}

	local function newSink(): any
		local sink = { checksum = 0 }
		function sink:apply(_time, requests)
			for _, request in requests do
				self.checksum += request.weight + request.speed
			end
		end
		function sink:bindToTrackCompleted(_callback)
			return function() end
		end
		function sink:stopLayer(_layer, _fade) end
		function sink:clear() end
		function sink:destroy() end
		return sink
	end

	local function runCase(name: string, kind: string, size: number): ()
		local timings = {}
		local checksum = 0
		for round = 1, rounds do
			local sink = newSink()
			local backend = if kind == "native"
				then AnimGraph.robloxAnimatorBackend.new({
					animator = FakeRoblox.newAnimator(10),
					resolveAssetId = function(_clip)
						return 123
					end,
				})
				else sink
			local timeSample = { position = 0, rate = 1 }
			local controller = AnimGraph.new({
				backend = backend,
				timeReader = function(coordinate)
					timeSample.position = coordinate
					return timeSample
				end,
			})
			local motion
			if kind == "blend1D" then
				local samples = {}
				for index = 1, size do
					samples[index] = { threshold = index - 1, motion = AnimGraph.clip(tostring(index)) }
				end
				motion = AnimGraph.blend1D("x", { samples = samples })
			elseif kind == "blend2D" then
				local samples = {}
				for x = 0, size - 1 do
					for y = 0, size - 1 do
						samples[#samples + 1] = { x = x, y = y, motion = AnimGraph.clip(`{x}:{y}`) }
					end
				end
				motion = AnimGraph.blend2D("x", "y", { samples = samples, maxInfluences = 4 })
			else
				motion = AnimGraph.clip("idle", { looped = true })
			end
			local layerCount = if kind == "native" then size else 1
			for layer = 1, layerCount do
				controller:addLayer({ id = layer })
				controller:play(layer, motion)
			end
			local coordinate = 0
			local function step(count: number): ()
				for index = 1, count do
					coordinate += 1 / 60
					if kind == "blend1D" or kind == "blend2D" then
						controller:setFloat("x", 0.13 + ((index * 17) % 997) / 997 * (size - 1.3))
						if kind == "blend2D" then
							controller:setFloat("y", 0.21 + ((index * 31) % 991) / 991 * (size - 1.4))
						end
					end
					controller:update(coordinate)
				end
			end
			step(2000)
			local start = os.clock()
			step(iterations)
			local elapsed = os.clock() - start
			timings[round] = elapsed
			checksum += sink.checksum
			controller:destroy()
		end
		results[#results + 1] = { name = name, seconds = timings, checksum = checksum }
		local sorted = table.clone(timings)
		table.sort(sorted)
		print(
			string.format(
				"BENCH %s: median %.3f us/update (%d updates, %d rounds)",
				name,
				sorted[math.ceil(rounds / 2)] * 1e6 / iterations,
				iterations,
				rounds
			)
		)
	end

	runCase("clip-sink", "clip", 1)
	runCase("blend1D-16-sink", "blend1D", 16)
	runCase("blend2D-16-sink", "blend2D", 4)
	runCase("blend2D-64-sink", "blend2D", 8)
	runCase("native-8-layers", "native", 8)
	fs.writeFile(
		assert(process.env.ANIMGRAPH_BENCH_OUTPUT, "Run through scripts/bench/run.ps1"),
		serde.encode("json", { iterations = iterations, rounds = rounds, results = results }, true)
	)
	return nil
end)
transformed.cleanup()
if not ok then
	error(failure, 0)
end

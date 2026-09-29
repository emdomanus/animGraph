--!strict

local requireAny = require :: any
local process = requireAny("@lune/process")
local ModuleLoader = requireAny(process.cwd .. "/tests/lune/lib/moduleLoader.luau")
local fakeRobloxPath = (process.cwd:gsub("\\", "/")) .. "/tests/lune/fixtures/fakeRoblox.luau"
local FakeRoblox = requireAny(fakeRobloxPath)
local transformed = ModuleLoader.write({
	sourceRoot = "src",
	tempDir = "evaluation-reuse",
	preamble = "local __fakeRoblox = require([["
		.. fakeRobloxPath
		.. "]])\nlocal Instance = __fakeRoblox.Instance\nlocal Enum = __fakeRoblox.Enum",
})

local ok, result = pcall(function(): number
	local AnimGraph = transformed.requireModule("animGraph/init.luau") :: any
	local RequestValidation = transformed.requireModule("animGraph/utils/requestValidation.luau") :: any
	local count = 0
	local function test(name: string, callback: () -> ()): ()
		callback()
		count += 1
		print("PASS evaluation reuse: " .. name)
	end
	local function context(x: number, y: number): any
		return {
			layer = "body",
			state = "idle",
			timePosition = 0,
			timeRate = 1,
			fadeTime = 0,
			layerWeight = 1,
			layerSpeed = 1,
			logicalPriority = 0,
			getParameter = function(parameter)
				return if parameter == "x" then x else y
			end,
			consumeTrigger = function(_parameter)
				return false
			end,
			emitEvent = function(_event) end,
		}
	end
	local function assertRequestsEqual(actual: any, expected: any): ()
		assert(#actual == #expected, "request count changed")
		for index, request in expected do
			assert(actual[index].clip == request.clip, "request order changed")
			assert(actual[index].weight == request.weight, "request weight changed")
		end
	end

	for _, kind in { "1D", "2D" } do
		test(kind .. " nested evaluation preserves outer weights and retained requests", function(): ()
			local node
			local reenter = false
			local fail = false
			local function makeNode(withCallback: boolean): any
				local samples = {}
				for index = 1, 4 do
					local clip = AnimGraph.clip(tostring(index))
					local motion = clip
					if withCallback then
						motion = {
							evaluate = function(_, evaluationContext)
								if fail then
									fail = false
									error("child evaluation failed")
								end
								if reenter then
									reenter = false
									node:evaluate(context(0.2, 0.8))
								end
								return clip:evaluate(evaluationContext)
							end,
							getDebugSnapshot = function()
								return clip:getDebugSnapshot()
							end,
						}
					end
					samples[index] =
						{ threshold = index - 1, x = (index - 1) % 2, y = math.floor((index - 1) / 2), motion = motion }
				end
				return if kind == "1D"
					then AnimGraph.blend1D("x", { samples = samples })
					else AnimGraph.blend2D("x", "y", { samples = samples })
			end
			node = makeNode(true)
			local reference = makeNode(false)
			local outerContext = context(0.65, 0.35)
			local expected = reference:evaluate(outerContext)
			reenter = true
			local retained = node:evaluate(outerContext)
			assertRequestsEqual(retained, expected)
			local debugSnapshot = node:getDebugSnapshot()
			local savedWeight = debugSnapshot.children[1].details.weight
			node:evaluate(context(0, 0))
			node:evaluate(context(0.5, 0.5))
			assertRequestsEqual(node:evaluate(outerContext), expected)
			assertRequestsEqual(retained, expected)
			assert(debugSnapshot.children[1].details.weight == savedWeight, "retained debug snapshot mutated")
			fail = true
			local succeeded = pcall(function()
				node:evaluate(outerContext)
			end)
			assert(not succeeded, "expected child failure")
			assertRequestsEqual(node:evaluate(outerContext), expected)
		end)
	end

	test("validation recovers after rejection and nested validation", function(): ()
		local request = AnimGraph.clip("idle"):evaluate(context(0, 0))[1]
		local succeeded = pcall(function()
			RequestValidation.validate({ request, request })
		end)
		assert(not succeeded, "duplicate key was accepted")
		RequestValidation.validate({ request })
		local nested = false
		local borrowed = setmetatable({}, {
			__index = function(_, key)
				if not nested then
					nested = true
					RequestValidation.validate({ request })
				end
				return request[key]
			end,
		})
		RequestValidation.validate({ borrowed })
		RequestValidation.validate({ request })
	end)

	test("nested backend apply cannot overwrite outer touched keys", function(): ()
		local backend
		local nested = false
		local first = AnimGraph.clip("first", { looped = true }):evaluate(context(0, 0))[1]
		local second = AnimGraph.clip("second", { looped = true }):evaluate(context(0, 0))[1]
		backend = AnimGraph.robloxAnimatorBackend.new({
			animator = FakeRoblox.newAnimator(10),
			defaultFadeOut = 0,
			resolveAssetId = function(clip)
				if clip == "second" and not nested then
					nested = true
					backend:apply(1, { first })
				end
				return 123
			end,
		})
		backend:apply(0, { first })
		backend:apply(1, { second })
		local tracks = backend:getDebugSnapshot().tracks
		assert(#tracks == 1 and tracks[1].clip == "second", "outer apply lost its touched-key set")
		backend:destroy()
	end)

	test("controller batches remain independent across updates", function(): ()
		local batches = {}
		local backend = {
			apply = function(_, _time, requests)
				batches[#batches + 1] = requests
			end,
			bindToTrackCompleted = function()
				return function() end
			end,
			clear = function() end,
			destroy = function() end,
		}
		local controller = AnimGraph.new({
			backend = backend,
			layers = { { id = "body" } },
			timeReader = function(time)
				return { position = time, rate = 1 }
			end,
		})
		controller:play("body", AnimGraph.clip("idle"))
		controller:update(0)
		controller:setLayerWeight("body", 0.25)
		controller:update(1)
		assert(batches[1] ~= batches[2] and batches[1][1] ~= batches[2][1], "batch storage was reused")
		assert(batches[1][1].weight == 1 and batches[2][1].weight == 0.25, "retained batch was mutated")
		controller:destroy()
	end)
	return count
end)
transformed.cleanup()
if not ok then
	error(result, 0)
end
return result

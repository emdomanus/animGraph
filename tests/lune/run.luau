--!strict
--!optimize 2

local requireAny = require :: any
local process = requireAny("@lune/process")

local suites = {
	process.cwd .. "/tests/lune/smoke.spec.luau",
	process.cwd .. "/tests/lune/controller.spec.luau",
	process.cwd .. "/tests/lune/trackMarkers.spec.luau",
	process.cwd .. "/tests/lune/evaluationReuse.spec.luau",
	process.cwd .. "/tests/lune/robloxAnimatorBackend.spec.luau",
	process.cwd .. "/tests/lune/sampledRobloxAnimatorBackend.spec.luau",
}

local testCount = 0
for _, suite in suites do
	local ok, result = pcall(requireAny, suite)
	if not ok then
		error(`{suite} failed: {result}`, 0)
	end
	assert(result == true or typeof(result) == "number", `{suite} did not report success`)
	testCount += if typeof(result) == "number" then result else 1
	print(`PASS suite {suite}`)
end

print(`PASS {testCount} test(s) across {#suites} suite(s)`)

--!strict
--!optimize 2
local requireAny = require :: any
local process = requireAny("@lune/process")
local task = requireAny("@lune/task")
local fs = requireAny("@lune/fs")
local transform = requireAny("../lib/moduleLoader")
local mode = process.env.ANIMGRAPH_HARNESS_CASE
local package = transform.write({
	sourceRoot = if mode == "setup-failure" then "missing-animgraph-fixture" else "src",
	tempDir = "lifecycle",
})
local animGraph = package.requireModule("animGraph/components/stackModifier/shared/stackModifier.luau")
assert(animGraph.new ~= nil, "transformed package must export its constructor")
if mode == "test-failure" then
	error("intentional harness fixture failure")
elseif mode == "concurrent" then
	print("RUNTIME=" .. process.env.ANIMGRAPH_LUNE_RUNTIME)
	task.wait(1)
	assert(fs.isDir(process.env.ANIMGRAPH_LUNE_RUNTIME), "another run must not remove this runtime")
	assert(
		package.requireModule("animGraph/components/stackModifier/shared/stackModifier.luau") == animGraph,
		"concurrent runtime must remain readable"
	)
end

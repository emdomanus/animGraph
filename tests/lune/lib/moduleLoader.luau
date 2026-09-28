--!strict

local requireAny = require :: any
local fs = requireAny("@lune/fs")
local process = requireAny("@lune/process")

export type LoaderOptions = {
	sourceRoot: string,
	tempDir: string,
	preamble: string?,
}

export type LoaderHandle = {
	requireModule: (relativePath: string) -> any,
	cleanup: () -> (),
}

local ModuleLoader = {}
local runtimeSequence = 0

local function normalizePath(path: string): string
	return (path:gsub("\\", "/"))
end

local function joinPath(left: string, right: string): string
	if left:sub(-1) == "/" or left:sub(-1) == "\\" then
		return left .. right
	end

	return left .. "/" .. right
end

local function resolveFromCwd(path: string): string
	local normalized = normalizePath(path)
	if normalized:match("^%a:/") or normalized:sub(1, 1) == "/" then
		return normalized
	end

	return joinPath(process.cwd, normalized)
end

local function dirname(path: string): string
	return normalizePath(path):match("^(.*)/[^/]+$") or ""
end

local function discoverModules(sourceRoot: string): { string }
	local modules: { string } = {}

	local function visit(directoryPath: string, directoryRelativePath: string): ()
		for _, entry in fs.readDir(directoryPath) do
			local entryPath = joinPath(directoryPath, entry)
			local entryRelativePath = if directoryRelativePath == ""
				then entry
				else directoryRelativePath .. "/" .. entry

			if fs.isDir(entryPath) then
				visit(entryPath, entryRelativePath)
			elseif fs.isFile(entryPath) and entry:sub(-5) == ".luau" then
				modules[#modules + 1] = entryRelativePath
			end
		end
	end

	visit(sourceRoot, "")
	table.sort(modules)
	return modules
end

local function moduleSegments(relativePath: string): { string }
	local segments: { string } = {}
	for segment in normalizePath(relativePath):gsub("%.luau$", ""):gmatch("[^/]+") do
		segments[#segments + 1] = segment
	end
	if segments[#segments] == "init" then
		table.remove(segments)
	end

	return segments
end

local function relativePathFromSegments(segments: { string }, moduleSet: { [string]: true }): string
	local base = table.concat(segments, "/")
	local initPath = if base == "" then "init.luau" else base .. "/init.luau"
	if moduleSet[initPath] then
		return initPath
	end

	return base .. ".luau"
end

local function resolveScriptRequire(
	moduleRelativePath: string,
	expression: string,
	tempRoot: string,
	moduleSet: { [string]: true }
): string
	local segments = moduleSegments(moduleRelativePath)
	local firstToken = true
	for token in expression:gmatch("[A-Za-z_][A-Za-z0-9_]*") do
		if firstToken then
			firstToken = false
		elseif token == "Parent" then
			table.remove(segments)
		else
			segments[#segments + 1] = token
		end
	end

	return joinPath(tempRoot, relativePathFromSegments(segments, moduleSet))
end

function ModuleLoader.write(options: LoaderOptions): LoaderHandle
	local sourceRoot = resolveFromCwd(options.sourceRoot)
	local ownedRoot = assert(process.env.ANIMGRAPH_LUNE_RUNTIME, "Run through scripts/verify/tests.ps1")
	runtimeSequence += 1
	local label = options.tempDir:gsub("[^%w_-]", "-")
	local tempRoot = joinPath(ownedRoot, label .. "-" .. tostring(runtimeSequence))
	local modules = discoverModules(sourceRoot)
	local moduleSet: { [string]: true } = {}

	assert(not fs.isDir(tempRoot), "owned module runtime must be unique")
	fs.writeDir(tempRoot)

	for _, relativePath in modules do
		moduleSet[relativePath] = true
	end

	for _, relativePath in modules do
		local source = fs.readFile(joinPath(sourceRoot, relativePath))
		local transformed = source:gsub("require%(%s*(script[^%)]*)%)", function(expression)
			local dependencyPath = resolveScriptRequire(relativePath, expression, tempRoot, moduleSet)
			return "require([[" .. dependencyPath .. "]])"
		end)
		if options.preamble ~= nil then
			transformed = options.preamble .. "\n" .. transformed
		end
		local targetPath = joinPath(tempRoot, relativePath)
		local targetDirectory = dirname(targetPath)
		if targetDirectory ~= "" then
			fs.writeDir(targetDirectory)
		end
		fs.writeFile(targetPath, transformed)
	end

	return {
		requireModule = function(relativePath: string): any
			return requireAny(joinPath(tempRoot, relativePath))
		end,
		cleanup = function(): ()
			-- The guarded runner reclaims this entire owned run in protected cleanup.
		end,
	}
end

return ModuleLoader

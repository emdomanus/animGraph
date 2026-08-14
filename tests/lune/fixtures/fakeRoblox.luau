--!strict

local FakeRoblox = {}

FakeRoblox.Enum = {
	AnimationPriority = {
		Core = "Core",
		Idle = "Idle",
		Movement = "Movement",
		Action = "Action",
		Action2 = "Action2",
		Action3 = "Action3",
		Action4 = "Action4",
	},
}

local animations: { any } = {}

local function newAnimation(): any
	local fields = {
		AnimationId = "",
	}
	local animation = setmetatable({}, {
		__index = function(_, key)
			if key == "Destroy" then
				return function()
					fields.destroyed = true
				end
			end
			return fields[key]
		end,
		__newindex = function(_, key, value)
			fields[key] = value
		end,
	})
	animations[#animations + 1] = animation
	return animation
end

FakeRoblox.Instance = {
	new = function(className: string): any
		assert(className == "Animation", "fake Instance only supports Animation")
		return newAnimation()
	end,
}

function FakeRoblox.newTrack(length: number?): any
	local fields = {
		IsPlaying = false,
		Length = length or 10,
		TimePosition = 0,
		Looped = false,
		Priority = nil,
	}
	local calls = {
		play = 0,
		adjustWeight = 0,
		adjustSpeed = 0,
		stop = 0,
		destroy = 0,
		loopedWrites = 0,
		priorityWrites = 0,
		positionWrites = {} :: { number },
		weights = {} :: { { weight: number, fadeTime: number } },
		speeds = {} :: { number },
	}

	local track = setmetatable({}, {
		__index = function(_, key)
			if key == "calls" then
				return calls
			elseif key == "setLength" then
				return function(_, value: number)
					fields.Length = value
				end
			elseif key == "setEnginePlaying" then
				return function(_, value: boolean)
					fields.IsPlaying = value
				end
			elseif key == "setEngineTimePosition" then
				return function(_, value: number)
					fields.TimePosition = value
				end
			elseif key == "Play" then
				return function(_, _fadeTime: number, _weight: number, _speed: number)
					calls.play += 1
					fields.IsPlaying = true
					fields.TimePosition = 0
				end
			elseif key == "AdjustWeight" then
				return function(_, weight: number, fadeTime: number)
					calls.adjustWeight += 1
					calls.weights[#calls.weights + 1] = { weight = weight, fadeTime = fadeTime }
				end
			elseif key == "AdjustSpeed" then
				return function(_, speed: number)
					calls.adjustSpeed += 1
					calls.speeds[#calls.speeds + 1] = speed
				end
			elseif key == "Stop" then
				return function(_, _fadeTime: number)
					calls.stop += 1
					fields.IsPlaying = false
				end
			elseif key == "Destroy" then
				return function()
					calls.destroy += 1
				end
			end
			return fields[key]
		end,
		__newindex = function(_, key, value)
			fields[key] = value
			if key == "TimePosition" then
				calls.positionWrites[#calls.positionWrites + 1] = value
			elseif key == "Looped" then
				calls.loopedWrites += 1
			elseif key == "Priority" then
				calls.priorityWrites += 1
			end
		end,
	})

	return track
end

function FakeRoblox.newAnimator(defaultLength: number?): any
	local animator = {
		loadCount = 0,
		tracks = {} :: { any },
		defaultLength = if defaultLength ~= nil then defaultLength else 10,
	}

	function animator:LoadAnimation(_animation): any
		self.loadCount += 1
		local track = FakeRoblox.newTrack(self.defaultLength)
		self.tracks[#self.tracks + 1] = track
		return track
	end

	return animator
end

function FakeRoblox.getAnimationCount(): number
	return #animations
end

return FakeRoblox

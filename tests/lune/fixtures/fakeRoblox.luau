--!strict
--!optimize 2

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

local function newSignal(): any
	local listeners: { any } = {}
	local signal = {}

	function signal:Connect(callback): any
		local connection = {
			Connected = true,
		}
		function connection.Disconnect(activeConnection): ()
			if not activeConnection.Connected then
				return
			end
			activeConnection.Connected = false
			for index = #listeners, 1, -1 do
				if listeners[index] == callback then
					table.remove(listeners, index)
					break
				end
			end
		end
		listeners[#listeners + 1] = callback
		return connection
	end

	function signal:Fire(...): ()
		for _, callback in table.clone(listeners) do
			callback(...)
		end
	end

	function signal:capture(): (...any) -> ()
		local captured = table.clone(listeners)
		return function(...)
			for _, callback in captured do
				callback(...)
			end
		end
	end

	function signal:getConnectionCount(): number
		return #listeners
	end

	return signal
end

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
		Stopped = newSignal(),
		Ended = newSignal(),
		markerSignals = {},
	}
	local calls = {
		play = 0,
		playSpeeds = {} :: { number },
		adjustWeight = 0,
		adjustSpeed = 0,
		stop = 0,
		destroy = 0,
		loopedWrites = 0,
		priorityWrites = 0,
		positionReads = 0,
		positionWrites = {} :: { number },
		weights = {} :: { { weight: number, fadeTime: number } },
		speeds = {} :: { number },
		stopFades = {} :: { number },
		order = {} :: { { operation: string, value: number } },
	}

	local track = setmetatable({}, {
		__index = function(_, key)
			if key == "calls" then
				return calls
			elseif key == "TimePosition" then
				calls.positionReads += 1
				return fields.TimePosition
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
			elseif key == "fireStopped" then
				return function()
					fields.IsPlaying = false
					fields.Stopped:Fire()
				end
			elseif key == "fireEnded" then
				return function()
					fields.IsPlaying = false
					fields.Ended:Fire()
				end
			elseif key == "GetMarkerReachedSignal" then
				return function(_, markerName: string)
					local signal = fields.markerSignals[markerName]
					if signal == nil then
						signal = newSignal()
						fields.markerSignals[markerName] = signal
					end
					return signal
				end
			elseif key == "Play" then
				return function(_, _fadeTime: number, _weight: number, speed: number)
					calls.play += 1
					calls.playSpeeds[#calls.playSpeeds + 1] = speed
					calls.order[#calls.order + 1] = { operation = "Play", value = speed }
					fields.IsPlaying = true
					fields.TimePosition = 0
					if fields.onPlay ~= nil then
						fields.onPlay()
					end
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
					calls.order[#calls.order + 1] = { operation = "AdjustSpeed", value = speed }
				end
			elseif key == "Stop" then
				return function(_, fadeTime: number)
					calls.stop += 1
					calls.stopFades[#calls.stopFades + 1] = fadeTime
					fields.IsPlaying = false
					fields.Stopped:Fire()
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
				calls.order[#calls.order + 1] = { operation = "TimePosition", value = value }
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
		animations = {} :: { any },
		defaultLength = if defaultLength ~= nil then defaultLength else 10,
	}

	function animator:LoadAnimation(animation): any
		self.loadCount += 1
		local track = FakeRoblox.newTrack(self.defaultLength)
		self.tracks[#self.tracks + 1] = track
		self.animations[#self.animations + 1] = animation
		return track
	end

	return animator
end

function FakeRoblox.getAnimationCount(): number
	return #animations
end

return FakeRoblox

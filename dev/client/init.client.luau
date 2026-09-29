--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AnimGraph = require(ReplicatedStorage:WaitForChild("packages"):WaitForChild("animGraph"))

local DEV_ROOT_NAME = "AnimGraphDev"
local GUI_NAME = "AnimGraphDevHarness"
local DUMMY_NAME = "AnimGraphR6Dummy"
local DUMMY_POSITION = Vector3.new(0, 1000, 0)
local DUMMY_PIVOT = CFrame.new(DUMMY_POSITION)
local LIFECYCLE_TRACK_KEY = "dev/action/lifecycle"
local BACKEND_POSITION_MODE: AnimGraph.BackendPositionMode = "nativeRate"

type Layer = "base" | "action"
type State = "empty" | "locomotion" | "idle" | "walk" | "jump" | "wave" | "cheer" | "dance"
type Param = "speed" | "waveTrigger" | "cheerTrigger" | "danceTrigger" | "clearAction"
type Clip = "idle" | "walk" | "jump" | "wave" | "cheer" | "dance"
type LayerBackend = AnimGraph.RobloxLayerBackend

type AnimationPosition = AnimGraph.AnimationPosition

type TestButton = {
	text: string,
	callback: () -> (),
}

type ControlGrid = {
	frame: Frame,
	layout: UIGridLayout,
}

type SequenceStep = {
	at: number,
	label: string,
	run: () -> (),
}

local ANIMATION_IDS: { [Clip]: number } = {
	idle = 180435571,
	walk = 180426354,
	jump = 125750702,
	wave = 128777973,
	cheer = 129423030,
	dance = 182435998,
}

local CP_AG_R_UPPER: AnimationPosition = { kind = "normalized", value = 1 }
local CP_AG_R_LOWER: AnimationPosition = { kind = "seconds", value = 0 }

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldRoot = Workspace:FindFirstChild(DEV_ROOT_NAME)
if oldRoot ~= nil then
	oldRoot:Destroy()
end

local oldGui = playerGui:FindFirstChild(GUI_NAME)
if oldGui ~= nil then
	oldGui:Destroy()
end

local devRoot = Instance.new("Folder")
devRoot.Name = DEV_ROOT_NAME
devRoot.Parent = Workspace

local logLines: { string } = {}
local consoleLabel: TextLabel? = nil
local summaryLabel: TextLabel? = nil
local debugLabel: TextLabel? = nil
local panelFrame: Frame? = nil
local controlsScroller: ScrollingFrame? = nil
local controlsContentLayout: UIListLayout? = nil
local consoleToggleButton: TextButton? = nil
local consoleScroller: ScrollingFrame? = nil
local consoleContentLayout: UIListLayout? = nil
local controlGridLayouts: { ControlGrid } = {}

local controller: AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend>? = nil
local releaseUpdate: (() -> ())? = nil
local debugConnection: RBXScriptConnection? = nil
local cameraConnection: RBXScriptConnection? = nil
local nativeAnimator: Animator? = nil
local nativeTracks: { AnimationTrack } = {}
local nativeTrackIds: { [AnimationTrack]: number } = {}
local nativeConnections: { RBXScriptConnection } = {}
local nativePlayCount = 0
local evidenceSequence = 0
local cameraTarget: Model? = nil
local activeActionClip: Clip = "wave"
local baseWeight = 1
local actionWeight = 1
local actionPriority = 100
local basePlaybackRate = 1
local actionPlaybackRate = 1
local actionRobloxPriority: Enum.AnimationPriority? = nil
local speedValue = 0
local consoleExpanded = false
local sequenceToken = 0
local activeSequenceName = "none"
local baseTimePosition = 0
local actionTimePosition = 0
local baseTimeAnchor = os.clock()
local actionTimeAnchor = baseTimeAnchor
local baseTimeHeld = false
local actionTimeHeld = false

local function appendLog(message: string): ()
	print("[AnimGraphDev] " .. message)

	logLines[#logLines + 1] = message
	if #logLines > 80 then
		table.remove(logLines, 1)
	end

	local label = consoleLabel
	if label ~= nil then
		label.Text = table.concat(logLines, "\n")
	end

	local scroller = consoleScroller
	local layout = consoleContentLayout
	if scroller ~= nil and layout ~= nil then
		scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
		scroller.CanvasPosition = Vector2.new(0, math.max(layout.AbsoluteContentSize.Y - scroller.AbsoluteSize.Y, 0))
	end
end

local function appendEvidence(message: string): ()
	evidenceSequence += 1
	appendLog(string.format("evidence %03d %s", evidenceSequence, message))
end

local function formatNativeTrack(track: AnimationTrack): string
	local trackId = nativeTrackIds[track] or -1
	local animation = track.Animation
	return string.format(
		"native=%d asset=%s length=%.4f position=%.4f speed=%.2f playing=%s looped=%s",
		trackId,
		animation.AnimationId,
		track.Length,
		track.TimePosition,
		track.Speed,
		tostring(track.IsPlaying),
		tostring(track.Looped)
	)
end

local function appendNativeTrackState(track: AnimationTrack, eventName: string): ()
	appendEvidence(eventName .. " " .. formatNativeTrack(track))
end

local function dumpNativeTrackStates(label: string): ()
	appendEvidence(label .. " nativePlayCount=" .. tostring(nativePlayCount) .. " tracks=" .. tostring(#nativeTracks))
	for _, track in nativeTracks do
		appendNativeTrackState(track, "native state")
	end
end

local function connectNativeEvidence(animator: Animator): ()
	nativeAnimator = animator
	local animationPlayedConnection = animator.AnimationPlayed:Connect(function(track: AnimationTrack)
		nativePlayCount += 1
		nativeTracks[#nativeTracks + 1] = track
		nativeTrackIds[track] = nativePlayCount
		appendNativeTrackState(track, "AnimationPlayed")

		local observedFirstPositionChange = false
		nativeConnections[#nativeConnections + 1] = track:GetPropertyChangedSignal("TimePosition"):Connect(function()
			if observedFirstPositionChange then
				return
			end
			observedFirstPositionChange = true
			appendNativeTrackState(track, "first TimePosition change")
		end)
		nativeConnections[#nativeConnections + 1] = track:GetPropertyChangedSignal("Length"):Connect(function()
			appendNativeTrackState(track, "Length changed")
		end)
		nativeConnections[#nativeConnections + 1] = track:GetPropertyChangedSignal("Speed"):Connect(function()
			appendNativeTrackState(track, "Speed changed")
		end)
		nativeConnections[#nativeConnections + 1] = track.Stopped:Connect(function()
			appendNativeTrackState(track, "Stopped")
		end)
		nativeConnections[#nativeConnections + 1] = track.Ended:Connect(function()
			appendNativeTrackState(track, "Ended")
		end)
		nativeConnections[#nativeConnections + 1] = track.DidLoop:Connect(function()
			appendNativeTrackState(track, "DidLoop")
		end)
		nativeConnections[#nativeConnections + 1] = track.Destroying:Connect(function()
			appendEvidence("Destroying native=" .. tostring(nativeTrackIds[track] or -1))
		end)
	end)
	nativeConnections[#nativeConnections + 1] = animationPlayedConnection
end

local function clearLog(): ()
	logLines = {}
	local label = consoleLabel
	if label ~= nil then
		label.Text = ""
	end

	local scroller = consoleScroller
	if scroller ~= nil then
		scroller.CanvasPosition = Vector2.zero
	end
end

local function setSummary(message: string): ()
	local label = summaryLabel
	if label ~= nil then
		label.Text = message
	end
end

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

local function formatWeight(value: number): string
	return string.format("%.2f", value)
end

local function formatSpeed(value: number): string
	return string.format("%.1f", value)
end

local function updateSummary(): ()
	local priorityText = if actionRobloxPriority ~= nil then tostring(actionRobloxPriority) else "auto"

	setSummary(
		string.format(
			"locomotion=%s  base=%s  action=%s  actionPriority=%d/%s  active=%s  sequence=%s",
			formatSpeed(speedValue),
			if baseTimeHeld then "held" else "advancing",
			if actionTimeHeld then "held" else "advancing",
			actionPriority,
			priorityText,
			activeActionClip,
			activeSequenceName
		)
	)
end

local function sampleTime(time: number, layer: Layer): AnimGraph.TimeSample
	if layer == "base" then
		return {
			position = baseTimePosition + (if baseTimeHeld then 0 else math.max(time - baseTimeAnchor, 0)),
			rate = if baseTimeHeld then 0 else 1,
		}
	end

	return {
		position = actionTimePosition + (if actionTimeHeld then 0 else math.max(time - actionTimeAnchor, 0)),
		rate = if actionTimeHeld then 0 else 1,
	}
end

local function baseTimeReader(time: number): AnimGraph.TimeSample
	return sampleTime(time, "base")
end

local function actionTimeReader(time: number): AnimGraph.TimeSample
	return sampleTime(time, "action")
end

local function getController(): AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend>
	local activeController = controller
	assert(activeController ~= nil, "AnimGraph dev controller is not ready")

	return activeController
end

local function makeClipNode(clip: Clip): AnimGraph.ClipNode<Layer, State, Param, Clip, LayerBackend>
	return AnimGraph.clipNode.new(clip) :: any
end

local function triggerCondition(parameter: Param): AnimGraph.TransitionCondition<Param>
	return {
		parameter = parameter,
		op = "trigger" :: AnimGraph.TransitionConditionOp,
	}
end

local function makeLocomotionBlend(): AnimGraph.Blend1DNode<Layer, State, Param, Clip, LayerBackend>
	local samples: { AnimGraph.Blend1DSample<Layer, State, Param, Clip, LayerBackend> } = {
		{
			threshold = 0,
			motion = makeClipNode("idle"),
		},
		{
			threshold = 8,
			motion = makeClipNode("walk"),
		},
	}
	local config: AnimGraph.Blend1DNodeConfig<Layer, State, Param, Clip, LayerBackend> = {
		name = "LocomotionBlend",
		defaultValue = 0,
		samples = samples,
	}

	local newBlend = AnimGraph.blend1D :: (
		Param,
		AnimGraph.Blend1DNodeConfig<Layer, State, Param, Clip, LayerBackend>
	) -> AnimGraph.Blend1DNode<Layer, State, Param, Clip, LayerBackend>
	return newBlend("speed" :: Param, config)
end

local function makeActionStateMachine(): AnimGraph.StateMachineRuntime<Layer, State, Param, Clip, LayerBackend>
	local states: { AnimGraph.StateDefinition<Layer, State, Param, Clip, LayerBackend> } = {
		{
			id = "empty",
		},
		{
			id = "wave",
			motion = makeClipNode("wave"),
		},
		{
			id = "cheer",
			motion = makeClipNode("cheer"),
		},
		{
			id = "dance",
			motion = makeClipNode("dance"),
		},
	}

	local transitions: { AnimGraph.TransitionDefinition<State, Param> } = {
		{
			name = "any -> wave",
			to = "wave",
			duration = 0.12,
			priority = 30,
			conditions = {
				triggerCondition("waveTrigger"),
			},
		},
		{
			name = "any -> cheer",
			to = "cheer",
			duration = 0.12,
			priority = 20,
			conditions = {
				triggerCondition("cheerTrigger"),
			},
		},
		{
			name = "any -> dance",
			to = "dance",
			duration = 0.12,
			priority = 10,
			conditions = {
				triggerCondition("danceTrigger"),
			},
		},
		{
			name = "clear action",
			to = "empty",
			duration = 0.12,
			priority = 100,
			conditions = {
				triggerCondition("clearAction"),
			},
		},
	}

	local config: AnimGraph.StateMachineConfig<Layer, State, Param, Clip, LayerBackend> = {
		name = "ActionStateMachine",
		initialState = "empty",
		states = states,
		transitions = transitions,
	}

	local stateMachineFactory = AnimGraph.stateMachine :: any
	return stateMachineFactory(config) :: any
end

local function destroyScripts(root: Instance): ()
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
end

local function prepareParts(root: Instance): ()
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

local function getRootPart(model: Model): BasePart
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChild("Torso")

	assert(root ~= nil and root:IsA("BasePart"), "dev rig is missing a root part")
	return root
end

local function createDummy(): (Model, Animator)
	local description = Instance.new("HumanoidDescription")
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	description:Destroy()

	assert(ok, "failed to create R6 humanoid model: " .. tostring(result))

	local model = result :: Model
	model.Name = DUMMY_NAME
	destroyScripts(model)
	prepareParts(model)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid ~= nil, "dev rig is missing a Humanoid")
	humanoid.AutoRotate = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local animatorCandidate = humanoid:FindFirstChildOfClass("Animator")
	local resolvedAnimator: Animator
	if animatorCandidate ~= nil then
		resolvedAnimator = animatorCandidate
	else
		local createdAnimator = Instance.new("Animator")
		createdAnimator.Parent = humanoid
		resolvedAnimator = createdAnimator
	end

	local rootPart = getRootPart(model)
	model.PrimaryPart = rootPart
	model.Parent = devRoot
	model:PivotTo(DUMMY_PIVOT * CFrame.Angles(0, math.pi, 0))
	rootPart.Anchored = true

	return model, resolvedAnimator
end

local function getCameraCFrame(model: Model): (CFrame, CFrame)
	local target = model:GetPivot().Position + Vector3.new(0, 1.8, 0)
	local cameraPosition = target + Vector3.new(0, 1.2, 11)
	local rightBiasedLookAt = target + Vector3.new(-3.5, 0, 0)

	return CFrame.lookAt(cameraPosition, rightBiasedLookAt), CFrame.new(target)
end

local function applyCamera(model: Model): ()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
		camera = Workspace.CurrentCamera
	end
	if camera == nil then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil

	local cframe, focus = getCameraCFrame(model)
	camera.CFrame = cframe
	camera.Focus = focus
end

local function setupCamera(model: Model): ()
	cameraTarget = model
	applyCamera(model)

	local activeConnection = cameraConnection
	if activeConnection ~= nil then
		activeConnection:Disconnect()
	end

	cameraConnection = RunService.RenderStepped:Connect(function()
		local target = cameraTarget
		if target ~= nil and target.Parent ~= nil then
			applyCamera(target)
		end
	end)
end

local function setSpeed(value: number): ()
	speedValue = value
	getController():setFloat("speed", speedValue)
	appendLog("speed = " .. tostring(speedValue))
	updateSummary()
end

local function triggerAction(clip: Clip): ()
	activeActionClip = clip
	if clip == "wave" then
		getController():setTrigger("waveTrigger")
	elseif clip == "cheer" then
		getController():setTrigger("cheerTrigger")
	elseif clip == "dance" then
		getController():setTrigger("danceTrigger")
	else
		return
	end

	appendLog("trigger action -> " .. clip .. " priority " .. tostring(actionPriority))
	updateSummary()
end

local function stopAction(): ()
	getController():setTrigger("clearAction")
	appendLog("trigger action clear")
	updateSummary()
end

local function restartAction(): ()
	local clip: Clip = activeActionClip
	stopAction()
	task.delay(0.16, function()
		if controller == nil then
			return
		end

		triggerAction(clip)
	end)
end

local function setTimeHeld(layer: Layer, held: boolean): ()
	local coordinate = os.clock()
	if layer == "base" then
		baseTimePosition = sampleTime(coordinate, "base").position
		baseTimeAnchor = coordinate
		baseTimeHeld = held
	else
		actionTimePosition = sampleTime(coordinate, "action").position
		actionTimeAnchor = coordinate
		actionTimeHeld = held
	end
	appendLog(tostring(layer) .. " time reader = " .. (if held then "held" else "advancing"))
	updateSummary()
end

local function playLifecycleClip(
	clip: Clip,
	looped: boolean,
	forceRestart: boolean?,
	initialPosition: AnimationPosition?
): ()
	activeActionClip = clip
	local node = AnimGraph.clipNode.new(clip, {
		name = "Lifecycle " .. tostring(clip),
		trackKey = LIFECYCLE_TRACK_KEY,
		looped = looped,
	}) :: any
	getController():play("action", node, {
		state = clip :: State,
		trackKey = LIFECYCLE_TRACK_KEY,
		looped = looped,
		fadeTime = 0.6,
		forceRestart = forceRestart == true,
		initialPosition = initialPosition,
		timeReader = actionTimeReader,
	})
	appendLog(
		"lifecycle play clip="
			.. tostring(clip)
			.. " looped="
			.. tostring(looped)
			.. " restart="
			.. tostring(forceRestart == true)
			.. " initialPosition="
			.. (
				if initialPosition == nil
					then "none"
					else initialPosition.kind .. ":" .. tostring(initialPosition.value)
			)
	)
	updateSummary()
end

local function setLifecyclePosition(position: AnimGraph.AnimationPosition, label: string): ()
	appendEvidence("request live " .. label .. " at signed speed " .. formatSpeed(actionPlaybackRate))
	local accepted = getController():setTrackPosition(LIFECYCLE_TRACK_KEY, position)
	appendEvidence("live " .. label .. " accepted=" .. tostring(accepted))
end

local function offsetLifecyclePosition(deltaSeconds: number, label: string): ()
	appendEvidence(
		"request relative "
			.. label
			.. " deltaSeconds="
			.. tostring(deltaSeconds)
			.. " at signed speed "
			.. formatSpeed(actionPlaybackRate)
	)
	local accepted = getController():offsetTrackPosition(LIFECYCLE_TRACK_KEY, deltaSeconds)
	appendEvidence("relative " .. label .. " accepted=" .. tostring(accepted))
end

local function playThenPositionTerminal(): ()
	playLifecycleClip("wave", false, nil, nil)
	task.delay(0.1, function()
		if controller ~= nil then
			setLifecyclePosition({ kind = "normalized", value = 1 }, "terminal")
		end
	end)
end

local function replaceLifecycleClip(): ()
	playLifecycleClip("wave", false, nil, nil)
	task.delay(0.2, function()
		if controller ~= nil then
			playLifecycleClip("cheer", false, nil, nil)
		end
	end)
end

local function reappearDuringFade(): ()
	playLifecycleClip("wave", false, nil, nil)
	task.delay(0.2, function()
		local activeController = controller
		if activeController == nil then
			return
		end
		activeController:stopLayer("action", 1)
		appendLog("lifecycle retiring with 1.0s fade")
	end)
	task.delay(0.35, function()
		if controller ~= nil then
			playLifecycleClip("cheer", false, nil, nil)
		end
	end)
end

local function playLifecycleAt(position: AnimationPosition, label: string): ()
	appendEvidence("requested initial " .. label .. " at signed speed " .. formatSpeed(actionPlaybackRate))
	playLifecycleClip("wave", false, true, position)
end

local function clearPhysicalLifecycle(): ()
	getController():clear()
	appendLog("controller clear: immediate physical cleanup boundary")
end

local function setBaseWeight(value: number): ()
	baseWeight = clamp01(value)
	getController():setLayerWeight("base", baseWeight)
	appendLog("base weight = " .. formatWeight(baseWeight))
	updateSummary()
end

local function setActionWeight(value: number): ()
	actionWeight = clamp01(value)
	getController():setLayerWeight("action", actionWeight)
	appendLog("action weight = " .. formatWeight(actionWeight))
	updateSummary()
end

local function adjustBaseWeight(delta: number): ()
	setBaseWeight(baseWeight + delta)
end

local function adjustActionWeight(delta: number): ()
	setActionWeight(actionWeight + delta)
end

local function setBasePlaybackRate(value: number): ()
	basePlaybackRate = math.max(value, 0)
	getController():setLayerSpeed("base", basePlaybackRate)
	appendLog("base playback rate = " .. formatSpeed(basePlaybackRate))
	updateSummary()
end

local function setActionPlaybackRate(value: number): ()
	actionPlaybackRate = value
	getController():setLayerSpeed("action", actionPlaybackRate)
	appendEvidence("action signed speed = " .. formatSpeed(actionPlaybackRate))
	updateSummary()
end

local function adjustBasePlaybackRate(delta: number): ()
	setBasePlaybackRate(basePlaybackRate + delta)
end

local function adjustActionPlaybackRate(delta: number): ()
	setActionPlaybackRate(actionPlaybackRate + delta)
end

local function runColdZeroToReverse(): ()
	appendEvidence("cold 0-to-negative begin; use first in a fresh Play session")
	setActionPlaybackRate(0)
	playLifecycleClip("wave", false, true, CP_AG_R_UPPER)
	local activeController = getController()
	activeController:update(os.clock())
	dumpNativeTrackStates("cold 0-to-negative after Play(0)")
	setActionPlaybackRate(-1)
	activeController:update(os.clock())
	dumpNativeTrackStates("cold 0-to-negative after desired speed -1")
end

local function runColdOffsetQueue(): ()
	appendEvidence("cold relative queue begin; use first in a fresh Play session")
	setActionPlaybackRate(0)
	playLifecycleClip("cheer", false, true, { kind = "normalized", value = 0.25 })
	local activeController = getController()
	activeController:update(os.clock())
	offsetLifecyclePosition(0.5, "cold +0.5")
	offsetLifecyclePosition(-0.25, "cold -0.25")
	dumpNativeTrackStates("cold relative queue before Length resolution")
end

local function runColdReverseOffsetQueue(): ()
	appendEvidence("cold reverse relative queue begin; use first in a fresh Play session")
	setActionPlaybackRate(-1)
	playLifecycleClip("dance", false, true, CP_AG_R_UPPER)
	local activeController = getController()
	activeController:update(os.clock())
	offsetLifecyclePosition(-0.5, "cold reverse -0.5")
	offsetLifecyclePosition(0.1, "cold reverse +0.1")
	dumpNativeTrackStates("cold reverse relative queue before Length resolution")
end

local function runOffsetTerminal(
	speed: number,
	initialPosition: AnimationPosition,
	deltaSeconds: number,
	label: string
): ()
	setActionPlaybackRate(speed)
	playLifecycleClip("wave", false, true, initialPosition)
	task.delay(0.15, function()
		if controller ~= nil then
			offsetLifecyclePosition(deltaSeconds, label)
			dumpNativeTrackStates(label)
		end
	end)
end

local function runOffsetLoopWrap(): ()
	setActionPlaybackRate(-1)
	playLifecycleClip("dance", true, true, { kind = "normalized", value = 0.1 })
	task.delay(0.15, function()
		if controller ~= nil then
			offsetLifecyclePosition(-60, "loop negative wrap")
			offsetLifecyclePosition(60.5, "loop positive wrap")
			dumpNativeTrackStates("relative loop wraps")
		end
	end)
end

local function setActionPriority(value: number): ()
	actionPriority = value
	getController():setLayerLogicalPriority("action", actionPriority)
	appendLog("action logical priority = " .. tostring(actionPriority))
	updateSummary()
end

local function makeRobloxLayerBackend(priority: Enum.AnimationPriority?): LayerBackend?
	return if priority ~= nil
		then {
			robloxPriority = priority,
		}
		else nil
end

local function setActionRobloxPriority(priority: Enum.AnimationPriority?): ()
	actionRobloxPriority = priority
	getController():setLayerBackend("action", makeRobloxLayerBackend(priority))
	appendLog("action roblox priority = " .. (if priority ~= nil then tostring(priority) else "auto"))
	updateSummary()
end

local function cycleActionPriority(): ()
	if actionPriority == 0 then
		setActionPriority(10)
	elseif actionPriority == 10 then
		setActionPriority(50)
	elseif actionPriority == 50 then
		setActionPriority(100)
	elseif actionPriority == 100 then
		setActionPriority(200)
	else
		setActionPriority(0)
	end
end

local function replayControllerGraphs(): ()
	local activeController = getController()
	local baseOptions: AnimGraph.LayerPlayOptions<State, LayerBackend> = {
		state = "locomotion" :: State,
		looped = true,
		fadeTime = 0.15,
	}
	local actionOptions: AnimGraph.LayerPlayOptions<State, LayerBackend> = {
		state = "empty" :: State,
		looped = false,
		fadeTime = 0.05,
	}

	activeController:play("base", makeLocomotionBlend(), baseOptions)
	activeController:play("action", makeActionStateMachine(), actionOptions)
	activeController:setFloat("speed", speedValue)
	activeController:setLayerWeight("base", baseWeight)
	activeController:setLayerWeight("action", actionWeight)
	activeController:setLayerSpeed("base", basePlaybackRate)
	activeController:setLayerSpeed("action", actionPlaybackRate)
	activeController:setLayerLogicalPriority("action", actionPriority)
	activeController:setLayerBackend("action", makeRobloxLayerBackend(actionRobloxPriority))
	appendLog("replayed authored controller graphs")
	updateSummary()
end

local function resetHarnessState(): ()
	sequenceToken += 1
	activeSequenceName = "none"
	speedValue = 0
	baseWeight = 1
	actionWeight = 1
	basePlaybackRate = 1
	actionPlaybackRate = 1
	actionPriority = 100
	actionRobloxPriority = nil
	activeActionClip = "wave"
	baseTimePosition = 0
	actionTimePosition = 0
	baseTimeAnchor = os.clock()
	actionTimeAnchor = baseTimeAnchor
	baseTimeHeld = false
	actionTimeHeld = false
	replayControllerGraphs()
	appendLog("reset harness state")
end

local function runSequence(name: string, steps: { SequenceStep }): ()
	sequenceToken += 1
	local token = sequenceToken
	activeSequenceName = name
	appendLog("sequence start -> " .. name)
	updateSummary()

	for _, step in steps do
		task.delay(step.at, function()
			if token ~= sequenceToken then
				return
			end

			appendLog("sequence step -> " .. step.label)
			step.run()
		end)
	end
end

local function cancelSequence(): ()
	if activeSequenceName == "none" then
		appendLog("no active sequence")
		return
	end

	sequenceToken += 1
	appendLog("sequence cancelled -> " .. activeSequenceName)
	activeSequenceName = "none"
	updateSummary()
end

local function finishSequence(name: string, token: number): ()
	if token ~= sequenceToken then
		return
	end

	activeSequenceName = "none"
	appendLog("sequence complete -> " .. name)
	updateSummary()
end

local function runCombatSequence(): ()
	local name = "combat opener"
	local token = sequenceToken + 1
	runSequence(name, {
		{
			at = 0,
			label = "start sprint locomotion",
			run = function()
				setSpeed(8)
				setActionPriority(200)
			end,
		},
		{
			at = 0.45,
			label = "fire action trigger",
			run = function()
				triggerAction("wave")
			end,
		},
		{
			at = 1.05,
			label = "chain into second action",
			run = function()
				triggerAction("cheer")
			end,
		},
		{
			at = 1.65,
			label = "drop to jog while action continues",
			run = function()
				setSpeed(4)
			end,
		},
		{
			at = 2.35,
			label = "clear action layer",
			run = stopAction,
		},
		{
			at = 2.8,
			label = "return idle",
			run = function()
				setSpeed(0)
				finishSequence(name, token)
			end,
		},
	})
end

local function runLocomotionInterruptSequence(): ()
	local name = "locomotion interrupt"
	local token = sequenceToken + 1
	runSequence(name, {
		{
			at = 0,
			label = "idle",
			run = function()
				setSpeed(0)
				setActionWeight(1)
			end,
		},
		{
			at = 0.35,
			label = "accelerate",
			run = function()
				setSpeed(4)
			end,
		},
		{
			at = 0.75,
			label = "full movement",
			run = function()
				setSpeed(8)
			end,
		},
		{
			at = 1.05,
			label = "interrupt with emote/action",
			run = function()
				triggerAction("dance")
			end,
		},
		{
			at = 1.6,
			label = "lower action weight",
			run = function()
				setActionWeight(0.45)
			end,
		},
		{
			at = 2.15,
			label = "restore action and stop",
			run = function()
				setActionWeight(1)
				stopAction()
			end,
		},
		{
			at = 2.6,
			label = "settle",
			run = function()
				setSpeed(0)
				finishSequence(name, token)
			end,
		},
	})
end

local function runEmoteChainSequence(): ()
	local name = "emote chain"
	local token = sequenceToken + 1
	runSequence(name, {
		{
			at = 0,
			label = "stand still",
			run = function()
				setSpeed(0)
				setActionPriority(100)
			end,
		},
		{
			at = 0.2,
			label = "wave",
			run = function()
				triggerAction("wave")
			end,
		},
		{
			at = 1.05,
			label = "cheer",
			run = function()
				triggerAction("cheer")
			end,
		},
		{
			at = 1.9,
			label = "dance",
			run = function()
				triggerAction("dance")
			end,
		},
		{
			at = 3.1,
			label = "clear",
			run = function()
				stopAction()
				finishSequence(name, token)
			end,
		},
	})
end

local function runBlendStressSequence(): ()
	local name = "blend stress"
	local token = sequenceToken + 1
	runSequence(name, {
		{
			at = 0,
			label = "base full",
			run = function()
				setBaseWeight(1)
				setActionWeight(1)
				setSpeed(0)
			end,
		},
		{
			at = 0.25,
			label = "speed midpoint",
			run = function()
				setSpeed(4)
			end,
		},
		{
			at = 0.5,
			label = "speed max",
			run = function()
				setSpeed(8)
			end,
		},
		{
			at = 0.75,
			label = "fade base down",
			run = function()
				setBaseWeight(0.35)
			end,
		},
		{
			at = 1.05,
			label = "trigger action",
			run = function()
				triggerAction("cheer")
			end,
		},
		{
			at = 1.45,
			label = "swap priority bucket",
			run = function()
				setActionPriority(50)
			end,
		},
		{
			at = 1.9,
			label = "restore weights",
			run = function()
				setBaseWeight(1)
				setActionWeight(1)
			end,
		},
		{
			at = 2.35,
			label = "clear and idle",
			run = function()
				stopAction()
				setSpeed(0)
				setActionPriority(100)
				finishSequence(name, token)
			end,
		},
	})
end

local function getTrackRobloxPriority(track: any): any
	local details = track.details
	return if typeof(details) == "table" then details.robloxPriority else nil
end

local function getTrackDetail(track: any, key: string): any
	local details = track.details
	return if typeof(details) == "table" then details[key] else nil
end

local function dumpDebugSnapshot(): ()
	local snapshot = getController():getDebugSnapshot()
	appendLog("debug dump:")
	for _, layer in snapshot.layers do
		local motionName = if layer.motion ~= nil then layer.motion.name else "none"
		appendLog(
			"  layer "
				.. tostring(layer.id)
				.. " state="
				.. tostring(layer.state)
				.. " motion="
				.. motionName
				.. " weight="
				.. formatWeight(layer.weight)
		)
	end
	for _, track in snapshot.backend.tracks do
		appendLog(
			"  track "
				.. track.trackKey
				.. " clip="
				.. tostring(track.clip)
				.. " generation="
				.. tostring(getTrackDetail(track, "generation"))
				.. " lifecycle="
				.. tostring(getTrackDetail(track, "lifecycle"))
				.. " physical="
				.. tostring(getTrackDetail(track, "physicalPresent"))
				.. " playing="
				.. tostring(track.isPlaying)
				.. " speed="
				.. formatSpeed(track.speed)
				.. " weight="
				.. formatWeight(track.weight)
				.. " priority="
				.. tostring(getTrackRobloxPriority(track))
		)
	end
end

local function dumpNativeAndDebug(): ()
	local animator = nativeAnimator
	local playingCount = if animator == nil then 0 else #animator:GetPlayingAnimationTracks()
	dumpNativeTrackStates("manual dump playing=" .. tostring(playingCount))
	dumpDebugSnapshot()
end

local function formatDetailValue(value: any): string
	if typeof(value) == "number" then
		return string.format("%.2f", value)
	elseif typeof(value) == "table" then
		local name = value.name
		local progress = value.progress
		if typeof(name) == "string" and typeof(progress) == "number" then
			return string.format("%s %.0f%%", name, progress * 100)
		end

		return "<table>"
	end

	return tostring(value)
end

local function appendMotionDebug(lines: { string }, motion: any, indent: string): ()
	local kind = tostring(motion.kind)
	local name = tostring(motion.name)
	lines[#lines + 1] = indent .. kind .. " " .. name

	local details = motion.details
	if typeof(details) == "table" then
		local orderedKeys = {
			"parameter",
			"value",
			"activeState",
			"transition",
			"state",
			"role",
			"threshold",
			"weight",
			"x",
			"y",
		}

		for _, key in orderedKeys do
			local value = details[key]
			if value ~= nil then
				lines[#lines + 1] = indent .. "  " .. key .. "=" .. formatDetailValue(value)
			end
		end
	end

	local children = motion.children
	if typeof(children) == "table" then
		for _, child in children do
			appendMotionDebug(lines, child, indent .. "  ")
		end
	end
end

local function buildDebugText(): string
	local activeController = controller
	if activeController == nil then
		return "Controller not ready"
	end

	local snapshot = activeController:getDebugSnapshot()
	local lines: { string } = {
		"Layers",
	}

	for _, layer in snapshot.layers do
		local motionName = if layer.motion ~= nil then layer.motion.name else "none"
		lines[#lines + 1] = string.format(
			"%s  state=%s  motion=%s  weight=%.2f  rate=%.2f  logical=%d",
			tostring(layer.id),
			tostring(layer.state),
			motionName,
			layer.weight,
			layer.speed,
			layer.logicalPriority
		)
		if layer.motion ~= nil then
			appendMotionDebug(lines, layer.motion, "  ")
		end
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "Backend Tracks"
	for _, track in snapshot.backend.tracks do
		lines[#lines + 1] = string.format(
			"%s  clip=%s  gen=%s  %s  physical=%s  weight=%.2f  rate=%.2f  logical=%d  roblox=%s",
			track.trackKey,
			tostring(track.clip),
			tostring(getTrackDetail(track, "generation")),
			tostring(getTrackDetail(track, "lifecycle")),
			tostring(getTrackDetail(track, "physicalPresent")),
			track.weight,
			track.speed,
			track.logicalPriority,
			tostring(getTrackRobloxPriority(track))
		)
	end

	return table.concat(lines, "\n")
end

local function updateControlsCanvas(): ()
	local scroller = controlsScroller
	local layout = controlsContentLayout
	if scroller == nil or layout == nil then
		return
	end

	scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)
end

local function updateControlGridSize(grid: ControlGrid): ()
	local width = math.max(grid.frame.AbsoluteSize.X, 1)
	local columns = if width >= 520 then 4 elseif width >= 390 then 3 elseif width >= 260 then 2 else 1
	local padding = 8
	local cellWidth = math.floor((width - padding * (columns - 1)) / columns)

	grid.layout.CellPadding = UDim2.fromOffset(padding, padding)
	grid.layout.CellSize = UDim2.fromOffset(cellWidth, 32)
	grid.frame.Size = UDim2.new(1, 0, 0, grid.layout.AbsoluteContentSize.Y)
	updateControlsCanvas()
end

local function updateAllControlGridSizes(): ()
	for _, grid in controlGridLayouts do
		updateControlGridSize(grid)
	end
	updateControlsCanvas()
end

local function relayoutPanel(): ()
	local panel = panelFrame
	if panel == nil then
		return
	end

	local panelHeight = math.max(panel.AbsoluteSize.Y, 520)
	local margin = 14
	local controlsTop = 72
	local consoleHeaderHeight = 28
	local consoleHeight = if consoleExpanded then math.max(120, math.floor(panelHeight * 0.24)) else 0
	local consoleHeaderTop = panelHeight - margin - consoleHeaderHeight - consoleHeight
	local debugHeight = if consoleExpanded
		then math.max(110, math.floor(panelHeight * 0.2))
		else math.max(170, math.floor(panelHeight * 0.32))
	local debugTop = consoleHeaderTop - 8 - debugHeight
	local controlsHeight = math.max(180, debugTop - 8 - controlsTop)

	local controls = controlsScroller
	if controls ~= nil then
		controls.Position = UDim2.fromOffset(margin, controlsTop)
		controls.Size = UDim2.new(1, -margin * 2, 0, controlsHeight)
	end

	local debug = debugLabel
	if debug ~= nil then
		debug.Position = UDim2.fromOffset(margin, debugTop)
		debug.Size = UDim2.new(1, -margin * 2, 0, debugHeight)
	end

	local toggle = consoleToggleButton
	if toggle ~= nil then
		toggle.Position = UDim2.fromOffset(margin, consoleHeaderTop)
		toggle.Size = UDim2.new(1, -margin * 2, 0, consoleHeaderHeight)
		toggle.Text = if consoleExpanded then "Hide Console" else "Show Console"
	end

	local console = consoleScroller
	if console ~= nil then
		console.Visible = consoleExpanded
		console.Position = UDim2.fromOffset(margin, consoleHeaderTop + consoleHeaderHeight + 6)
		console.Size = UDim2.new(1, -margin * 2, 0, math.max(consoleHeight - 6, 0))
	end

	updateAllControlGridSizes()
end

local function setConsoleExpanded(expanded: boolean): ()
	consoleExpanded = expanded
	relayoutPanel()
end

local function makeButton(parent: Instance, text: string, layoutOrder: number, callback: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = text:gsub("%W+", "")
	button.LayoutOrder = layoutOrder
	button.BackgroundColor3 = Color3.fromRGB(38, 42, 50)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamMedium
	button.Text = text
	button.TextColor3 = Color3.fromRGB(235, 240, 245)
	button.TextScaled = true
	button.TextWrapped = true
	button.Parent = parent
	button.Activated:Connect(function(_input: InputObject, _clickCount: number)
		callback()
	end)

	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MinTextSize = 10
	textLimit.MaxTextSize = 13
	textLimit.Parent = button

	return button
end

local function makeSection(parent: Instance, titleText: string, layoutOrder: number, buttons: { TestButton }): Frame
	local section = Instance.new("Frame")
	section.Name = titleText:gsub("%W+", "")
	section.LayoutOrder = layoutOrder
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.Size = UDim2.new(1, -4, 0, 0)
	section.BackgroundTransparency = 1
	section.BorderSizePixel = 0
	section.Parent = parent

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.Padding = UDim.new(0, 6)
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Parent = section

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundColor3 = Color3.fromRGB(26, 31, 38)
	header.BorderSizePixel = 0
	header.Font = Enum.Font.GothamBold
	header.Text = titleText
	header.TextColor3 = Color3.fromRGB(235, 240, 245)
	header.TextSize = 13
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = section

	local headerPadding = Instance.new("UIPadding")
	headerPadding.PaddingLeft = UDim.new(0, 8)
	headerPadding.Parent = header

	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "Grid"
	gridFrame.LayoutOrder = 2
	gridFrame.Size = UDim2.new(1, 0, 0, 32)
	gridFrame.BackgroundTransparency = 1
	gridFrame.BorderSizePixel = 0
	gridFrame.Parent = section

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(120, 32)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridFrame

	local grid: ControlGrid = {
		frame = gridFrame,
		layout = gridLayout,
	}
	controlGridLayouts[#controlGridLayouts + 1] = grid

	for index, button in buttons do
		makeButton(gridFrame, button.text, index, button.callback)
	end

	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		gridFrame.Size = UDim2.new(1, 0, 0, gridLayout.AbsoluteContentSize.Y)
		updateControlsCanvas()
	end)
	gridFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		updateControlGridSize(grid)
	end)
	sectionLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateControlsCanvas)

	return section
end

local function buildUi(): ()
	controlGridLayouts = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.fromOffset(12, 12)
	panel.Size = UDim2.new(0.48, -18, 1, -24)
	panel.BackgroundColor3 = Color3.fromRGB(18, 21, 26)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	panelFrame = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -28, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "AnimGraph Dev Harness"
	title.TextColor3 = Color3.fromRGB(245, 248, 252)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MinTextSize = 12
	titleLimit.MaxTextSize = 16
	titleLimit.Parent = title

	local summary = Instance.new("TextLabel")
	summary.Name = "Summary"
	summary.Position = UDim2.fromOffset(14, 36)
	summary.Size = UDim2.new(1, -28, 0, 24)
	summary.BackgroundTransparency = 1
	summary.Font = Enum.Font.Gotham
	summary.Text = "Creating dummy and controller..."
	summary.TextColor3 = Color3.fromRGB(180, 190, 205)
	summary.TextScaled = true
	summary.TextWrapped = true
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Parent = panel
	summaryLabel = summary

	local summaryLimit = Instance.new("UITextSizeConstraint")
	summaryLimit.MinTextSize = 10
	summaryLimit.MaxTextSize = 13
	summaryLimit.Parent = summary

	local controls = Instance.new("ScrollingFrame")
	controls.Name = "Controls"
	controls.BackgroundTransparency = 1
	controls.BorderSizePixel = 0
	controls.CanvasSize = UDim2.fromOffset(0, 0)
	controls.ScrollBarThickness = 6
	controls.ScrollingDirection = Enum.ScrollingDirection.Y
	controls.Parent = panel
	controlsScroller = controls

	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.Padding = UDim.new(0, 12)
	controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlsLayout.Parent = controls
	controlsContentLayout = controlsLayout

	makeSection(controls, "Locomotion Blend", 1, {
		{
			text = "Speed 0",
			callback = function()
				setSpeed(0)
			end,
		},
		{
			text = "Speed 4",
			callback = function()
				setSpeed(4)
			end,
		},
		{
			text = "Speed 8",
			callback = function()
				setSpeed(8)
			end,
		},
		{
			text = "Base Rate -",
			callback = function()
				adjustBasePlaybackRate(-0.1)
			end,
		},
		{
			text = "Base Rate +",
			callback = function()
				adjustBasePlaybackRate(0.1)
			end,
		},
		{
			text = "Base Rate 1x",
			callback = function()
				setBasePlaybackRate(1)
			end,
		},
	})

	makeSection(controls, "Action State Machine", 2, {
		{
			text = "Action Wave",
			callback = function()
				triggerAction("wave")
			end,
		},
		{
			text = "Action Cheer",
			callback = function()
				triggerAction("cheer")
			end,
		},
		{
			text = "Action Dance",
			callback = function()
				triggerAction("dance")
			end,
		},
		{
			text = "Stop Action",
			callback = stopAction,
		},
		{
			text = "Restart Action",
			callback = restartAction,
		},
		{
			text = "Action Speed -0.1",
			callback = function()
				adjustActionPlaybackRate(-0.1)
			end,
		},
		{
			text = "Action Speed +0.1",
			callback = function()
				adjustActionPlaybackRate(0.1)
			end,
		},
		{
			text = "Action Speed -1x",
			callback = function()
				setActionPlaybackRate(-1)
			end,
		},
		{
			text = "Action Speed 0x",
			callback = function()
				setActionPlaybackRate(0)
			end,
		},
		{
			text = "Action Speed +1x",
			callback = function()
				setActionPlaybackRate(1)
			end,
		},
	})

	makeSection(controls, "Layer Weights", 3, {
		{
			text = "Base -",
			callback = function()
				adjustBaseWeight(-0.1)
			end,
		},
		{
			text = "Base +",
			callback = function()
				adjustBaseWeight(0.1)
			end,
		},
		{
			text = "Base 0",
			callback = function()
				setBaseWeight(0)
			end,
		},
		{
			text = "Base 1",
			callback = function()
				setBaseWeight(1)
			end,
		},
		{
			text = "Action -",
			callback = function()
				adjustActionWeight(-0.1)
			end,
		},
		{
			text = "Action +",
			callback = function()
				adjustActionWeight(0.1)
			end,
		},
		{
			text = "Action 0",
			callback = function()
				setActionWeight(0)
			end,
		},
		{
			text = "Action 1",
			callback = function()
				setActionWeight(1)
			end,
		},
	})

	makeSection(controls, "Priority Mapping", 4, {
		{
			text = "Logical 0",
			callback = function()
				setActionPriority(0)
			end,
		},
		{
			text = "Logical 10",
			callback = function()
				setActionPriority(10)
			end,
		},
		{
			text = "Logical 50",
			callback = function()
				setActionPriority(50)
			end,
		},
		{
			text = "Logical 100",
			callback = function()
				setActionPriority(100)
			end,
		},
		{
			text = "Logical 200",
			callback = function()
				setActionPriority(200)
			end,
		},
		{
			text = "Cycle Logical",
			callback = cycleActionPriority,
		},
		{
			text = "Roblox Auto",
			callback = function()
				setActionRobloxPriority(nil)
			end,
		},
		{
			text = "Roblox Action2",
			callback = function()
				setActionRobloxPriority(Enum.AnimationPriority.Action2)
			end,
		},
		{
			text = "Roblox Action4",
			callback = function()
				setActionRobloxPriority(Enum.AnimationPriority.Action4)
			end,
		},
	})

	makeSection(controls, "Gameplay Sequences", 5, {
		{
			text = "Combat Opener",
			callback = runCombatSequence,
		},
		{
			text = "Move Interrupt",
			callback = runLocomotionInterruptSequence,
		},
		{
			text = "Emote Chain",
			callback = runEmoteChainSequence,
		},
		{
			text = "Blend Stress",
			callback = runBlendStressSequence,
		},
		{
			text = "Cancel Sequence",
			callback = cancelSequence,
		},
	})

	makeSection(controls, "Temporal Lifecycle", 6, {
		{
			text = "Hold Base Reader",
			callback = function()
				setTimeHeld("base", true)
			end,
		},
		{
			text = "Advance Base Reader",
			callback = function()
				setTimeHeld("base", false)
			end,
		},
		{
			text = "Hold Action Reader",
			callback = function()
				setTimeHeld("action", true)
			end,
		},
		{
			text = "Advance Action Reader",
			callback = function()
				setTimeHeld("action", false)
			end,
		},
		{
			text = "Play Natural End",
			callback = function()
				playLifecycleClip("wave", false, nil, nil)
			end,
		},
		{
			text = "Play Loop",
			callback = function()
				playLifecycleClip("dance", true, nil, nil)
			end,
		},
		{
			text = "Initial Upper",
			callback = function()
				playLifecycleAt(CP_AG_R_UPPER, "upper")
			end,
		},
		{
			text = "Initial Lower",
			callback = function()
				playLifecycleAt(CP_AG_R_LOWER, "lower")
			end,
		},
		{
			text = "Live Upper",
			callback = function()
				setLifecyclePosition(CP_AG_R_UPPER, "upper")
			end,
		},
		{
			text = "Live Lower",
			callback = function()
				setLifecyclePosition(CP_AG_R_LOWER, "lower")
			end,
		},
		{
			text = "Cold 0 -> -1",
			callback = runColdZeroToReverse,
		},
		{
			text = "Offset +0.50s",
			callback = function()
				offsetLifecyclePosition(0.5, "+0.5")
			end,
		},
		{
			text = "Offset -0.50s",
			callback = function()
				offsetLifecyclePosition(-0.5, "-0.5")
			end,
		},
		{
			text = "Offset Loop Wrap",
			callback = runOffsetLoopWrap,
		},
		{
			text = "Offset Fwd End",
			callback = function()
				runOffsetTerminal(1, { kind = "normalized", value = 0.9 }, 60, "forward relative terminal")
			end,
		},
		{
			text = "Offset Rev End",
			callback = function()
				runOffsetTerminal(-1, { kind = "normalized", value = 0.1 }, -60, "reverse relative terminal")
			end,
		},
		{
			text = "Offset Zero Hold",
			callback = function()
				runOffsetTerminal(0, { kind = "normalized", value = 0.9 }, 60, "zero-speed relative hold")
			end,
		},
		{
			text = "Cold Offset Queue",
			callback = runColdOffsetQueue,
		},
		{
			text = "Cold Rev + Offset",
			callback = runColdReverseOffsetQueue,
		},
		{
			text = "Position 75%",
			callback = function()
				setLifecyclePosition({ kind = "normalized", value = 0.75 }, "75%")
			end,
		},
		{
			text = "Position 25%",
			callback = function()
				setLifecyclePosition({ kind = "normalized", value = 0.25 }, "25%")
			end,
		},
		{
			text = "Exact Terminal",
			callback = playThenPositionTerminal,
		},
		{
			text = "Replace Same Key",
			callback = replaceLifecycleClip,
		},
		{
			text = "Reappear In Fade",
			callback = reappearDuringFade,
		},
		{
			text = "Force Restart",
			callback = function()
				playLifecycleClip(activeActionClip, false, true, nil)
			end,
		},
		{
			text = "Stop Fade 1s",
			callback = function()
				getController():stopLayer("action", 1)
				appendLog("action stop with 1.0s fade")
			end,
		},
		{
			text = "Clear Physics",
			callback = clearPhysicalLifecycle,
		},
	})

	makeSection(controls, "Debug Tools", 7, {
		{
			text = "Dump Native + Debug",
			callback = dumpNativeAndDebug,
		},
		{
			text = "Replay Graphs",
			callback = replayControllerGraphs,
		},
		{
			text = "Reset Harness",
			callback = resetHarnessState,
		},
		{
			text = "Clear Console",
			callback = clearLog,
		},
	})

	controlsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateControlsCanvas)
	controls:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateAllControlGridSizes)

	local debug = Instance.new("TextLabel")
	debug.Name = "Debug"
	debug.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
	debug.BorderSizePixel = 0
	debug.Font = Enum.Font.Code
	debug.Text = ""
	debug.TextColor3 = Color3.fromRGB(210, 220, 230)
	debug.TextScaled = true
	debug.TextXAlignment = Enum.TextXAlignment.Left
	debug.TextYAlignment = Enum.TextYAlignment.Top
	debug.TextWrapped = true
	debug.Parent = panel
	debugLabel = debug

	local debugLimit = Instance.new("UITextSizeConstraint")
	debugLimit.MinTextSize = 8
	debugLimit.MaxTextSize = 12
	debugLimit.Parent = debug

	local consoleToggle = Instance.new("TextButton")
	consoleToggle.Name = "ConsoleToggle"
	consoleToggle.BackgroundColor3 = Color3.fromRGB(26, 31, 38)
	consoleToggle.BorderSizePixel = 0
	consoleToggle.Font = Enum.Font.GothamBold
	consoleToggle.Text = "Show Console"
	consoleToggle.TextColor3 = Color3.fromRGB(235, 240, 245)
	consoleToggle.TextSize = 13
	consoleToggle.Parent = panel
	consoleToggle.Activated:Connect(function()
		setConsoleExpanded(not consoleExpanded)
	end)
	consoleToggleButton = consoleToggle

	local consoleFrame = Instance.new("ScrollingFrame")
	consoleFrame.Name = "Console"
	consoleFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
	consoleFrame.BorderSizePixel = 0
	consoleFrame.CanvasSize = UDim2.fromOffset(0, 0)
	consoleFrame.ScrollBarThickness = 6
	consoleFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	consoleFrame.Visible = false
	consoleFrame.Parent = panel
	consoleScroller = consoleFrame

	local consolePadding = Instance.new("UIPadding")
	consolePadding.PaddingBottom = UDim.new(0, 4)
	consolePadding.PaddingLeft = UDim.new(0, 6)
	consolePadding.PaddingRight = UDim.new(0, 6)
	consolePadding.PaddingTop = UDim.new(0, 4)
	consolePadding.Parent = consoleFrame

	local consoleLayout = Instance.new("UIListLayout")
	consoleLayout.SortOrder = Enum.SortOrder.LayoutOrder
	consoleLayout.Parent = consoleFrame
	consoleContentLayout = consoleLayout

	local console = Instance.new("TextLabel")
	console.Name = "Text"
	console.AutomaticSize = Enum.AutomaticSize.Y
	console.Size = UDim2.new(1, -12, 0, 0)
	console.BackgroundTransparency = 1
	console.Font = Enum.Font.Code
	console.Text = ""
	console.TextColor3 = Color3.fromRGB(210, 220, 230)
	console.TextSize = 12
	console.TextXAlignment = Enum.TextXAlignment.Left
	console.TextYAlignment = Enum.TextYAlignment.Top
	console.TextWrapped = true
	console.Parent = consoleFrame
	consoleLabel = console

	consoleLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		consoleFrame.CanvasSize = UDim2.fromOffset(0, consoleLayout.AbsoluteContentSize.Y + 8)
	end)

	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutPanel)
	relayoutPanel()
end

local function setupController(animator: Animator): ()
	connectNativeEvidence(animator)
	local backend: AnimGraph.RobloxAnimatorBackend<Layer, State, Clip> = AnimGraph.robloxAnimatorBackend.new({
		animator = animator,
		positionMode = BACKEND_POSITION_MODE,
		resolveAssetId = function(clip: Clip): number
			local assetId = ANIMATION_IDS[clip]
			assert(assetId ~= nil, "missing dev animation id for clip " .. tostring(clip))

			return assetId
		end,
		defaultFadeOut = 0.15,
	}) :: any

	local layerDefinitions: { AnimGraph.LayerDefinition<Layer, LayerBackend> } = {
		{
			id = "base",
			weight = baseWeight,
			logicalPriority = 0,
			layerBackend = {
				robloxPriority = Enum.AnimationPriority.Movement,
			},
			defaultFadeIn = 0.15,
			defaultFadeOut = 0.15,
		},
		{
			id = "action",
			weight = actionWeight,
			logicalPriority = actionPriority,
			layerBackend = makeRobloxLayerBackend(actionRobloxPriority),
			defaultFadeIn = 0.05,
			defaultFadeOut = 0.12,
			timeReader = actionTimeReader,
		},
	}

	local config: AnimGraph.AnimationControllerConfig<Layer, State, Param, Clip, LayerBackend> = {
		backend = backend,
		timeReader = baseTimeReader,
		layers = layerDefinitions,
	}

	local newController = AnimGraph.new :: (
		AnimGraph.AnimationControllerConfig<Layer, State, Param, Clip, LayerBackend>
	) -> AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend>
	controller = newController(config)

	local activeController = getController()
	activeController:on("transitionStarted", function(event)
		if event.name == "transitionStarted" and event.layer == "action" then
			appendLog("event transitionStarted " .. tostring(event.transition))
		end
	end)
	activeController:on("transitionEnded", function(event)
		if event.name == "transitionEnded" and event.layer == "action" then
			appendLog("event transitionEnded " .. tostring(event.transition))
		end
	end)
	activeController:on("stateEntered", function(event)
		if event.name == "stateEntered" and event.layer == "action" then
			appendLog("event stateEntered " .. tostring(event.state))
		end
	end)
	activeController:on("stateExited", function(event)
		if event.name == "stateExited" and event.layer == "action" then
			appendLog("event stateExited " .. tostring(event.state))
		end
	end)
	activeController:on("trackCompleted", function(event)
		if event.name == "trackCompleted" then
			local generation = "missing"
			local lifecycle = "missing"
			for _, track in activeController:getDebugSnapshot().backend.tracks do
				if track.trackKey == event.trackKey then
					generation = tostring(getTrackDetail(track, "generation"))
					lifecycle = tostring(getTrackDetail(track, "lifecycle"))
					break
				end
			end
			appendEvidence(
				"trackCompleted key=" .. event.trackKey .. " generation=" .. generation .. " lifecycle=" .. lifecycle
			)
		end
	end)

	replayControllerGraphs()

	local updateConnection = RunService.PreAnimation:Connect(function()
		activeController:update(os.clock())
	end)
	releaseUpdate = function()
		updateConnection:Disconnect()
	end
	updateSummary()
end

local function cleanup(): ()
	local activeDebugConnection = debugConnection
	if activeDebugConnection ~= nil then
		activeDebugConnection:Disconnect()
		debugConnection = nil
	end

	local activeCameraConnection = cameraConnection
	if activeCameraConnection ~= nil then
		activeCameraConnection:Disconnect()
		cameraConnection = nil
	end
	cameraTarget = nil

	local activeRelease = releaseUpdate
	if activeRelease ~= nil then
		activeRelease()
		releaseUpdate = nil
	end

	local activeController = controller
	if activeController ~= nil then
		activeController:destroy()
		controller = nil
	end

	for _, connection in nativeConnections do
		connection:Disconnect()
	end
	nativeConnections = {}
	nativeAnimator = nil
	nativeTracks = {}
	nativeTrackIds = {}

	if devRoot.Parent ~= nil then
		devRoot:Destroy()
	end
end

buildUi()

local ok, err = pcall(function()
	local dummy, animator = createDummy()
	setupCamera(dummy)
	setupController(animator)
	appendLog("Spawned R6 dummy and sampled time readers from PreAnimation.")
end)

if not ok then
	setSummary("Setup failed. See Output for details.")
	appendLog("SETUP FAILED: " .. tostring(err))
	warn("[AnimGraphDev] " .. tostring(err))
end

debugConnection = RunService.Heartbeat:Connect(function()
	local label = debugLabel
	if label ~= nil then
		label.Text = buildDebugText()
	end
end)

script.Destroying:Connect(cleanup)

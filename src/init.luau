--!strict
--!optimize 2

local RobloxPlaybackDefTypes = require(script.animGraph.types.def.animationPlayback.shared.robloxPlayback)
local TrackMarkerSourceTypes = require(script.animGraph.types.ports.backends.animationPlayback.shared.trackMarkerSource)
local AnimationControllerTypes =
	require(script.animGraph.types.controller.animationController.shared.animationController)
local DefTypes = require(script.animGraph.types.def.animation.shared.animation)
local EventBusTypes = require(script.animGraph.types.controller.animationController.shared.animationController.eventBus)
local ParameterStoreTypes =
	require(script.animGraph.types.controller.animationController.shared.animationController.parameterStore)
local LayerRuntimeTypes = require(script.animGraph.types.runtime.layerRuntime.shared.layerRuntime)
local StateMachineRuntimeTypes = require(script.animGraph.types.runtime.stateMachineRuntime.shared.stateMachineRuntime)
local TransitionRuntimeTypes = require(script.animGraph.types.runtime.transitionRuntime.shared.transitionRuntime)
local MotionNodeTypes = require(script.animGraph.types.motions.motionNode.shared.motionNode)
local ClipNodeTypes = require(script.animGraph.types.motions.clipNode.shared.clipNode)
local Blend1DNodeTypes = require(script.animGraph.types.motions.blend1DNode.shared.blend1DNode)
local Blend2DNodeTypes = require(script.animGraph.types.motions.blend2DNode.shared.blend2DNode)
local AnimationBackendTypes = require(script.animGraph.types.backends.animationBackend.shared.animationBackend)
local RobloxAnimatorBackendTypes =
	require(script.animGraph.types.backends.robloxAnimatorBackend.shared.robloxAnimatorBackend)
local StackModifierTypes = require(script.animGraph.types.components.stackModifier.shared.stackModifier)
local AnimationController = require(script.animGraph.controller.animationController.shared.animationController)
local Blend1DNode = require(script.animGraph.motions.blend1DNode.shared.blend1DNode)
local Blend2DNode = require(script.animGraph.motions.blend2DNode.shared.blend2DNode)
local ClipNode = require(script.animGraph.motions.clipNode.shared.clipNode)
local RobloxAnimatorBackend = require(script.animGraph.backends.robloxAnimatorBackend.shared.robloxAnimatorBackend)
local StateMachineRuntime = require(script.animGraph.runtime.stateMachineRuntime.shared.stateMachineRuntime)
local StackModifier = require(script.animGraph.components.stackModifier.shared.stackModifier)

export type Release = DefTypes.Release
export type AssetId = RobloxPlaybackDefTypes.AssetId
export type AnimationPosition = DefTypes.AnimationPosition
export type TimeSample = DefTypes.TimeSample
export type TimeReader = DefTypes.TimeReader
export type TrackCompletedEvent<LayerT, StateT> = DefTypes.TrackCompletedEvent<LayerT, StateT>
export type TrackMarkerSource<LayerT, StateT, ClipT> = TrackMarkerSourceTypes.TrackMarkerSource<LayerT, StateT, ClipT>
export type ParameterValue = ParameterStoreTypes.ParameterValue
export type AnimationEventName = EventBusTypes.AnimationEventName
export type AnimationEvent<LayerT, StateT> = EventBusTypes.AnimationEvent<LayerT, StateT>
export type AnimationEventCallback<LayerT, StateT> = EventBusTypes.AnimationEventCallback<LayerT, StateT>
export type SpeedModifierMode = StackModifierTypes.SpeedModifierMode
export type SpeedModifierOptions = StackModifierTypes.SpeedModifierOptions
export type AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	AnimationControllerTypes.AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT> =
	AnimationControllerTypes.AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT>
export type AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	AnimationControllerTypes.AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type LayerDefinition<LayerT, LayerBackendT> = LayerRuntimeTypes.LayerDefinition<LayerT, LayerBackendT>
export type LayerPlayOptions<StateT, LayerBackendT> = LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>
export type MotionRequestOverrides<LayerBackendT> = MotionNodeTypes.MotionRequestOverrides<LayerBackendT>
export type ClipRequest<LayerT, StateT, ClipT, LayerBackendT> = MotionNodeTypes.ClipRequest<
	LayerT,
	StateT,
	ClipT,
	LayerBackendT
>
export type MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = MotionNodeTypes.MotionNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type ClipNodeConfig<LayerBackendT> = ClipNodeTypes.ClipNodeConfig<LayerBackendT>
export type ClipNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = ClipNodeTypes.ClipNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Blend1DNodeTypes.Blend1DSample<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type Blend1DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Blend1DNodeTypes.Blend1DNodeConfig<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type Blend1DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Blend1DNodeTypes.Blend1DNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Blend2DNodeTypes.Blend2DSample<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type Blend2DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Blend2DNodeTypes.Blend2DNodeConfig<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type Blend2DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Blend2DNodeTypes.Blend2DNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type TransitionConditionOp = TransitionRuntimeTypes.TransitionConditionOp
export type TransitionCondition<ParamT> = TransitionRuntimeTypes.TransitionCondition<ParamT>
export type TransitionDefinition<StateT, ParamT> = TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT>
export type StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT> = StateMachineRuntimeTypes.StateDefinition<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = StateMachineRuntimeTypes.StateMachineConfig<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	StateMachineRuntimeTypes.StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type AnimationBackend<LayerT, StateT, ClipT, LayerBackendT> = AnimationBackendTypes.AnimationBackend<
	LayerT,
	StateT,
	ClipT,
	LayerBackendT
>
export type BackendPositionMode = AnimationBackendTypes.BackendPositionMode
export type BackendCapabilities = AnimationBackendTypes.BackendCapabilities
export type BackendDebugSnapshot = AnimationBackendTypes.BackendDebugSnapshot
export type LogicalPriorityBand = RobloxPlaybackDefTypes.LogicalPriorityBand
export type RobloxLayerBackend = RobloxPlaybackDefTypes.RobloxLayerBackend
export type RobloxAnimatorBackendConfig<ClipT> = RobloxAnimatorBackendTypes.RobloxAnimatorBackendConfig<ClipT>
export type RobloxAnimatorBackend<LayerT, StateT, ClipT> = RobloxAnimatorBackendTypes.RobloxAnimatorBackend<
	LayerT,
	StateT,
	ClipT
>
export type StackModifier = StackModifierTypes.StackModifier

return {
	animationController = AnimationController,
	blend1DNode = Blend1DNode,
	blend2DNode = Blend2DNode,
	clipNode = ClipNode,
	robloxAnimatorBackend = RobloxAnimatorBackend,
	stateMachineRuntime = StateMachineRuntime,
	stackModifier = StackModifier,

	new = AnimationController.new,
	blend1D = Blend1DNode.new,
	blend2D = Blend2DNode.new,
	clip = ClipNode.new,
	stateMachine = StateMachineRuntime.new,
}

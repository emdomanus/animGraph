--!strict
--!optimize 2
--!native

local Types = require(script.types)
local AnimationController = require(script.controller.animationController)
local Blend1DNode = require(script.motions.blend1DNode)
local Blend2DNode = require(script.motions.blend2DNode)
local ClipNode = require(script.motions.clipNode)
local RobloxAnimatorBackend = require(script.backends.robloxAnimatorBackend)
local StateMachineRuntime = require(script.runtime.stateMachineRuntime)
local StackModifier = require(script.components.stackModifier)

export type ParameterValue = Types.ParameterValue
export type AnimationPosition = Types.AnimationPosition
export type TimeSource = Types.TimeSource
export type LogicalTimeReader = Types.LogicalTimeReader
export type TrackCompletedEvent<LayerT, StateT> = Types.TrackCompletedEvent<LayerT, StateT>
export type AnimationEventName = Types.AnimationEventName
export type AnimationEvent<LayerT, StateT> = Types.AnimationEvent<LayerT, StateT>
export type AnimationEventCallback<LayerT, StateT> = Types.AnimationEventCallback<LayerT, StateT>
export type AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT> =
	Types.AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT>
export type AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type LayerDefinition<LayerT, LayerBackendT> = Types.LayerDefinition<LayerT, LayerBackendT>
export type LayerPlayOptions<StateT, LayerBackendT> = Types.LayerPlayOptions<StateT, LayerBackendT>
export type MotionRequestOverrides<LayerBackendT> = Types.MotionRequestOverrides<LayerBackendT>
export type ClipRequest<LayerT, StateT, ClipT, LayerBackendT> =
	Types.ClipRequest<LayerT, StateT, ClipT, LayerBackendT>
export type MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type ClipNodeConfig<LayerBackendT> = Types.ClipNodeConfig<LayerBackendT>
export type ClipNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.ClipNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend1DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.Blend1DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend1DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.Blend1DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend2DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.Blend2DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type Blend2DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.Blend2DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type TransitionConditionOp = Types.TransitionConditionOp
export type TransitionCondition<ParamT> = Types.TransitionCondition<ParamT>
export type TransitionDefinition<StateT, ParamT> = Types.TransitionDefinition<StateT, ParamT>
export type StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type AnimationBackend<LayerT, StateT, ClipT, LayerBackendT> =
	Types.AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>
export type BackendCapabilities = Types.BackendCapabilities
export type BackendDebugSnapshot = Types.BackendDebugSnapshot
export type AssetId = Types.AssetId
export type RobloxLayerBackend = Types.RobloxLayerBackend
export type LogicalPriorityBand = Types.LogicalPriorityBand
export type RobloxAnimatorBackendConfig<ClipT> = Types.RobloxAnimatorBackendConfig<ClipT>
export type RobloxAnimatorBackend<LayerT, StateT, ClipT> =
	Types.RobloxAnimatorBackend<LayerT, StateT, ClipT>
export type Release = Types.Release
export type SpeedModifierMode = Types.SpeedModifierMode
export type SpeedModifierOptions = Types.SpeedModifierOptions
export type StackModifier = Types.StackModifier

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

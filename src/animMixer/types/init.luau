--!strict
--!optimize 2
--!native

local ComponentTypes = require(script.components)

export type Release = ComponentTypes.Release
export type AssetId = ComponentTypes.AssetId
export type SpeedModifierMode = ComponentTypes.SpeedModifierMode
export type SpeedModifierOptions = ComponentTypes.SpeedModifierOptions
export type AnimMixerPlayOptions = ComponentTypes.AnimMixerPlayOptions
export type AnimMixerCategoryDefaults = ComponentTypes.AnimMixerCategoryDefaults
export type AnimMixerConfig<CategoryT, RefT> = ComponentTypes.AnimMixerConfig<CategoryT, RefT>
export type AnimMixer<CategoryT, RefT> = ComponentTypes.AnimMixer<CategoryT, RefT>
export type AnimMixerImpl<CategoryT, RefT> = ComponentTypes.AnimMixerImpl<CategoryT, RefT>
export type CategoryEntry<RefT> = ComponentTypes.CategoryEntry<RefT>
export type AnimPlayback<RefT> = ComponentTypes.AnimPlayback<RefT>
export type AnimPlaybackImpl<RefT> = ComponentTypes.AnimPlaybackImpl<RefT>
export type AnimPlaybackConfig<RefT> = ComponentTypes.AnimPlaybackConfig<RefT>
export type AnimPlaybackPlayOptions = ComponentTypes.AnimPlaybackPlayOptions
export type StackModifier = ComponentTypes.StackModifier
export type StackModifierImpl = ComponentTypes.StackModifierImpl
export type StackModifierConfig = ComponentTypes.StackModifierConfig
export type StackModifierEntry = ComponentTypes.StackModifierEntry

return {}

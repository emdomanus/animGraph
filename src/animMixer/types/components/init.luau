--!strict
--!optimize 2
--!native

local AnimMixerTypes = require(script.animMixer)
local AnimPlaybackTypes = require(script.animPlayback)
local StackModifierTypes = require(script.stackModifier)

export type Release = AnimMixerTypes.Release
export type AssetId = AnimMixerTypes.AssetId
export type SpeedModifierMode = StackModifierTypes.SpeedModifierMode
export type SpeedModifierOptions = StackModifierTypes.SpeedModifierOptions
export type AnimMixerPlayOptions = AnimMixerTypes.AnimMixerPlayOptions
export type AnimMixerCategoryDefaults = AnimMixerTypes.AnimMixerCategoryDefaults
export type AnimMixerConfig<CategoryT, RefT> = AnimMixerTypes.AnimMixerConfig<CategoryT, RefT>
export type AnimMixer<CategoryT, RefT> = AnimMixerTypes.AnimMixer<CategoryT, RefT>
export type AnimMixerImpl<CategoryT, RefT> = AnimMixerTypes.AnimMixerImpl<CategoryT, RefT>
export type CategoryEntry<RefT> = AnimMixerTypes.CategoryEntry<RefT>
export type AnimPlayback<RefT> = AnimPlaybackTypes.AnimPlayback<RefT>
export type AnimPlaybackImpl<RefT> = AnimPlaybackTypes.AnimPlaybackImpl<RefT>
export type AnimPlaybackConfig<RefT> = AnimPlaybackTypes.AnimPlaybackConfig<RefT>
export type AnimPlaybackPlayOptions = AnimPlaybackTypes.AnimPlaybackPlayOptions
export type StackModifier = StackModifierTypes.StackModifier
export type StackModifierImpl = StackModifierTypes.StackModifierImpl
export type StackModifierConfig = StackModifierTypes.StackModifierConfig
export type StackModifierEntry = StackModifierTypes.StackModifierEntry

return {}

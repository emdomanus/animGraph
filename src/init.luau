--!strict
--!optimize 2
--!native

local AnimMixer = require(script.animMixer)
local Types = require(script.animMixer.types)

export type Release = Types.Release
export type AssetId = Types.AssetId
export type SpeedModifierMode = Types.SpeedModifierMode
export type SpeedModifierOptions = Types.SpeedModifierOptions
export type AnimMixerPlayOptions = Types.AnimMixerPlayOptions
export type AnimMixerCategoryDefaults = Types.AnimMixerCategoryDefaults
export type AnimMixerConfig<CategoryT, RefT> = Types.AnimMixerConfig<CategoryT, RefT>
export type AnimMixer<CategoryT, RefT> = Types.AnimMixer<CategoryT, RefT>

return AnimMixer

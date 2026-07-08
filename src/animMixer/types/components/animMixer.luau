--!strict
--!optimize 2
--!native

local AnimPlaybackTypes = require(script.Parent.animPlayback)
local StackModifierTypes = require(script.Parent.stackModifier)

export type Release = () -> ()
export type AssetId = number
export type SpeedModifierOptions = StackModifierTypes.SpeedModifierOptions

export type AnimMixerPlayOptions = {
	fadeIn: number?,
	fadeOut: number?,
	speed: number?,
	looped: boolean?,
	preserveTimePosition: boolean?,
	forceRestart: boolean?,
	localPriority: number?,
}

export type AnimMixerCategoryDefaults = {
	fadeIn: number?,
	fadeOut: number?,
	speed: number?,
	looped: boolean?,
	forceRestart: boolean?,
	localPriority: number?,
	priority: Enum.AnimationPriority?,
}

export type AnimMixerConfig<CategoryT, RefT> = {
	animator: Animator,
	resolveAssetId: (ref: RefT) -> AssetId,

	defaultFadeIn: number?,
	defaultFadeOut: number?,
	defaultSpeed: number?,
	defaultLooped: boolean?,
	defaultPriority: Enum.AnimationPriority?,

	categoryPriorities: { [CategoryT]: Enum.AnimationPriority }?,
	categoryDefaults: { [CategoryT]: AnimMixerCategoryDefaults }?,
}

export type AnimMixer<CategoryT, RefT> = {
	play: (
		self: AnimMixer<CategoryT, RefT>,
		category: CategoryT,
		ref: RefT,
		options: AnimMixerPlayOptions?
	) -> (),
	push: (
		self: AnimMixer<CategoryT, RefT>,
		category: CategoryT,
		ref: RefT,
		options: AnimMixerPlayOptions?
	) -> Release,

	stop: (self: AnimMixer<CategoryT, RefT>, category: CategoryT, fadeOut: number?) -> (),
	stopIfRef: (
		self: AnimMixer<CategoryT, RefT>,
		category: CategoryT,
		ref: RefT,
		fadeOut: number?
	) -> boolean,

	isCategoryPlaying: (self: AnimMixer<CategoryT, RefT>, category: CategoryT) -> boolean,
	getCategoryTrack: (self: AnimMixer<CategoryT, RefT>, category: CategoryT) -> AnimationTrack?,
	getCategoryRef: (self: AnimMixer<CategoryT, RefT>, category: CategoryT) -> RefT?,
	getCategoryTimePosition: (self: AnimMixer<CategoryT, RefT>, category: CategoryT) -> number?,
	getCategorySpeed: (self: AnimMixer<CategoryT, RefT>, category: CategoryT) -> number?,

	setCategorySpeed: (self: AnimMixer<CategoryT, RefT>, category: CategoryT, speed: number) -> (),
	setCategoryTimePosition: (
		self: AnimMixer<CategoryT, RefT>,
		category: CategoryT,
		timePosition: number
	) -> (),
	adjustCategoryTimePosition: (
		self: AnimMixer<CategoryT, RefT>,
		category: CategoryT,
		deltaTime: number
	) -> (),
	adjustAllTimePositions: (self: AnimMixer<CategoryT, RefT>, deltaTime: number) -> (),

	pushGlobalSpeedModifier: (
		self: AnimMixer<CategoryT, RefT>,
		value: number,
		options: SpeedModifierOptions?
	) -> Release,
	pushCategorySpeedModifier: (
		self: AnimMixer<CategoryT, RefT>,
		category: CategoryT,
		value: number,
		options: SpeedModifierOptions?
	) -> Release,

	clear: (self: AnimMixer<CategoryT, RefT>) -> (),
	destroy: (self: AnimMixer<CategoryT, RefT>) -> (),
}

export type CategoryEntry<RefT> = {
	token: number,
	ref: RefT,
	localPriority: number,
	order: number,
	fadeIn: number,
	fadeOut: number,
	speed: number,
	looped: boolean,
	preserveTimePosition: boolean?,
	forceRestart: boolean,
}

export type AnimMixerImpl<CategoryT, RefT> = AnimMixer<CategoryT, RefT> & {
	_animator: Animator,
	_resolveAssetId: (ref: RefT) -> AssetId,

	_defaultFadeIn: number,
	_defaultFadeOut: number,
	_defaultSpeed: number,
	_defaultLooped: boolean,
	_defaultPriority: Enum.AnimationPriority,
	_categoryPriorities: { [CategoryT]: Enum.AnimationPriority },
	_categoryDefaults: { [CategoryT]: AnimMixerCategoryDefaults },

	_knownCategories: { CategoryT },
	_knownCategorySet: { [CategoryT]: true },
	_categoryRefs: { [CategoryT]: RefT },
	_categoryBaseEntries: { [CategoryT]: CategoryEntry<RefT> },
	_categoryStackEntries: { [CategoryT]: { CategoryEntry<RefT> } },
	_categorySpeedModifiers: { [CategoryT]: StackModifierTypes.StackModifierImpl },

	_playbacks: { [RefT]: AnimPlaybackTypes.AnimPlaybackImpl<RefT> },
	_nextCategoryEntryToken: number,
	_nextCategoryEntryOrder: number,
	_globalSpeedModifiers: StackModifierTypes.StackModifierImpl,
	_destroyed: boolean,

	_rememberCategory: (self: AnimMixerImpl<CategoryT, RefT>, category: CategoryT) -> (),
	_resolveOptions: (
		self: AnimMixerImpl<CategoryT, RefT>,
		category: CategoryT,
		options: AnimMixerPlayOptions?
	) -> (number, number, number, boolean, boolean?, boolean, number),
	_getCategoryDefaultFadeOut: (self: AnimMixerImpl<CategoryT, RefT>, category: CategoryT) -> number,
	_getCategoryPriority: (self: AnimMixerImpl<CategoryT, RefT>, category: CategoryT) -> Enum.AnimationPriority,
	_getCategoryTopEntry: (
		self: AnimMixerImpl<CategoryT, RefT>,
		category: CategoryT
	) -> CategoryEntry<RefT>?,
	_getCategoryTopSpeed: (self: AnimMixerImpl<CategoryT, RefT>, category: CategoryT) -> number?,
	_getCategorySpeedModifier: (
		self: AnimMixerImpl<CategoryT, RefT>,
		category: CategoryT
	) -> StackModifierTypes.StackModifierImpl,
	_getEffectiveSpeed: (
		self: AnimMixerImpl<CategoryT, RefT>,
		category: CategoryT,
		baseSpeed: number
	) -> number,
	_getAssetId: (self: AnimMixerImpl<CategoryT, RefT>, ref: RefT) -> AssetId,
	_getOrLoadPlayback: (
		self: AnimMixerImpl<CategoryT, RefT>,
		ref: RefT
	) -> AnimPlaybackTypes.AnimPlaybackImpl<RefT>,
	_stopPlayback: (self: AnimMixerImpl<CategoryT, RefT>, ref: RefT, fadeOut: number) -> (),
	_stopAndDestroyPlaybacks: (self: AnimMixerImpl<CategoryT, RefT>) -> (),
	_crossFade: (
		self: AnimMixerImpl<CategoryT, RefT>,
		category: CategoryT,
		ref: RefT,
		options: AnimMixerPlayOptions?
	) -> (),
	_reconcileCategory: (self: AnimMixerImpl<CategoryT, RefT>, category: CategoryT) -> (),
	_isRefReferenced: (
		self: AnimMixerImpl<CategoryT, RefT>,
		ref: RefT,
		excludedCategory: CategoryT?
	) -> boolean,
	_isRefTopInOtherCategory: (
		self: AnimMixerImpl<CategoryT, RefT>,
		ref: RefT,
		category: CategoryT
	) -> boolean,
	_clearRefReferences: (self: AnimMixerImpl<CategoryT, RefT>, ref: RefT) -> (),
	_onPlaybackStopped: (
		self: AnimMixerImpl<CategoryT, RefT>,
		playback: AnimPlaybackTypes.AnimPlaybackImpl<RefT>
	) -> (),
	_applyCategorySpeed: (self: AnimMixerImpl<CategoryT, RefT>, category: CategoryT) -> (),
	_applyAllCategorySpeeds: (self: AnimMixerImpl<CategoryT, RefT>) -> (),
}

return {}

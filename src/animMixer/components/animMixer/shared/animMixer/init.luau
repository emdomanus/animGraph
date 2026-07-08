--!strict
--!optimize 2
--!native

local AnimPlayback = require(script.Parent.Parent.Parent.animPlayback.shared.animPlayback)
local StackModifier = require(script.Parent.Parent.Parent.stackModifier.shared.stackModifier)
local AnimPlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.animPlayback)
local StackModifierTypes = require(script.Parent.Parent.Parent.Parent.types.components.stackModifier)
local Types = require(script.Parent.Parent.Parent.Parent.types.components.animMixer)

export type Release = Types.Release
export type AssetId = Types.AssetId
export type SpeedModifierOptions = Types.SpeedModifierOptions
export type AnimMixerPlayOptions = Types.AnimMixerPlayOptions
export type AnimMixerCategoryDefaults = Types.AnimMixerCategoryDefaults
export type AnimMixerConfig<CategoryT, RefT> = Types.AnimMixerConfig<CategoryT, RefT>
export type AnimMixer<CategoryT, RefT> = Types.AnimMixer<CategoryT, RefT>
export type AnimMixerImpl<CategoryT, RefT> = Types.AnimMixerImpl<CategoryT, RefT>
export type CategoryEntry<RefT> = Types.CategoryEntry<RefT>
export type AnimPlaybackImpl<RefT> = AnimPlaybackTypes.AnimPlaybackImpl<RefT>
export type StackModifierImpl = StackModifierTypes.StackModifierImpl

local DEFAULT_FADE_IN = 0.2
local DEFAULT_FADE_OUT = 0.2
local DEFAULT_SPEED = 1

local function noop(): ()
	return
end

local function optionNumber(value: number?, fallback: number): number
	return if value ~= nil then value else fallback
end

local function optionBoolean(value: boolean?, fallback: boolean): boolean
	return if value ~= nil then value else fallback
end

local function assertNonNegative(value: number, name: string): number
	assert(value >= 0, name .. " must be non-negative")
	return value
end

local AnimMixer = {}
AnimMixer.__index = AnimMixer

function AnimMixer.new<CategoryT, RefT>(
	config: AnimMixerConfig<CategoryT, RefT>
): AnimMixer<CategoryT, RefT>
	local categoryPriorities: { [CategoryT]: Enum.AnimationPriority } = config.categoryPriorities or {}
	local categoryDefaults: { [CategoryT]: AnimMixerCategoryDefaults } = config.categoryDefaults or {}
	local self: AnimMixerImpl<CategoryT, RefT> = setmetatable({}, AnimMixer) :: any

	self._animator = config.animator
	self._resolveAssetId = config.resolveAssetId

	self._defaultFadeIn = optionNumber(config.defaultFadeIn, DEFAULT_FADE_IN)
	self._defaultFadeOut = optionNumber(config.defaultFadeOut, DEFAULT_FADE_OUT)
	self._defaultSpeed = optionNumber(config.defaultSpeed, DEFAULT_SPEED)
	self._defaultLooped = optionBoolean(config.defaultLooped, false)
	self._defaultPriority = config.defaultPriority or Enum.AnimationPriority.Core
	self._categoryPriorities = categoryPriorities
	self._categoryDefaults = categoryDefaults

	self._knownCategories = {}
	self._knownCategorySet = {}
	self._categoryRefs = {}
	self._categoryBaseEntries = {}
	self._categoryStackEntries = {}
	self._categorySpeedModifiers = {}

	self._playbacks = {}
	self._nextCategoryEntryToken = 0
	self._nextCategoryEntryOrder = 0
	self._globalSpeedModifiers = StackModifier.new({
		onChanged = function()
			self:_applyAllCategorySpeeds()
		end,
	}) :: StackModifierImpl
	self._destroyed = false

	for category in self._categoryDefaults do
		self:_rememberCategory(category)
	end
	for category in self._categoryPriorities do
		self:_rememberCategory(category)
	end

	return self
end

function AnimMixer._rememberCategory<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): ()
	assert(category ~= nil, "category must not be nil")
	if self._knownCategorySet[category] then
		return
	end

	self._knownCategorySet[category] = true
	self._knownCategories[#self._knownCategories + 1] = category
end

function AnimMixer._resolveOptions<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	options: AnimMixerPlayOptions?
): (number, number, number, boolean, boolean?, boolean, number)
	local defaults = self._categoryDefaults[category]
	local fadeIn = self._defaultFadeIn
	local fadeOut = self._defaultFadeOut
	local speed = self._defaultSpeed
	local looped = self._defaultLooped
	local forceRestart = false
	local localPriority = 0

	if defaults ~= nil then
		fadeIn = optionNumber(defaults.fadeIn, fadeIn)
		fadeOut = optionNumber(defaults.fadeOut, fadeOut)
		speed = optionNumber(defaults.speed, speed)
		looped = optionBoolean(defaults.looped, looped)
		forceRestart = optionBoolean(defaults.forceRestart, forceRestart)
		localPriority = optionNumber(defaults.localPriority, localPriority)
	end

	if options ~= nil then
		fadeIn = optionNumber(options.fadeIn, fadeIn)
		fadeOut = optionNumber(options.fadeOut, fadeOut)
		speed = optionNumber(options.speed, speed)
		looped = optionBoolean(options.looped, looped)
		forceRestart = optionBoolean(options.forceRestart, forceRestart)
		localPriority = optionNumber(options.localPriority, localPriority)
	end

	return assertNonNegative(fadeIn, "fadeIn"),
		assertNonNegative(fadeOut, "fadeOut"),
		speed,
		looped,
		if options ~= nil then options.preserveTimePosition else nil,
		forceRestart,
		localPriority
end

function AnimMixer._getCategoryDefaultFadeOut<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): number
	local defaults = self._categoryDefaults[category]
	return if defaults ~= nil and defaults.fadeOut ~= nil then defaults.fadeOut else self._defaultFadeOut
end

function AnimMixer._getCategoryPriority<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): Enum.AnimationPriority
	local priority = self._categoryPriorities[category]
	if priority ~= nil then
		return priority
	end

	local defaults = self._categoryDefaults[category]
	if defaults ~= nil and defaults.priority ~= nil then
		return defaults.priority
	end

	return self._defaultPriority
end

function AnimMixer.play<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	ref: RefT,
	options: AnimMixerPlayOptions?
): ()
	if self._destroyed then
		return
	end

	self:_crossFade(category, ref, options)
end

function AnimMixer.push<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	ref: RefT,
	options: AnimMixerPlayOptions?
): Release
	if self._destroyed then
		return noop
	end

	self:_rememberCategory(category)
	self._nextCategoryEntryToken += 1
	self._nextCategoryEntryOrder += 1

	local fadeIn, fadeOut, speed, looped, preserveTimePosition, forceRestart, localPriority =
		self:_resolveOptions(category, options)
	local token = self._nextCategoryEntryToken
	local entry: CategoryEntry<RefT> = {
		token = token,
		ref = ref,
		localPriority = localPriority,
		order = self._nextCategoryEntryOrder,
		fadeIn = fadeIn,
		fadeOut = fadeOut,
		speed = speed,
		looped = looped,
		preserveTimePosition = preserveTimePosition,
		forceRestart = forceRestart,
	}

	local stack = self._categoryStackEntries[category]
	if stack == nil then
		stack = {}
		self._categoryStackEntries[category] = stack
	end
	stack[#stack + 1] = entry
	self:_reconcileCategory(category)

	local released = false
	return function()
		if released or self._destroyed then
			return
		end
		released = true

		local activeStack = self._categoryStackEntries[category]
		if activeStack == nil then
			return
		end

		local removedRef: RefT? = nil
		local removedFadeOut = fadeOut
		for index = #activeStack, 1, -1 do
			if activeStack[index].token == token then
				removedRef = activeStack[index].ref
				removedFadeOut = activeStack[index].fadeOut
				table.remove(activeStack, index)
				break
			end
		end

		if removedRef == nil then
			return
		end

		if #activeStack == 0 then
			self._categoryStackEntries[category] = nil
		end

		self:_reconcileCategory(category)
		if not self:_isRefReferenced(removedRef, nil) then
			self:_stopPlayback(removedRef, removedFadeOut)
		end
	end
end

function AnimMixer.stop<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	fadeOut: number?
): ()
	if self._destroyed then
		return
	end

	self:_rememberCategory(category)
	local baseEntry = self._categoryBaseEntries[category]
	if baseEntry == nil then
		return
	end

	local currentRef = baseEntry.ref
	local resolvedFadeOut = assertNonNegative(fadeOut or self:_getCategoryDefaultFadeOut(category), "fadeOut")
	self._categoryBaseEntries[category] = nil
	self:_reconcileCategory(category)

	if not self:_isRefReferenced(currentRef, nil) then
		self:_stopPlayback(currentRef, resolvedFadeOut)
	end
end

function AnimMixer.stopIfRef<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	ref: RefT,
	fadeOut: number?
): boolean
	if self._destroyed then
		return false
	end

	local baseEntry = self._categoryBaseEntries[category]
	if baseEntry == nil or baseEntry.ref ~= ref then
		return false
	end

	self:stop(category, fadeOut)
	return true
end

function AnimMixer.isCategoryPlaying<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): boolean
	local ref = self._categoryRefs[category]
	if ref == nil then
		return false
	end

	local playback = self._playbacks[ref]
	return playback ~= nil and playback:isPlaying()
end

function AnimMixer.getCategoryTrack<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): AnimationTrack?
	local ref = self._categoryRefs[category]
	if ref == nil then
		return nil
	end

	local playback = self._playbacks[ref]
	return if playback ~= nil then playback:getTrack() else nil
end

function AnimMixer.getCategoryRef<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): RefT?
	return self._categoryRefs[category]
end

function AnimMixer.getCategoryTimePosition<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): number?
	local ref = self._categoryRefs[category]
	local playback = if ref ~= nil then self._playbacks[ref] else nil
	return if playback ~= nil then playback:getTimePosition() else nil
end

function AnimMixer.getCategorySpeed<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): number?
	local ref = self._categoryRefs[category]
	local playback = if ref ~= nil then self._playbacks[ref] else nil
	return if playback ~= nil then playback:getSpeed() else nil
end

function AnimMixer.setCategorySpeed<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	speed: number
): ()
	if self._destroyed then
		return
	end

	local topEntry = self:_getCategoryTopEntry(category)
	if topEntry ~= nil then
		topEntry.speed = speed
	end

	self:_applyCategorySpeed(category)
end

function AnimMixer.setCategoryTimePosition<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	timePosition: number
): ()
	local ref = self._categoryRefs[category]
	local playback = if ref ~= nil then self._playbacks[ref] else nil
	if playback ~= nil then
		playback:setTimePosition(timePosition)
	end
end

function AnimMixer.adjustCategoryTimePosition<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	deltaTime: number
): ()
	local ref = self._categoryRefs[category]
	local playback = if ref ~= nil then self._playbacks[ref] else nil
	if playback ~= nil then
		playback:adjustTimePosition(deltaTime)
	end
end

function AnimMixer.adjustAllTimePositions<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	deltaTime: number
): ()
	for _, playback in self._playbacks do
		playback:adjustTimePosition(deltaTime)
	end
end

function AnimMixer.pushGlobalSpeedModifier<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	value: number,
	options: SpeedModifierOptions?
): Release
	if self._destroyed then
		return noop
	end

	return self._globalSpeedModifiers:push(value, options)
end

function AnimMixer.pushCategorySpeedModifier<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	value: number,
	options: SpeedModifierOptions?
): Release
	if self._destroyed then
		return noop
	end

	self:_rememberCategory(category)
	return self:_getCategorySpeedModifier(category):push(value, options)
end

function AnimMixer.clear<CategoryT, RefT>(self: AnimMixerImpl<CategoryT, RefT>): ()
	self:_stopAndDestroyPlaybacks()
	self._categoryRefs = {}
	self._categoryBaseEntries = {}
	self._categoryStackEntries = {}
	for _, modifier in self._categorySpeedModifiers do
		modifier:clear()
	end
	self._categorySpeedModifiers = {}
	self._globalSpeedModifiers:clear()
end

function AnimMixer.destroy<CategoryT, RefT>(self: AnimMixerImpl<CategoryT, RefT>): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self:clear()
end

function AnimMixer._getCategoryTopEntry<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): CategoryEntry<RefT>?
	local topEntry = self._categoryBaseEntries[category]
	local stack = self._categoryStackEntries[category]
	if stack == nil then
		return topEntry
	end

	for index = 1, #stack do
		local entry = stack[index]
		if
			topEntry == nil
			or entry.localPriority > topEntry.localPriority
			or (entry.localPriority == topEntry.localPriority and entry.order > topEntry.order)
		then
			topEntry = entry
		end
	end

	return topEntry
end

function AnimMixer._getCategoryTopSpeed<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): number?
	local topEntry = self:_getCategoryTopEntry(category)
	return if topEntry ~= nil then topEntry.speed else nil
end

function AnimMixer._getCategorySpeedModifier<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): StackModifierImpl
	local modifier = self._categorySpeedModifiers[category]
	if modifier ~= nil then
		return modifier
	end

	modifier = StackModifier.new({
		onChanged = function()
			self:_applyCategorySpeed(category)
		end,
	}) :: StackModifierImpl
	self._categorySpeedModifiers[category] = modifier

	return modifier
end

function AnimMixer._getEffectiveSpeed<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	baseSpeed: number
): number
	local categoryModifier = self._categorySpeedModifiers[category]
	return self._globalSpeedModifiers:evaluate(baseSpeed, categoryModifier)
end

function AnimMixer._getAssetId<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	ref: RefT
): AssetId
	local assetId = self._resolveAssetId(ref)
	assert(assetId > 0, "resolved animation asset id must be a positive number")
	return assetId
end

function AnimMixer._getOrLoadPlayback<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	ref: RefT
): AnimPlaybackImpl<RefT>
	local playback = self._playbacks[ref]
	if playback ~= nil then
		return playback
	end

	playback = AnimPlayback.new({
		ref = ref,
		assetId = self:_getAssetId(ref),
		animator = self._animator,
		onStopped = function(stoppedPlayback)
			self:_onPlaybackStopped(stoppedPlayback)
		end,
	}) :: AnimPlaybackImpl<RefT>
	self._playbacks[ref] = playback

	return playback
end

function AnimMixer._stopPlayback<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	ref: RefT,
	fadeOut: number
): ()
	local playback = self._playbacks[ref]
	if playback == nil then
		return
	end

	playback:stop(assertNonNegative(fadeOut, "fadeOut"))
end

function AnimMixer._stopAndDestroyPlaybacks<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>
): ()
	for _, playback in self._playbacks do
		playback:destroy()
	end

	self._playbacks = {}
end

function AnimMixer._crossFade<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT,
	ref: RefT,
	options: AnimMixerPlayOptions?
): ()
	self:_rememberCategory(category)

	local fadeIn, fadeOut, speed, looped, preserveTimePosition, forceRestart, localPriority =
		self:_resolveOptions(category, options)
	local baseEntry = self._categoryBaseEntries[category]
	local currentRef = if baseEntry ~= nil then baseEntry.ref else nil

	if baseEntry ~= nil and baseEntry.ref == ref then
		local playback = self._playbacks[baseEntry.ref]
		if playback ~= nil and playback:isPlaying() and not forceRestart then
			baseEntry.fadeIn = fadeIn
			baseEntry.fadeOut = fadeOut
			baseEntry.speed = speed
			baseEntry.looped = looped
			baseEntry.preserveTimePosition = preserveTimePosition
			baseEntry.forceRestart = forceRestart
			baseEntry.localPriority = localPriority
			self:_reconcileCategory(category)
			return
		end
	end

	local timePosition = 0
	if preserveTimePosition and currentRef ~= nil then
		local currentPlayback = self._playbacks[currentRef]
		if currentPlayback ~= nil and currentPlayback:isPlaying() then
			timePosition = currentPlayback:getTimePosition()
		end
	end

	if baseEntry == nil then
		baseEntry = {
			token = 0,
			ref = ref,
			localPriority = localPriority,
			order = 0,
			fadeIn = fadeIn,
			fadeOut = fadeOut,
			speed = speed,
			looped = looped,
			preserveTimePosition = preserveTimePosition,
			forceRestart = forceRestart,
		}
		self._categoryBaseEntries[category] = baseEntry
	else
		local oldRef = baseEntry.ref
		baseEntry.ref = ref
		baseEntry.localPriority = localPriority
		baseEntry.fadeIn = fadeIn
		baseEntry.fadeOut = fadeOut
		baseEntry.speed = speed
		baseEntry.looped = looped
		baseEntry.preserveTimePosition = preserveTimePosition
		baseEntry.forceRestart = forceRestart

		if oldRef ~= ref and not self:_isRefReferenced(oldRef, nil) then
			self:_stopPlayback(oldRef, fadeOut)
		end
	end

	self:_reconcileCategory(category)
	if preserveTimePosition and timePosition > 0 then
		self:setCategoryTimePosition(category, timePosition)
	end
end

function AnimMixer._reconcileCategory<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): ()
	if self._destroyed then
		return
	end

	local previousRef = self._categoryRefs[category]
	local topEntry = self:_getCategoryTopEntry(category)
	if topEntry == nil then
		self._categoryRefs[category] = nil
		if previousRef ~= nil and not self:_isRefReferenced(previousRef, nil) then
			self:_stopPlayback(previousRef, self:_getCategoryDefaultFadeOut(category))
		end
		return
	end

	local topRef = topEntry.ref
	self._categoryRefs[category] = topRef

	local playback = self:_getOrLoadPlayback(topRef)
	playback:play({
		fadeIn = topEntry.fadeIn,
		weight = 1,
		baseSpeed = topEntry.speed,
		effectiveSpeed = self:_getEffectiveSpeed(category, topEntry.speed),
		looped = topEntry.looped,
		priority = self:_getCategoryPriority(category),
		forceRestart = topEntry.forceRestart,
	})

	local baseEntry = self._categoryBaseEntries[category]
	if baseEntry ~= nil and baseEntry ~= topEntry and baseEntry.ref ~= topRef then
		local otherPlayback = self._playbacks[baseEntry.ref]
		if
			otherPlayback ~= nil
			and otherPlayback:isPlaying()
			and not self:_isRefTopInOtherCategory(baseEntry.ref, category)
		then
			otherPlayback:adjustWeight(0, baseEntry.fadeOut)
		end
	end

	local stack = self._categoryStackEntries[category]
	if stack ~= nil then
		for index = 1, #stack do
			local entry = stack[index]
			if entry ~= topEntry and entry.ref ~= topRef then
				local otherPlayback = self._playbacks[entry.ref]
				if
					otherPlayback ~= nil
					and otherPlayback:isPlaying()
					and not self:_isRefTopInOtherCategory(entry.ref, category)
				then
					otherPlayback:adjustWeight(0, entry.fadeOut)
				end
			end
		end
	end

	if previousRef ~= nil and previousRef ~= topRef and not self:_isRefReferenced(previousRef, nil) then
		self:_stopPlayback(previousRef, topEntry.fadeOut)
	end
end

function AnimMixer._isRefReferenced<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	ref: RefT,
	excludedCategory: CategoryT?
): boolean
	for category, entry in self._categoryBaseEntries do
		if category ~= excludedCategory and entry.ref == ref then
			return true
		end
	end

	for category, stack in self._categoryStackEntries do
		if category ~= excludedCategory then
			for index = 1, #stack do
				if stack[index].ref == ref then
					return true
				end
			end
		end
	end

	return false
end

function AnimMixer._isRefTopInOtherCategory<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	ref: RefT,
	category: CategoryT
): boolean
	for otherCategory, otherRef in self._categoryRefs do
		if otherCategory ~= category and otherRef == ref then
			return true
		end
	end

	return false
end

function AnimMixer._clearRefReferences<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	ref: RefT
): ()
	for _, category in self._knownCategories do
		local removed = false
		local baseEntry = self._categoryBaseEntries[category]
		if baseEntry ~= nil and baseEntry.ref == ref then
			self._categoryBaseEntries[category] = nil
			removed = true
		end

		local stack = self._categoryStackEntries[category]
		if stack ~= nil then
			for index = #stack, 1, -1 do
				if stack[index].ref == ref then
					table.remove(stack, index)
					removed = true
				end
			end
			if #stack == 0 then
				self._categoryStackEntries[category] = nil
			end
		end

		if removed then
			self:_reconcileCategory(category)
		end
	end
end

function AnimMixer._onPlaybackStopped<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	playback: AnimPlaybackImpl<RefT>
): ()
	if self._destroyed or playback:isPlaying() then
		return
	end

	self:_clearRefReferences(playback:getRef())
end

function AnimMixer._applyCategorySpeed<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>,
	category: CategoryT
): ()
	local ref = self._categoryRefs[category]
	if ref == nil then
		return
	end

	local playback = self._playbacks[ref]
	local speed = self:_getCategoryTopSpeed(category)
	if playback ~= nil and speed ~= nil then
		playback:setBaseSpeed(speed)
		playback:setEffectiveSpeed(self:_getEffectiveSpeed(category, speed))
	end
end

function AnimMixer._applyAllCategorySpeeds<CategoryT, RefT>(
	self: AnimMixerImpl<CategoryT, RefT>
): ()
	for _, category in self._knownCategories do
		self:_applyCategorySpeed(category)
	end
end

return AnimMixer

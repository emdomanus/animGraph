--!strict
--!optimize 2

-- The existing playback object implements this observation surface directly.
export type TrackMarkerSource<LayerT, StateT, ClipT> = {
	read getTrackKey: (self: TrackMarkerSource<LayerT, StateT, ClipT>) -> string,
	read getGeneration: (self: TrackMarkerSource<LayerT, StateT, ClipT>) -> number,
	read getLayer: (self: TrackMarkerSource<LayerT, StateT, ClipT>) -> LayerT,
	read getState: (self: TrackMarkerSource<LayerT, StateT, ClipT>) -> StateT?,
	read getClip: (self: TrackMarkerSource<LayerT, StateT, ClipT>) -> ClipT,
}

return {}

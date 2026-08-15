<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";

const props = withDefaults(
	defineProps<{
		src: string;
		alt: string;
		height?: string;
		initialZoom?: number;
		caption?: string;
	}>(),
	{
		height: "min(72vh, 720px)",
		initialZoom: 1,
		caption: undefined,
	},
);

const viewport = ref<HTMLDivElement>();
const image = ref<HTMLImageElement>();
const scale = ref(1);
const offsetX = ref(16);
const offsetY = ref(16);
const isDragging = ref(false);
const fitMultiplier = ref<number | undefined>(props.initialZoom);

const minimumScale = 0.15;
const maximumScale = 4;
let pointerX = 0;
let pointerY = 0;
let startX = 0;
let startY = 0;
let resizeObserver: ResizeObserver | undefined;

const transform = computed(
	() => `translate(${offsetX.value}px, ${offsetY.value}px) scale(${scale.value})`,
);
const scaleLabel = computed(() => `${Math.round(scale.value * 100)}%`);

function clampScale(value: number): number {
	return Math.min(maximumScale, Math.max(minimumScale, value));
}

function fit(multiplier = 1): void {
	const viewportElement = viewport.value;
	const imageElement = image.value;
	if (!viewportElement || !imageElement?.naturalWidth) {
		return;
	}

	const availableWidth = Math.max(100, viewportElement.clientWidth - 32);
	const availableHeight = Math.max(100, viewportElement.clientHeight - 32);
	const nextScale = clampScale(
		Math.min(
			availableWidth / imageElement.naturalWidth,
			availableHeight / imageElement.naturalHeight,
		) * multiplier,
	);
	scale.value = nextScale;
	offsetX.value = (viewportElement.clientWidth - imageElement.naturalWidth * nextScale) / 2;
	offsetY.value = (viewportElement.clientHeight - imageElement.naturalHeight * nextScale) / 2;
	fitMultiplier.value = multiplier;
}

function actualSize(): void {
	scale.value = 1;
	offsetX.value = 16;
	offsetY.value = 16;
	fitMultiplier.value = undefined;
}

function zoomAt(factor: number, pointX?: number, pointY?: number): void {
	const viewportElement = viewport.value;
	if (!viewportElement) {
		return;
	}

	const anchorX = pointX ?? viewportElement.clientWidth / 2;
	const anchorY = pointY ?? viewportElement.clientHeight / 2;
	const nextScale = clampScale(scale.value * factor);
	const imageX = (anchorX - offsetX.value) / scale.value;
	const imageY = (anchorY - offsetY.value) / scale.value;

	offsetX.value = anchorX - imageX * nextScale;
	offsetY.value = anchorY - imageY * nextScale;
	scale.value = nextScale;
	fitMultiplier.value = undefined;
}

function onImageLoad(): void {
	nextTick(() => fit(props.initialZoom));
}

function onPointerDown(event: PointerEvent): void {
	if (event.button !== 0 || !viewport.value) {
		return;
	}

	isDragging.value = true;
	pointerX = event.clientX;
	pointerY = event.clientY;
	startX = offsetX.value;
	startY = offsetY.value;
	viewport.value.setPointerCapture(event.pointerId);
	event.preventDefault();
}

function onPointerMove(event: PointerEvent): void {
	if (!isDragging.value) {
		return;
	}

	offsetX.value = startX + event.clientX - pointerX;
	offsetY.value = startY + event.clientY - pointerY;
	fitMultiplier.value = undefined;
}

function onPointerUp(event: PointerEvent): void {
	if (!isDragging.value || !viewport.value) {
		return;
	}

	isDragging.value = false;
	if (viewport.value.hasPointerCapture(event.pointerId)) {
		viewport.value.releasePointerCapture(event.pointerId);
	}
}

function onWheel(event: WheelEvent): void {
	if ((!event.ctrlKey && !event.metaKey) || !viewport.value) {
		return;
	}

	event.preventDefault();
	const bounds = viewport.value.getBoundingClientRect();
	zoomAt(
		Math.exp(-event.deltaY * 0.002),
		event.clientX - bounds.left,
		event.clientY - bounds.top,
	);
}

function onKeydown(event: KeyboardEvent): void {
	const panStep = event.shiftKey ? 80 : 32;
	switch (event.key) {
		case "ArrowLeft":
			offsetX.value += panStep;
			fitMultiplier.value = undefined;
			break;
		case "ArrowRight":
			offsetX.value -= panStep;
			fitMultiplier.value = undefined;
			break;
		case "ArrowUp":
			offsetY.value += panStep;
			fitMultiplier.value = undefined;
			break;
		case "ArrowDown":
			offsetY.value -= panStep;
			fitMultiplier.value = undefined;
			break;
		case "+":
		case "=":
			zoomAt(1.2);
			break;
		case "-":
		case "_":
			zoomAt(1 / 1.2);
			break;
		case "0":
			actualSize();
			break;
		case "Home":
			fit();
			break;
		default:
			return;
	}

	event.preventDefault();
}

onMounted(() => {
	resizeObserver = new ResizeObserver(() => {
		if (fitMultiplier.value !== undefined) {
			fit(fitMultiplier.value);
		}
	});

	if (viewport.value) {
		resizeObserver.observe(viewport.value);
	}

	if (image.value?.complete) {
		onImageLoad();
	}
});

onBeforeUnmount(() => resizeObserver?.disconnect());
</script>

<template>
	<figure class="zoomable-diagram">
		<div class="zoomable-diagram__toolbar">
			<div class="zoomable-diagram__controls" aria-label="Diagram zoom controls">
				<button type="button" aria-label="Zoom out" title="Zoom out" @click="zoomAt(1 / 1.2)">
					−
				</button>
				<output aria-live="polite">{{ scaleLabel }}</output>
				<button type="button" aria-label="Zoom in" title="Zoom in" @click="zoomAt(1.2)">
					+
				</button>
				<button type="button" @click="fit()">Fit</button>
				<button type="button" @click="actualSize">100%</button>
			</div>
			<span class="zoomable-diagram__hint">Drag to pan · Ctrl/⌘ + wheel to zoom</span>
		</div>
		<div
			ref="viewport"
			class="zoomable-diagram__viewport"
			:class="{ 'is-dragging': isDragging }"
			:style="{ height }"
			role="group"
			:aria-label="`${alt}. Interactive diagram: drag or use arrow keys to pan; use the controls to zoom.`"
			tabindex="0"
			@keydown="onKeydown"
			@pointerdown="onPointerDown"
			@pointermove="onPointerMove"
			@pointerup="onPointerUp"
			@pointercancel="onPointerUp"
			@wheel="onWheel"
		>
			<img
				ref="image"
				class="zoomable-diagram__image"
				:src="src"
				:alt="alt"
				:style="{ transform }"
				draggable="false"
				@load="onImageLoad"
			/>
		</div>
		<figcaption v-if="caption">{{ caption }}</figcaption>
	</figure>
</template>

<style scoped>
.zoomable-diagram {
	margin: 24px 0;
	overflow: hidden;
	border: 1px solid var(--vp-c-border);
	border-radius: 14px;
	background: var(--vp-c-bg);
}

.zoomable-diagram__toolbar {
	display: flex;
	align-items: center;
	justify-content: space-between;
	gap: 16px;
	min-height: 48px;
	padding: 8px 10px;
	border-bottom: 1px solid var(--vp-c-divider);
	background: var(--vp-c-bg-alt);
}

.zoomable-diagram__controls {
	display: flex;
	align-items: center;
	gap: 6px;
}

.zoomable-diagram button {
	min-width: 34px;
	height: 32px;
	padding: 0 10px;
	border: 1px solid var(--vp-c-border);
	border-radius: 8px;
	background: var(--vp-c-bg-elv);
	color: var(--vp-c-text-1);
	font: inherit;
	font-size: 13px;
	font-weight: 600;
	cursor: pointer;
}

.zoomable-diagram button:hover {
	border-color: var(--vp-c-brand-1);
	color: var(--vp-c-brand-1);
}

.zoomable-diagram button:focus-visible,
.zoomable-diagram__viewport:focus-visible {
	outline: 2px solid var(--vp-c-brand-1);
	outline-offset: -2px;
}

.zoomable-diagram output {
	min-width: 52px;
	color: var(--vp-c-text-2);
	font-size: 12px;
	font-variant-numeric: tabular-nums;
	text-align: center;
}

.zoomable-diagram__hint {
	color: var(--vp-c-text-3);
	font-size: 12px;
}

.zoomable-diagram__viewport {
	position: relative;
	width: 100%;
	min-height: 280px;
	overflow: hidden;
	background-color: var(--vp-c-bg);
	background-image: radial-gradient(var(--vp-c-divider) 0.7px, transparent 0.7px);
	background-size: 18px 18px;
	cursor: grab;
	touch-action: none;
}

.zoomable-diagram__viewport.is-dragging {
	cursor: grabbing;
}

.zoomable-diagram__image {
	position: absolute;
	top: 0;
	left: 0;
	max-width: none !important;
	margin: 0 !important;
	transform-origin: 0 0;
	user-select: none;
	will-change: transform;
}

.zoomable-diagram figcaption {
	padding: 8px 12px;
	border-top: 1px solid var(--vp-c-divider);
	color: var(--vp-c-text-3);
	font-size: 12px;
}

@media (max-width: 640px) {
	.zoomable-diagram__hint {
		display: none;
	}
}

@media (prefers-reduced-motion: reduce) {
	.zoomable-diagram__image {
		will-change: auto;
	}
}
</style>

import type { Theme } from "vitepress";
import DefaultTheme from "vitepress/theme";
import ZoomableDiagram from "./components/ZoomableDiagram.vue";
import "./custom.css";

export default {
	extends: DefaultTheme,
	enhanceApp({ app }) {
		app.component("ZoomableDiagram", ZoomableDiagram);
	},
} satisfies Theme;

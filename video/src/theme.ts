import { Easing } from "remotion";

// The site's neon frame stops, so the video glows the same colours as the app.
export const NEON_STOPS =
  "#8e42e9, #6769e8, #47abe1, #68def3, #59aeda, #5d57ee, #8e41e3, #c75976, #d1a036, #eab748, #d99c59, #d875a1, #b64ad7, #8e42e9";

export const SANS = '-apple-system, "SF Pro Display", "Helvetica Neue", sans-serif';
export const SERIF = '"New York", "Iowan Old Style", Georgia, serif';

export const FG = "#f5f5f7";
export const DIM = "#a1a1a6";
export const FAINT = "#6e6e73";

export const OUT = Easing.bezier(0.16, 1, 0.3, 1); // fast start, long soft landing
export const INOUT = Easing.bezier(0.65, 0, 0.35, 1);
export const IN = Easing.bezier(0.55, 0, 1, 0.45);

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

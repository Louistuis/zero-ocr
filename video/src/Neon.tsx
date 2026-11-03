import React from "react";
import { NEON_STOPS } from "./theme";

type RimProps = {
  x: number;
  y: number;
  w: number;
  h: number;
  r: number;
  angle: number;
  glow?: number; // 0..1 strength of the bloom
  opacity?: number;
};

const ring = (x: number, y: number, w: number, h: number, r: number, t: number, angle: number): React.CSSProperties => ({
  position: "absolute",
  left: x - t,
  top: y - t,
  width: w + 2 * t,
  height: h + 2 * t,
  borderRadius: r + t,
  padding: t,
  boxSizing: "border-box",
  background: `conic-gradient(from ${angle}deg, ${NEON_STOPS})`,
  WebkitMask: "linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)",
  WebkitMaskComposite: "xor",
  maskComposite: "exclude",
});

/** A rim of neon light: a sharp line, a white-hot core and three layers of bloom. */
export const NeonRim: React.FC<RimProps> = ({ x, y, w, h, r, angle, glow = 1, opacity = 1 }) => (
  <div style={{ position: "absolute", inset: 0, opacity, pointerEvents: "none" }}>
    <div style={{ position: "absolute", inset: 0, filter: "blur(70px)", opacity: 0.4 * glow }}>
      <div style={ring(x, y, w, h, r, 34, angle)} />
    </div>
    <div style={{ position: "absolute", inset: 0, filter: "blur(26px)", opacity: 0.65 * glow }}>
      <div style={ring(x, y, w, h, r, 14, angle)} />
    </div>
    <div style={{ position: "absolute", inset: 0, filter: "blur(7px)", opacity: 0.95 * glow }}>
      <div style={ring(x, y, w, h, r, 6, angle)} />
    </div>
    <div style={ring(x, y, w, h, r, 3, angle)} />
    <div style={{ ...ring(x, y, w, h, r, 1.5, angle), background: "rgba(255,255,255,0.75)" }} />
  </div>
);

/** A soft, slowly turning field of the same colours, for behind the icon and the headline. */
export const NeonBloom: React.FC<{ size: number; angle: number; opacity: number; scale?: number; squash?: number }> = ({
  size,
  angle,
  opacity,
  scale = 1,
  squash = 1,
}) => (
  <div
    style={{
      position: "absolute",
      left: "50%",
      top: "50%",
      width: size,
      height: size * squash,
      marginLeft: -size / 2,
      marginTop: (-size * squash) / 2,
      borderRadius: "50%",
      background: `conic-gradient(from ${angle}deg, ${NEON_STOPS})`,
      filter: `blur(${size * 0.16}px)`,
      opacity,
      scale,
    }}
  />
);

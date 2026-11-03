import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { NeonBloom } from "../Neon";
import { clamp, DIM, FG, OUT, SANS } from "../theme";

const LINES = [["Read", "any", "text"], ["on", "your", "screen."]];

/** The promise, word by word, over a slow glow, then the name and where to get it. 154 frames at 60 fps. */
export const Outro: React.FC = () => {
  const f = useCurrentFrame();
  let n = 0;

  return (
    <AbsoluteFill style={{ backgroundColor: "#000", fontFamily: SANS, opacity: interpolate(f, [0, 14, 142, 154], [0, 1, 1, 0], clamp) }}>
      <div style={{ position: "absolute", inset: 0, translate: "0 -60px" }}>
        <NeonBloom
          size={1100}
          squash={0.42}
          angle={f * 0.9}
          opacity={interpolate(f, [0, 60], [0, 0.3], { ...clamp, easing: OUT })}
          scale={interpolate(f, [0, 154], [0.85, 1.05], clamp)}
        />
      </div>
      <div style={{ position: "absolute", top: 290, width: "100%", textAlign: "center", color: FG, fontSize: 132, fontWeight: 700, letterSpacing: "-0.04em", lineHeight: 1.06 }}>
        {LINES.map((line, li) => (
          <div key={li}>
            {line.map((w) => {
              const s = 4 + n++ * 5;
              return (
                <span
                  key={w}
                  style={{
                    display: "inline-block",
                    margin: "0 0.12em",
                    opacity: interpolate(f, [s, s + 26], [0, 1], { ...clamp, easing: OUT }),
                    translate: `0 ${interpolate(f, [s, s + 34], [50, 0], { ...clamp, easing: OUT })}px`,
                    filter: `blur(${interpolate(f, [s, s + 26], [14, 0], { ...clamp, easing: OUT })}px)`,
                  }}
                >
                  {w}
                </span>
              );
            })}
          </div>
        ))}
      </div>
      <div
        style={{
          position: "absolute", top: 610, width: "100%", textAlign: "center", color: DIM, fontSize: 46, fontWeight: 500, letterSpacing: "-0.01em",
          opacity: interpolate(f, [44, 74], [0, 1], { ...clamp, easing: OUT }),
          translate: `0 ${interpolate(f, [44, 80], [24, 0], { ...clamp, easing: OUT })}px`,
        }}
      >
        Fast, private and free. Entirely on your Mac.
      </div>
      <div
        style={{
          position: "absolute", top: 790, width: "100%", display: "flex", justifyContent: "center", alignItems: "center", gap: 22,
          opacity: interpolate(f, [70, 100], [0, 1], { ...clamp, easing: OUT }),
          scale: interpolate(f, [70, 110], [0.94, 1], { ...clamp, easing: OUT }),
        }}
      >
        <Img src={staticFile("icon.png")} style={{ width: 84, height: 84 }} />
        <div style={{ textAlign: "left" }}>
          <div style={{ color: FG, fontSize: 40, fontWeight: 650, letterSpacing: "-0.02em" }}>Zero OCR</div>
          <div style={{ color: DIM, fontSize: 28, marginTop: 2 }}>zero.lou15.com</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

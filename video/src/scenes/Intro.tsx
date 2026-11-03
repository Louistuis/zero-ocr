import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { NeonBloom } from "../Neon";
import { clamp, DIM, FG, IN, OUT, SANS } from "../theme";

/** The icon lights up out of black, then the name. 160 frames at 60 fps. */
export const Intro: React.FC = () => {
  const f = useCurrentFrame();
  const exit = interpolate(f, [122, 160], [0, 1], { ...clamp, easing: IN });

  return (
    <AbsoluteFill style={{ backgroundColor: "#000", fontFamily: SANS }}>
      <AbsoluteFill
        style={{
          opacity: 1 - exit,
          scale: 1 + exit * 0.06,
          filter: `blur(${exit * 14}px)`,
        }}
      >
        <div style={{ position: "absolute", inset: 0, translate: "0 -70px" }}>
          <NeonBloom
            size={520}
            angle={f * 1.2}
            opacity={interpolate(f, [0, 70], [0, 0.55], { ...clamp, easing: OUT })}
            scale={interpolate(f, [0, 90], [0.4, 1], { ...clamp, easing: OUT })}
          />
        </div>
        <Img
          src={staticFile("icon.png")}
          style={{
            position: "absolute",
            left: "50%",
            top: "50%",
            width: 260,
            height: 260,
            marginLeft: -130,
            marginTop: -200,
            opacity: interpolate(f, [6, 46], [0, 1], { ...clamp, easing: OUT }),
            scale: interpolate(f, [6, 70], [0.82, 1], { ...clamp, easing: OUT }),
            filter: `blur(${interpolate(f, [6, 46], [12, 0], { ...clamp, easing: OUT })}px) drop-shadow(0 30px 60px rgba(0,0,0,0.6))`,
          }}
        />
        <div
          style={{
            position: "absolute",
            top: 640,
            width: "100%",
            textAlign: "center",
            color: FG,
            fontSize: 110,
            fontWeight: 700,
            letterSpacing: "-0.035em",
            opacity: interpolate(f, [38, 72], [0, 1], { ...clamp, easing: OUT }),
            translate: `0 ${interpolate(f, [38, 80], [36, 0], { ...clamp, easing: OUT })}px`,
            filter: `blur(${interpolate(f, [38, 72], [10, 0], { ...clamp, easing: OUT })}px)`,
          }}
        >
          Zero OCR
        </div>
        <div
          style={{
            position: "absolute",
            top: 790,
            width: "100%",
            textAlign: "center",
            color: DIM,
            fontSize: 44,
            fontWeight: 500,
            letterSpacing: "-0.01em",
            opacity: interpolate(f, [60, 92], [0, 1], { ...clamp, easing: OUT }),
            translate: `0 ${interpolate(f, [60, 100], [24, 0], { ...clamp, easing: OUT })}px`,
          }}
        >
          Text recognition that never leaves your Mac.
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { Intro } from "./scenes/Intro";
import { Demo } from "./scenes/Demo";
import { Outro } from "./scenes/Outro";

/** Ten seconds at 60 fps. The scenes overlap a little so each dissolves into the next. */
export const Showcase: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: "#000" }}>
    <Sequence name="Intro" from={0} durationInFrames={160}>
      <Intro />
    </Sequence>
    <Sequence name="Demo" from={138} durationInFrames={312}>
      <Demo />
    </Sequence>
    <Sequence name="Outro" from={446} durationInFrames={154}>
      <Outro />
    </Sequence>
  </AbsoluteFill>
);

import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { NeonRim, NeonBloom } from "../Neon";
import { clamp, DIM, FG, IN, INOUT, OUT, SANS, SERIF } from "../theme";

const PARAGRAPH = [
  "The lighthouse keeper logged every passing ship in a",
  "leather notebook. On the night of 14 March 1987 he",
  "recorded a freighter named Halvard, bound for Rotterdam",
  "with 2,340 tonnes of timber.",
];
const AFTER = [
  "The weather was poor: wind from the northwest at 38 knots,",
  "visibility under two nautical miles. He noted that the",
  "vessel's starboard light flickered twice before vanishing.",
];
const WORDS = PARAGRAPH.join(" ").split(" ");

// Where things sit on the 1920 x 1080 screen.
const WIN = { x: 190, y: 190, w: 1060, h: 720 };
const SEL = { x: 268, y: 386, w: 920, h: 224 };
const SEL_C = { x: SEL.x + SEL.w / 2, y: SEL.y + SEL.h / 2 };
const CARD = { right: 1860, y: 80, w: 580, h: 366, pillW: 290, pillH: 72 };
const PILL_C = { x: CARD.right - CARD.pillW / 2, y: CARD.y + CARD.pillH / 2 };
const CTRL = { x: 1180, y: 40 };

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const bez = (t: number) => ({
  x: (1 - t) ** 2 * SEL_C.x + 2 * (1 - t) * t * CTRL.x + t * t * PILL_C.x,
  y: (1 - t) ** 2 * SEL_C.y + 2 * (1 - t) * t * CTRL.y + t * t * PILL_C.y,
});

/** ⇧⌘2, a drag, the neon frame, the flight to the corner and the card. 312 frames at 60 fps. */
export const Demo: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();

  const enter = interpolate(f, [0, 48], [0, 1], { ...clamp, easing: OUT });
  const exit = interpolate(f, [280, 312], [0, 1], { ...clamp, easing: IN });
  // The camera pushes in on the selection, then follows the light to the card.
  const cam = { easing: INOUT, ...clamp };
  const z = interpolate(f, [56, 122, 150, 204, 290], [1, 1.16, 1.16, 1.5, 1.54], cam);
  const fx = Math.min(Math.max(interpolate(f, [56, 122, 150, 204], [960, 728, 728, 1570], cam), 960 / z), 1920 - 960 / z);
  const fy = Math.min(Math.max(interpolate(f, [56, 122, 150, 204], [540, 498, 498, 276], cam), 540 / z), 1080 - 540 / z);
  const drag = interpolate(f, [62, 118], [0, 1], { ...clamp, easing: INOUT });
  const collapse = interpolate(f, [128, 156], [0, 1], { ...clamp, easing: IN });
  const fly = interpolate(f, [156, 188], [0, 1], { ...clamp, easing: INOUT });
  const open = spring({ frame: f - 186, fps, config: { damping: 15, stiffness: 120, mass: 0.9 } });
  const done = interpolate(f, [236, 250], [0, 1], { ...clamp, easing: OUT });
  const angle = f * 2.2;

  // The selection: dragged open, then pulled into a point of light.
  const sw = lerp(SEL.w * drag, 26, collapse);
  const sh = lerp(SEL.h * drag, 26, collapse);
  const sx = lerp(SEL.x, SEL_C.x - 13, collapse);
  const sy = lerp(SEL.y, SEL_C.y - 13, collapse);
  const rimOn = f >= 62 && f < 157;

  // The card grows out of a pill anchored to the top-right corner.
  const cw = lerp(CARD.pillW, CARD.w, open);
  const ch = lerp(CARD.pillH, CARD.h, open);
  const cx = CARD.right - cw;
  const streamed = interpolate(f, [204, 252], [0, WORDS.length], clamp);

  return (
    <AbsoluteFill style={{ backgroundColor: "#000", fontFamily: SANS, overflow: "hidden" }}>
      <AbsoluteFill
        style={{
          opacity: enter * (1 - exit),
          scale: lerp(1.08, 1, enter) + exit * 0.05,
          filter: `blur(${(1 - enter) * 18 + exit * 14}px)`,
        }}
      >
        <div style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, transformOrigin: "0 0", transform: `translate(${960 - fx * z}px, ${540 - fy * z}px) scale(${z})` }}>
        {/* Wallpaper */}
        <AbsoluteFill
          style={{
            background: `radial-gradient(60% 70% at ${78 + Math.sin(f / 60) * 3}% 8%, rgba(126, 86, 255, 0.42), transparent 70%),
              radial-gradient(50% 60% at 6% 96%, rgba(56, 140, 255, 0.3), transparent 70%),
              radial-gradient(40% 40% at 50% 60%, rgba(200, 90, 140, 0.1), transparent 70%),
              linear-gradient(180deg, #121219, #07070a)`,
          }}
        />
        {/* Menu bar */}
        <div
          style={{
            position: "absolute", left: 0, top: 0, right: 0, height: 44, display: "flex", alignItems: "center",
            justifyContent: "space-between", padding: "0 28px", background: "rgba(0,0,0,0.28)",
            color: "rgba(255,255,255,0.85)", fontSize: 21, fontWeight: 500,
          }}
        >
          <div style={{ display: "flex", gap: 30 }}>
            <b style={{ fontWeight: 700 }}>Preview</b><span>File</span><span>Edit</span><span>View</span><span>Window</span>
          </div>
          <div style={{ display: "flex", gap: 26 }}><span>Mon 3 Nov</span><span>09:41</span></div>
        </div>

        {/* The document */}
        <div
          style={{
            position: "absolute", left: WIN.x, top: WIN.y, width: WIN.w, height: WIN.h, borderRadius: 22,
            background: "#f6f5f1", boxShadow: "0 50px 120px -30px rgba(0,0,0,0.85), 0 0 0 1px rgba(255,255,255,0.08)",
          }}
        >
          <div style={{ position: "absolute", left: 26, top: 24, display: "flex", gap: 12 }}>
            {[0, 1, 2].map((i) => (
              <i key={i} style={{ width: 16, height: 16, borderRadius: 8, background: "#d9d6cf", display: "block" }} />
            ))}
          </div>
          <div style={{ position: "absolute", left: 94, top: 96, fontSize: 46, fontWeight: 700, color: "#1d1d1f", letterSpacing: "-0.02em" }}>
            Harbour log, winter
          </div>
          {PARAGRAPH.map((l, i) => (
            <div key={l} style={{ position: "absolute", left: 94, top: 206 + i * 50, fontFamily: SERIF, fontSize: 31, color: "#1d1d1f", whiteSpace: "nowrap" }}>
              {l}
            </div>
          ))}
          {AFTER.map((l, i) => (
            <div key={l} style={{ position: "absolute", left: 94, top: 460 + i * 50, fontFamily: SERIF, fontSize: 31, color: "#6e6e73", whiteSpace: "nowrap" }}>
              {l}
            </div>
          ))}
        </div>

        {/* Selection and its neon frame */}
        {rimOn && (
          <>
            <div
              style={{
                position: "absolute", left: sx, top: sy, width: sw, height: sh, borderRadius: lerp(10, 13, collapse),
                background: `rgba(130, 100, 255, ${0.07 + collapse * 0.5})`,
              }}
            />
            <NeonRim
              x={sx} y={sy} w={sw} h={sh} r={lerp(10, 13, collapse)} angle={angle}
              glow={interpolate(f, [62, 118, 150], [0.35, 0.8, 1.2], clamp)}
            />
          </>
        )}
        {/* Crosshair at the dragging corner */}
        <svg
          width="44" height="44" viewBox="0 0 44 44"
          style={{
            position: "absolute", left: SEL.x + SEL.w * drag - 22, top: SEL.y + SEL.h * drag - 22,
            opacity: interpolate(f, [52, 60, 118, 128], [0, 1, 1, 0], clamp),
          }}
        >
          <path d="M22 4v36M4 22h36" stroke="#fff" strokeWidth="6" strokeLinecap="round" />
          <path d="M22 4v36M4 22h36" stroke="#1d1d1f" strokeWidth="2.4" strokeLinecap="round" />
        </svg>

        {/* The point of light and its trail */}
        {f >= 156 && f < 196 &&
          Array.from({ length: 12 }).map((_, k) => {
            const t = Math.max(0, fly - k * 0.03);
            const p = bez(t);
            const size = 26 - k * 1.6;
            return (
              <div
                key={k}
                style={{
                  position: "absolute", left: p.x - size / 2, top: p.y - size / 2, width: size, height: size, borderRadius: "50%",
                  background: "#fff",
                  opacity: (k === 0 ? 1 : (1 - k / 12) * 0.45) * interpolate(f, [186, 196], [1, 0], clamp),
                  boxShadow: k === 0 ? "0 0 14px 5px #fff, 0 0 40px 14px #8e42e9, 0 0 80px 30px rgba(71,171,225,0.7)" : "0 0 18px 6px rgba(142,66,233,0.6)",
                }}
              />
            );
          })}
        {/* Landing flash */}
        <div
          style={{
            position: "absolute", left: PILL_C.x - 120, top: PILL_C.y - 120, width: 240, height: 240, borderRadius: "50%",
            border: "3px solid rgba(255,255,255,0.9)", boxShadow: "0 0 40px 10px rgba(142,66,233,0.6)",
            scale: interpolate(f, [186, 214], [0.1, 1.6], { ...clamp, easing: OUT }),
            opacity: interpolate(f, [186, 190, 214], [0, 0.9, 0], clamp),
          }}
        />

        {/* The card */}
        {f >= 186 && (
          <>
            <NeonRim
              x={cx} y={CARD.y} w={cw} h={ch} r={lerp(36, 30, open)} angle={angle}
              glow={interpolate(f, [186, 200, 250, 290], [1.2, 0.9, 0.7, 0.25], clamp)}
              opacity={interpolate(f, [186, 192], [0, 1], clamp)}
            />
            <div
              style={{
                position: "absolute", left: cx, top: CARD.y, width: cw, height: ch, borderRadius: lerp(36, 30, open),
                overflow: "hidden", background: "rgba(30, 30, 36, 0.8)", backdropFilter: "blur(40px) saturate(180%)",
                boxShadow: "0 40px 90px -20px rgba(0,0,0,0.7), inset 0 1px 0 rgba(255,255,255,0.16), inset 0 0 0 1px rgba(255,255,255,0.08)",
              }}
            >
              <div style={{ position: "absolute", left: 30, top: 28, width: CARD.w - 60, opacity: interpolate(f, [196, 214], [0, 1], clamp) }}>
                <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
                  <div style={{ position: "relative", width: 52, height: 52 }}>
                    <div style={{ position: "absolute", inset: 0, borderRadius: 26, opacity: 1 - done, overflow: "hidden" }}>
                      <NeonBloom size={52} angle={angle * 3} opacity={1} />
                      <div style={{ position: "absolute", inset: 5, borderRadius: 21, background: "#1e1e24" }} />
                    </div>
                    <div style={{ position: "absolute", inset: 0, borderRadius: 26, background: "rgba(52,199,89,0.22)", opacity: done, scale: lerp(0.6, 1, done) }} />
                    <svg viewBox="0 0 24 24" width="52" height="52" style={{ position: "absolute", inset: 0, padding: 12, boxSizing: "border-box" }}>
                      <path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="#34c759" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"
                        strokeDasharray="24" strokeDashoffset={24 * (1 - interpolate(f, [238, 256], [0, 1], { ...clamp, easing: OUT }))} />
                    </svg>
                  </div>
                  <div style={{ position: "relative", height: 60, flex: 1 }}>
                    <div style={{ position: "absolute", top: 0, fontSize: 28, fontWeight: 650, color: FG, opacity: 1 - done }}>Reading…</div>
                    <div style={{ position: "absolute", top: 0, fontSize: 28, fontWeight: 650, color: FG, opacity: done, translate: `0 ${(1 - done) * 10}px` }}>
                      Copied {WORDS.length} words
                    </div>
                    <div style={{ position: "absolute", top: 36, fontSize: 20, color: DIM }}>Preview · 0.9 s</div>
                  </div>
                </div>
                <div style={{ marginTop: 22, fontSize: 23, lineHeight: 1.5, color: "#e5e5ea", height: 150 }}>
                  {WORDS.map((w, i) => (
                    <span key={i} style={{ opacity: Math.min(1, Math.max(0, streamed - i)) }}>{w} </span>
                  ))}
                </div>
                <div style={{ display: "flex", gap: 12, marginTop: 18, opacity: interpolate(f, [244, 268], [0, 1], clamp), translate: `0 ${interpolate(f, [244, 272], [12, 0], { ...clamp, easing: OUT })}px` }}>
                  {["Copy", "Translate", "Speak", "Pin"].map((b, i) => (
                    <div key={b} style={{ padding: "10px 20px", borderRadius: 14, fontSize: 20, fontWeight: 600, color: FG, background: i === 0 ? "rgba(255,255,255,0.16)" : "rgba(255,255,255,0.07)" }}>
                      {b}
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </>
        )}

        </div>
        {/* ⇧⌘2 */}
        <div
          style={{
            position: "absolute", left: 0, right: 0, top: 946, display: "flex", justifyContent: "center", gap: 16,
            opacity: interpolate(f, [20, 38, 74, 94], [0, 1, 1, 0], clamp),
            translate: `0 ${interpolate(f, [20, 44], [30, 0], { ...clamp, easing: OUT })}px`,
          }}
        >
          {["⇧", "⌘", "2"].map((k) => (
            <div
              key={k}
              style={{
                width: 92, height: 92, borderRadius: 20, display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 42, fontWeight: 500, color: FG, background: "linear-gradient(180deg, #2e2e33, #1b1b1e)",
                boxShadow: "inset 0 1px 0 rgba(255,255,255,0.14), 0 10px 30px rgba(0,0,0,0.5)",
                scale: interpolate(f, [48, 53, 62], [1, 0.9, 1], clamp),
              }}
            >
              {k}
            </div>
          ))}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

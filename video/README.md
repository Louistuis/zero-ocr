# Zero OCR showcase video

A 10-second product video made with [Remotion](https://www.remotion.dev): 1920 × 1080, 60 fps.

```sh
npm i
npx remotion studio                                            # preview and edit
npx remotion render Showcase out/zero-ocr-showcase.mp4 --crf=14   # render
```

`src/scenes` holds the three scenes (Intro, Demo, Outro), `src/Neon.tsx` the neon rim in the app's colours.

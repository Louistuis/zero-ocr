# Zero OCR

Select anything on your Mac's screen and its text lands on your clipboard. Zero OCR reads with
[Xiaomi-OCR-0](https://huggingface.co/xiaomi-research/Xiaomi-OCR-0), a 0.8B vision model, entirely on
your Mac. Nothing is uploaded.

**[zero.lou15.com](https://zero.lou15.com)** · [Download](https://github.com/Louistuis/zero-ocr/releases/latest) · MIT

## Use it

| | |
|---|---|
| **⇧⌘2** | Drag over any text. Click instead of dragging to take a whole window. |
| **⌥⇧⌘2** | The same, as Markdown with tables and LaTeX formulas |
| **⌃⇧⌘2** | A table. It pastes as a real grid in Numbers, Excel, Pages and Notes |
| Finder | Right-click an image or PDF › Quick Actions › *Copy Text with Zero OCR* |
| Any app | Select an image › Services › *Copy Text with Zero OCR* |
| Menu bar | Formulas, the clipboard image, open a file, the last result |
| Terminal | `zocr scan.png`, `zocr -t sheet.png`, `zocr -d paper.pdf` (menu › Install Command Line Tool) |
| Shortcuts | `open "zeroocr://capture?mode=table"`, `zeroocr://clipboard`, `zeroocr://file?path=/x.png&mode=doc` |

Click the island while it shows the result to edit the text before you paste.

## Install

1. Download `Zero-OCR-1.0.0.dmg` from [Releases](https://github.com/Louistuis/zero-ocr/releases/latest) and drag the app to Applications.
2. The app is not signed with an Apple developer certificate, so the first open is blocked. Open
   System Settings › Privacy & Security and click **Open Anyway**, or run:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/Zero OCR.app"
   ```
3. On first launch it downloads the model (837 MB, once, checked against a SHA-256) and asks for
   screen recording permission, which it needs to see the area you select.

Requires an Apple Silicon Mac with macOS 14 or later.

## How it works

- The model is the [Q6_K GGUF conversion](https://huggingface.co/prithivMLmods/Xiaomi-OCR-0-GGUF) of
  Xiaomi-OCR-0, pinned to one commit and hash checked, run by a bundled `llama-server` from
  [llama.cpp](https://github.com/ggml-org/llama.cpp) (release b11753) on Metal. On our test set it reads
  the same as the full fp16 model at about 80 tokens per second on an M-series Air, three times faster.
- The server starts when you press the shortcut, so it is ready by the time you finish selecting
  (about 1.5 s from cold). It listens on a random localhost port with a random key, and stops after
  10 idle minutes (menu › Keep Model Loaded) so the model uses no memory when you are not reading.
- Captures use ScreenCaptureKit with Zero OCR's own windows excluded. Small selections are scaled up
  before reading, which matters a lot for a quantised model.
- The frame and the notch island are one Metal shader: four edges of light per pixel, coloured by 16
  stops around the perimeter and tone mapped toward white, after the Louis Studios neon frame.
- Files live in `~/Library/Application Support/Zero OCR`. Delete that folder and the app to uninstall.

## Build

Needs only the Command Line Tools (no Xcode).

```sh
./build.sh            # build/Zero OCR.app
./build.sh --install  # also copy to ~/Applications and launch
./build.sh --dmg      # build/Zero-OCR-<version>.dmg
```

`build.sh` downloads the pinned llama.cpp release and checks it against `app/llama.sha256`.

## Credits

- [Xiaomi-OCR-0](https://huggingface.co/xiaomi-research/Xiaomi-OCR-0) by Xiaomi, Apache-2.0
- [llama.cpp](https://github.com/ggml-org/llama.cpp), MIT
- GGUF conversion by [prithivMLmods](https://huggingface.co/prithivMLmods/Xiaomi-OCR-0-GGUF)

## License

MIT © 2026 Louis Nordbø. The model weights are downloaded separately and keep their own Apache-2.0 license.

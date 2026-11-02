# Zero OCR

Select anything on your Mac's screen and its text lands on your clipboard. Zero OCR reads with
[Xiaomi-OCR-0](https://huggingface.co/xiaomi-research/Xiaomi-OCR-0), a 0.8B vision model, entirely on
your Mac. Nothing is uploaded.

**[zero.lou15.com](https://zero.lou15.com)** · [Download](https://github.com/Louistuis/zero-ocr/releases/latest/download/Zero-OCR.dmg) · MIT

## Use it

Press **⇧⌘2** and drag over any text, or click to take a whole window. That is the one thing to remember.

A glass card opens in the top right corner while it reads, and the text is already on your clipboard
when it says *Copied*. Everything else is a button on that card:

- **Copy** again, **Translate** (Apple's on-device translation), **Speak**, **Pin** it to the screen as a
  floating note, or **Edit** it in History.
- **Read as** Table, Markdown or Formula to read the same image again another way.
- Smart buttons for what it found: links, email addresses, phone numbers, addresses (Maps), dates
  (adds a Calendar event) and QR codes.
- Markdown, tables and LaTeX show formatted on the card and in History, not as source.

| | |
|---|---|
| **⇧⌘2** | Read any area. Click instead of dragging to take a whole window |
| **⇧⌘1** | Read the same area again (subtitles, a dashboard, a game) |
| **⌥⇧⌘2** / **⌃⇧⌘2** | Straight to Markdown / a table that pastes as a real grid in Numbers, Excel, Pages and Notes |
| **⌘Y** in the menu | History: everything you read, searchable, editable, exportable as .md, .tsv or .txt |
| Menu bar icon | Drop an image or PDF on it. The menu also reads the clipboard image or opens a file |
| Finder | Right-click an image or PDF › Quick Actions › *Copy Text with Zero OCR*, or Open With |
| Any app | Select an image › Services › *Copy Text with Zero OCR* |
| Terminal | `zocr scan.png`, `zocr -t sheet.png`, `zocr -d paper.pdf` (Settings › Install zocr) |
| Shortcuts | `open "zeroocr://capture?mode=table"`, `zeroocr://repeat`, `zeroocr://clipboard`, `zeroocr://file?path=/x.png&mode=doc`, `zeroocr://history` |

Settings (⌘, in the menu) has the rest: the neon frame, the sound, how long the card stays, joining
lines into paragraphs, the translation language, the model's idle timeout, and history on or off.

## Install

1. Download [`Zero-OCR.dmg`](https://github.com/Louistuis/zero-ocr/releases/latest/download/Zero-OCR.dmg) and drag the app to Applications.
2. The app is not signed with an Apple developer certificate, so the first open is blocked. Open
   System Settings › Privacy & Security and click **Open Anyway**, or run:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/Zero OCR.app"
   ```
3. On first launch it downloads the model (837 MB, once, checked against a SHA-256) and asks for
   screen recording permission, which it needs to see the area you select. Updates keep the
   permission.

Requires an Apple Silicon Mac with macOS 14 or later. Liquid Glass needs macOS 26; earlier versions
get the system material, and Translate needs macOS 15.

## How it works

- The model is the [Q6_K GGUF conversion](https://huggingface.co/prithivMLmods/Xiaomi-OCR-0-GGUF) of
  Xiaomi-OCR-0, pinned to one commit and hash checked, run by a bundled `llama-server` from
  [llama.cpp](https://github.com/ggml-org/llama.cpp) (release b11753) on Metal. On our test set it reads
  the same as the full fp16 model at about 80 tokens per second on an M-series Air, three times faster.
- The server starts when you press the shortcut, so it is ready by the time you finish selecting
  (about 1.5 s from cold). It listens on a random localhost port with a random key, and stops after
  10 idle minutes so the model uses no memory when you are not reading.
- Captures use ScreenCaptureKit with Zero OCR's own windows excluded. Small selections are scaled up
  before reading, which matters a lot for a quantised model.
- The neon frame, the flight to the card and the rim around it are one Metal shader: four edges of
  light per pixel, coloured by 16 stops around the perimeter and tone mapped toward white, after the
  Louis Studios neon frame. The card is SwiftUI with `glassEffect`.
- Formatted results are rendered offline by bundled [marked](https://github.com/markedjs/marked) and
  [KaTeX](https://katex.org).
- Files live in `~/Library/Application Support/Zero OCR`, history included. Delete that folder and
  the app to uninstall.

## Build

Needs only the Command Line Tools (no Xcode).

```sh
./build.sh            # build/Zero OCR.app
./build.sh --install  # also copy to ~/Applications and launch
./build.sh --dmg      # build/Zero-OCR.dmg
```

`build.sh` downloads the pinned llama.cpp release and checks it against `app/llama.sha256`.

## Credits

- [Xiaomi-OCR-0](https://huggingface.co/xiaomi-research/Xiaomi-OCR-0) by Xiaomi, Apache-2.0
- [llama.cpp](https://github.com/ggml-org/llama.cpp), MIT
- [KaTeX](https://github.com/KaTeX/KaTeX) and [marked](https://github.com/markedjs/marked), MIT
- GGUF conversion by [prithivMLmods](https://huggingface.co/prithivMLmods/Xiaomi-OCR-0-GGUF)

## License

MIT © 2026 Louis Nordbø. The model weights are downloaded separately and keep their own Apache-2.0 license.

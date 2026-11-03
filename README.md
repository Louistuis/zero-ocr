# Zero OCR

Select anything on your Mac's screen and its text lands on your clipboard. Zero OCR reads with
[Xiaomi-OCR-0](https://huggingface.co/xiaomi-research/Xiaomi-OCR-0), a 0.8B vision model, entirely on
your Mac. Nothing is uploaded.

**[zero.lou15.com](https://zero.lou15.com)** · Download for [Apple silicon](https://github.com/Louistuis/zero-ocr/releases/latest/download/Zero-OCR.dmg) or [Intel](https://github.com/Louistuis/zero-ocr/releases/latest/download/Zero-OCR-Intel.dmg) · MIT

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

Zero OCR comes in two editions. Not sure which Mac you have? Apple menu › About This Mac shows
**Chip: Apple** or **Processor: Intel**.

| | Apple silicon | Intel |
|---|---|---|
| Download | [`Zero-OCR.dmg`](https://github.com/Louistuis/zero-ocr/releases/latest/download/Zero-OCR.dmg) | [`Zero-OCR-Intel.dmg`](https://github.com/Louistuis/zero-ocr/releases/latest/download/Zero-OCR-Intel.dmg) |
| Reads on | the GPU, with Metal | the processor |
| Model | Q6_K, 837 MB | Q4_K_M, 747 MB |
| Interface | Liquid Glass on macOS 26, the neon at full resolution, LaTeX rendered with KaTeX | the system material, the neon at 1x on the integrated GPU, Markdown and tables drawn natively, LaTeX as clean source |
| Model unloads after | 10 idle minutes | 3 idle minutes |

1. Download the edition for your Mac and drag the app to Applications.
2. The app is not signed with an Apple developer certificate, so the first open is blocked. Open
   System Settings › Privacy & Security and click **Open Anyway**, or run:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/Zero OCR.app"
   ```
3. On first launch it downloads the model (once, checked against a SHA-256) and asks for screen
   recording permission, which it needs to see the area you select. Updates keep the permission.

## System requirements

**Apple silicon edition**

| | Minimum | Recommended |
|---|---|---|
| Chip | Apple M1 | Apple M2 or later. About 80 tokens a second on an M3 MacBook Air |
| macOS | 14 Sonoma (system material instead of Liquid Glass) | 26 Tahoe for the Liquid Glass card. Translate needs 15 or later |
| Memory | 8 GB. The model uses about 1.2 GB while it reads, nothing when it sleeps | 16 GB, to keep the model loaded next to your other apps |
| Storage | 1 GB free: the app is 32 MB, the model 837 MB | 2 GB free, for the model plus a long History with images |

**Intel edition**

| | Minimum | Recommended |
|---|---|---|
| Mac | Intel, 2018 or later: MacBook Air, MacBook Pro and Mac mini from 2018, iMac and Mac Pro from 2019, and iMac Pro. The Macs that run macOS Sonoma | A quad-core Intel Core i5 or better. Reading runs on the processor, so more cores read faster |
| macOS | 14 Sonoma | 15 Sequoia or later, for Translate |
| Memory | 4 GB. The model uses about 1 GB while it reads, nothing when it sleeps | 8 GB, to keep the model loaded next to your other apps |
| Storage | 1 GB free: the app is 28 MB, the model 747 MB | 2 GB free, for the model plus a long History with images |

An internet connection is needed once, to download the model. After that it works offline.

## How it works

- The Apple silicon edition runs the [Q6_K GGUF conversion](https://huggingface.co/prithivMLmods/Xiaomi-OCR-0-GGUF) of
  Xiaomi-OCR-0, pinned to one commit and hash checked, with a bundled `llama-server` from
  [llama.cpp](https://github.com/ggml-org/llama.cpp) (release b11753) on Metal. On our test set it reads
  the same as the full fp16 model at about 80 tokens per second on an M-series Air, three times faster.
- The Intel edition runs llama.cpp's official x86-64 build of the same release on the CPU (no AVX-512,
  so every 2018 and later Intel Mac can run it) with a lighter setup we picked by measuring it: the
  [Q4_K_M GGUF](https://huggingface.co/richardyoung/Xiaomi-OCR-0-GGUF) quantised with an importance matrix, also
  pinned and hash checked, an F16 vision projector, and images capped at 1.6 megapixels instead of 4.1, which
  more than halves the work on a full page. On our test images and pages 99.8% of the characters match the
  Apple silicon edition. With less than 8 GB of memory it reads the weights straight from the file instead of
  repacking them, about 200 MB less at its peak.
- The server starts when you press the shortcut, so it is ready by the time you finish selecting
  (about 1.5 s from cold). It listens on a random localhost port with a random key, and stops after
  10 idle minutes (3 on Intel) so the model uses no memory when you are not reading.
- Captures use ScreenCaptureKit with Zero OCR's own windows excluded. Small selections are scaled up
  before reading, which matters a lot for a quantised model.
- The neon frame, the flight to the card and the rim around it are one Metal shader: four edges of
  light per pixel, coloured by 16 stops around the perimeter and tone mapped toward white, after the
  Louis Studios neon frame. The card is SwiftUI with `glassEffect`. On Intel Macs with two GPUs the
  shader runs on the integrated one at 1x, so it never wakes the discrete GPU.
- On Apple silicon, formatted results are rendered offline by bundled [marked](https://github.com/markedjs/marked)
  and [KaTeX](https://katex.org). The Intel edition draws them with SwiftUI instead, which saves the
  WebKit processes.
- Files live in `~/Library/Application Support/Zero OCR`, history included. Delete that folder and
  the app to uninstall.

## Build

Needs only the Command Line Tools (no Xcode).

```sh
./build.sh                  # build/Zero OCR.app (Apple silicon)
./build.sh --install        # also copy to ~/Applications and launch
./build.sh --dmg            # build/Zero-OCR.dmg
./build.sh --intel --dmg    # build/intel/Zero OCR.app (x86_64) and build/Zero-OCR-Intel.dmg
```

`build.sh` downloads the pinned llama.cpp release for each architecture and checks it against
`app/llama.sha256` or `app/llama-x64.sha256`. Both editions build on either kind of Mac.

## Credits

- [Xiaomi-OCR-0](https://huggingface.co/xiaomi-research/Xiaomi-OCR-0) by Xiaomi, Apache-2.0
- [llama.cpp](https://github.com/ggml-org/llama.cpp), MIT
- [KaTeX](https://github.com/KaTeX/KaTeX) and [marked](https://github.com/markedjs/marked), MIT
- GGUF conversions by [prithivMLmods](https://huggingface.co/prithivMLmods/Xiaomi-OCR-0-GGUF) (Apple silicon)
  and [richardyoung](https://huggingface.co/richardyoung/Xiaomi-OCR-0-GGUF) (Intel)

## License

MIT © 2026 Louis Nordbø. The model weights are downloaded separately and keep their own Apache-2.0 license.

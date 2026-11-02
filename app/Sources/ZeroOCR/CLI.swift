import AppKit

/// `zocr`: the same binary, run from a shell. It uses the app's running engine when there is one,
/// otherwise starts its own for the duration of the command.
enum CLI {
    static let usage = """
    usage: zocr [-t | -d | -f] [-c] [file ...]

    Reads text from images and PDFs with Xiaomi-OCR-0, on this Mac.

      zocr scan.png            plain text
      zocr -t sheet.png        table as tab-separated cells
      zocr -d paper.pdf        Markdown, with tables and LaTeX formulas
      zocr -f eq.png           a formula as LaTeX
      zocr -c receipt.jpg      also copy the result
      cat shot.png | zocr      read from standard input
    """

    static func isInvocation(_ args: [String]) -> Bool {
        guard args.count > 1 else { return false }
        let a = args[1]
        // Finder and `open` add their own flags; those are not ours.
        return !(a.hasPrefix("-psn") || a.hasPrefix("-NS") || a.hasPrefix("-Apple"))
    }

    static func run(_ args: [String]) -> Never {
        var mode = Mode.text, copy = false, files: [String] = []
        for a in args.dropFirst() {
            switch a {
            case "-t", "--table": mode = .table
            case "-d", "--doc", "--markdown": mode = .doc
            case "-f", "--formula": mode = .formula
            case "-c", "--copy": copy = true
            case "-h", "--help": print(usage); exit(0)
            case "-v", "--version":
                print("zocr \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (Xiaomi-OCR-0 Q6_K)")
                exit(0)
            default:
                if a.hasPrefix("-"), a != "-" { fail("unknown option \(a)\n\n\(usage)") }
                files.append(a)
            }
        }
        if !Store.ready { fail("the model is not downloaded yet. Open Zero OCR once to finish setup.") }
        var inputs: [(String, Data)] = []
        if files.isEmpty || files == ["-"] {
            if isatty(0) != 0 { fail(usage) }
            inputs = [("stdin", FileHandle.standardInput.readDataToEndOfFile())]
        } else {
            for f in files {
                guard let d = FileManager.default.contents(atPath: f) else { fail("cannot read \(f)") }
                inputs.append((f, d))
            }
        }

        let sem = DispatchSemaphore(value: 0)
        var output: [String] = [], failure: String?
        let server = Server.shared
        Task.detached {
            do {
                for (name, data) in inputs {
                    let pages = Imaging.pages(from: data)
                    if pages.isEmpty { throw NSError(domain: "zocr", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name) is not an image or PDF"]) }
                    let t0 = Date()
                    var parts: [String] = []
                    for img in pages {
                        guard let png = Imaging.prepare(img) else { continue }
                        let (raw, _) = try await server.read(png: png, mode: mode) { _ in }
                        parts.append(Shape.apply(raw, mode: mode).text)
                    }
                    output.append(parts.joined(separator: "\n\n"))
                    FileHandle.standardError.write(Data(String(format: "%@: %.1f s\n", name, Date().timeIntervalSince(t0)).utf8))
                }
            } catch {
                failure = error.localizedDescription
            }
            sem.signal()
        }
        sem.wait()
        if server.launchedHere { server.stop() }
        if let failure { fail(failure) }
        let text = output.joined(separator: "\n\n")
        print(text)
        if copy { Clipboard.put(text, html: nil) }
        exit(0)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("zocr: \(message)\n".utf8))
        exit(1)
    }

    /// Menu: Install Command Line Tool. A two-line launcher, so it follows the app if it moves.
    static func install() -> String {
        let script = "#!/bin/sh\nexec \"\(Bundle.main.executablePath!)\" \"$@\"\n"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path]
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in candidates where FileManager.default.isWritableFile(atPath: dir) || dir.hasPrefix(home.path) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let dest = dir + "/zocr"
            if FileManager.default.createFile(atPath: dest, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755]) {
                return path.contains(dir) || dir != candidates.last ? dest : dest + " (add \(dir) to your PATH)"
            }
        }
        return ""
    }
}

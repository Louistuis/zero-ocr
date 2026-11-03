import Foundation

/// The four ways the model can read an image.
enum Mode: String, CaseIterable {
    case text, doc, table, formula

    var title: String {
        switch self {
        case .text: "Text"
        case .doc: "Markdown"
        case .table: "Table"
        case .formula: "Formula"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.viewfinder"
        case .doc: "doc.richtext"
        case .table: "tablecells"
        case .formula: "function"
        }
    }

    /// The prompts Xiaomi-OCR-0 was trained on (from its model card).
    var prompt: String {
        switch self {
        case .text: "Extract the text in the image."
        case .table: "Parse the table in the image into OTSL."
        case .formula: "Identify the formula in the image and represent it using LATEX format."
        case .doc:
            "Extract all information from the main body of the document image and represent it in markdown format, "
                + "ignoring headers and footers. Tables should be expressed in OTSL format, formulas in the document "
                + "should be represented using LATEX format, and the parsing should be organized according to the reading order."
        }
    }

    var maxTokens: Int { self == .formula ? 1024 : self == .doc ? 8192 : 4096 }
}

/// Where everything lives and what gets downloaded on first run.
enum Store {
    static let dir: URL = {
        // ZEROOCR_HOME points a test run elsewhere, so it never touches the real model, History or server.
        let d = ProcessInfo.processInfo.environment["ZEROOCR_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zero OCR", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    struct File {
        let name: String
        let bytes: Int64
        let sha256: String
        var url: URL { Store.dir.appendingPathComponent(name) }
        var remote: URL {
            URL(string: "https://huggingface.co/\(Store.repo)/resolve/\(Store.revision)/\(name)")!
        }
    }

    // GGUF conversions of xiaomi-research/Xiaomi-OCR-0 (Apache-2.0), each pinned to one commit and checked by hash.
    #if arch(x86_64)
    /// Intel: Q4_K_M, quantised with an importance matrix, reads the same as Q6_K on our test images and
    /// generates faster on a CPU. The projector is F16, which Intel CPUs convert in hardware (they have no
    /// fast bf16). Same model: the repo credits SeerRay-Lab, xiaomi-research's earlier name.
    static let repo = "richardyoung/Xiaomi-OCR-0-GGUF"
    static let revision = "a0cb6d2813d1bf778f06d22bb7a78e35bc4287b8"
    static let model = File(name: "Xiaomi-OCR-0-Q4_K_M.gguf", bytes: 541_904_320,
                            sha256: "70256e1482297608b25a79dbd43db794e75d38b4999b65fc4b75f9c66e348e1f")
    static let projector = File(name: "mmproj-Xiaomi-OCR-0-F16.gguf", bytes: 204_987_264,
                                sha256: "cd6a69a6fd4c36dbc5ca56bd1a5b9cfca3deb2043e645e95b8491e2fc0f29659")
    #else
    /// Apple silicon: Q6_K reads the same as the full fp16 model on our test set at three times the speed.
    static let repo = "prithivMLmods/Xiaomi-OCR-0-GGUF"
    static let revision = "7bbfa072e0f3d70ac722e26fbccef5b9f64b7121"
    static let model = File(name: "Xiaomi-OCR-0.Q6_K.gguf", bytes: 629_744_384,
                            sha256: "6da9896bd738852ec01d463612e463656f43b68e6cfbe09d3b0a3ed6f4ad9fd3")
    static let projector = File(name: "Xiaomi-OCR-0.mmproj-bf16.gguf", bytes: 207_346_624,
                                sha256: "634d6bc95781ebf4a3f06570a59859fa5082d488db540fd474bc6b4061aec90e")
    #endif
    static let files = [model, projector]
    static var downloadMB: Int { Int((Double(files.reduce(0) { $0 + $1.bytes }) / 1e6).rounded()) }

    static var ready: Bool {
        files.allSatisfy { f in
            ((try? FileManager.default.attributesOfItem(atPath: f.url.path)[.size]) as? Int64) == f.bytes
        }
    }

    static let serverState = dir.appendingPathComponent("server.json")
    static let serverLog = dir.appendingPathComponent("server.log")
}

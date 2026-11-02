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
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
            URL(string: "https://huggingface.co/prithivMLmods/Xiaomi-OCR-0-GGUF/resolve/\(Store.revision)/\(name)")!
        }
    }

    /// GGUF conversion of xiaomi-research/Xiaomi-OCR-0 (Apache-2.0), pinned to one commit and checked by hash.
    /// Q6_K reads the same as the full fp16 model on our test set at three times the speed.
    static let revision = "7bbfa072e0f3d70ac722e26fbccef5b9f64b7121"
    static let model = File(name: "Xiaomi-OCR-0.Q6_K.gguf", bytes: 629_744_384,
                            sha256: "6da9896bd738852ec01d463612e463656f43b68e6cfbe09d3b0a3ed6f4ad9fd3")
    static let projector = File(name: "Xiaomi-OCR-0.mmproj-bf16.gguf", bytes: 207_346_624,
                                sha256: "634d6bc95781ebf4a3f06570a59859fa5082d488db540fd474bc6b4061aec90e")
    static let files = [model, projector]

    static var ready: Bool {
        files.allSatisfy { f in
            ((try? FileManager.default.attributesOfItem(atPath: f.url.path)[.size]) as? Int64) == f.bytes
        }
    }

    static let serverState = dir.appendingPathComponent("server.json")
    static let serverLog = dir.appendingPathComponent("server.log")
}

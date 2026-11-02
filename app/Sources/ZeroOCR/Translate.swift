import SwiftUI
import Translation

/// On-device translation (Apple's Translation framework, macOS 15+) into the language set in Settings.
/// The first use of a language pair asks to download it once.
struct TranslationPane: View {
    let text: String
    @AppStorage(Prefs.Key.translateTo) private var target = "en"

    var body: some View {
        if #available(macOS 15.0, *) {
            Translated(text: text, target: target)
        } else {
            Text("Translation needs macOS 15 or later.").foregroundStyle(.secondary).padding()
        }
    }
}

@available(macOS 15.0, *)
private struct Translated: View {
    let text: String
    let target: String
    @State private var result = ""
    @State private var failed: String?
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Label("Translation · \(Locale.current.localizedString(forLanguageCode: target) ?? target)", systemImage: "translate")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !result.isEmpty {
                    Button("Copy") { Clipboard.put(result, html: nil); Sound.play("Pop") }.controlSize(.small)
                }
            }
            ScrollView {
                Group {
                    if let failed { Text(failed).foregroundStyle(.secondary) }
                    else if result.isEmpty { ProgressView().controlSize(.small) }
                    else { Text(result).textSelection(.enabled) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .onAppear { config = .init(target: Locale.Language(identifier: target)) }
        .onChange(of: text) { _, _ in config?.invalidate() }
        .translationTask(config) { session in
            do {
                result = try await session.translate(text).targetText
                failed = nil
            } catch {
                failed = "Couldn't translate: \(error.localizedDescription)"
            }
        }
    }
}

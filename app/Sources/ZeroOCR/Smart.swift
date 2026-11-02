import AppKit
import AVFoundation
import CoreImage
import NaturalLanguage

/// Things in the text worth one click: links, emails, phone numbers, dates, addresses, and QR codes in the image.
struct SmartAction: Identifiable, Hashable {
    enum Kind: Hashable { case link, email, phone, date, address, qr }
    let id = UUID()
    let kind: Kind
    let label: String
    let value: String
    var date: Date?

    var symbol: String {
        switch kind {
        case .link: "safari"
        case .email: "envelope"
        case .phone: "phone"
        case .date: "calendar.badge.plus"
        case .address: "map"
        case .qr: "qrcode"
        }
    }

    func perform() {
        switch kind {
        case .link, .qr:
            if let u = URL(string: value), u.scheme != nil { NSWorkspace.shared.open(u) } else { Clipboard.put(value, html: nil) }
        case .email: NSWorkspace.shared.open(URL(string: "mailto:\(value)")!)
        case .phone:
            let digits = value.filter { "+0123456789".contains($0) }
            NSWorkspace.shared.open(URL(string: "tel:\(digits)")!)
        case .address:
            let q = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            NSWorkspace.shared.open(URL(string: "maps://?q=\(q)")!)
        case .date: Smart.addToCalendar(title: label, date: date ?? Date())
        }
    }
}

enum Smart {
    static func actions(in text: String, image: CGImage?) -> [SmartAction] {
        var out: [SmartAction] = []
        if let image { out += qr(image).map { SmartAction(kind: .qr, label: short($0), value: $0) } }
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .date, .address]
        guard let det = try? NSDataDetector(types: types.rawValue) else { return out }
        var seen = Set(out.map(\.value))
        for m in det.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            let s = String(text[r])
            var a: SmartAction?
            switch m.resultType {
            case .link:
                if let u = m.url {
                    a = u.scheme == "mailto" ? SmartAction(kind: .email, label: u.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
                                                          value: u.absoluteString.replacingOccurrences(of: "mailto:", with: ""))
                        : SmartAction(kind: .link, label: short(s), value: u.absoluteString)
                }
            case .phoneNumber: a = SmartAction(kind: .phone, label: s, value: m.phoneNumber ?? s)
            case .date:
                // Bare years and times read as dates too often to be worth a button.
                if s.count >= 6, s.rangeOfCharacter(from: .letters) != nil || s.contains("-") || s.contains(".") || s.contains("/") {
                    a = SmartAction(kind: .date, label: s, value: s, date: m.date)
                }
            case .address: a = SmartAction(kind: .address, label: short(s), value: s)
            default: break
            }
            if let a, !seen.contains(a.value) { seen.insert(a.value); out.append(a) }
            if out.count >= 6 { break }
        }
        return out
    }

    private static func short(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        return t.count > 30 ? String(t.prefix(29)) + "…" : t
    }

    static func qr(_ image: CGImage) -> [String] {
        let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (det?.features(in: CIImage(cgImage: image)) ?? []).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    /// An .ics file opened in Calendar shows its own "add event" sheet, no calendar permission needed.
    static func addToCalendar(title: String, date: Date) {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        let start = f.string(from: date), end = f.string(from: date.addingTimeInterval(3600))
        let ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Zero OCR//EN\r\nBEGIN:VEVENT\r\nUID:\(UUID().uuidString)\r\n"
            + "DTSTAMP:\(f.string(from: Date()))Z\r\nDTSTART:\(start)Z\r\nDTEND:\(end)Z\r\nSUMMARY:\(title)\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Zero OCR event.ics")
        try? ics.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }

    /// Lines that belong to one paragraph joined back together, with hyphenated breaks mended.
    static func joinLines(_ s: String) -> String {
        s.components(separatedBy: "\n\n").map { para in
            para.replacingOccurrences(of: "(\\w)-\\n(\\w)", with: "$1$2", options: .regularExpression)
                .replacingOccurrences(of: "\\s*\\n\\s*", with: " ", options: .regularExpression)
        }.joined(separator: "\n\n")
    }
}

/// Reads text aloud in its own language.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()

    var speaking: Bool { synth.isSpeaking }

    func toggle(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate); return }
        let u = AVSpeechUtterance(string: text)
        if let lang = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue {
            u.voice = AVSpeechSynthesisVoice(language: lang)
        }
        synth.speak(u)
    }
}

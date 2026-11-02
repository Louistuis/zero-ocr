import Foundation
import SwiftUI

/// Every user setting, in one place. SwiftUI views bind to these through @AppStorage with the same keys.
enum Prefs {
    enum Key {
        static let keepLoaded = "keepLoaded"
        static let history = "historyEnabled"
        static let sounds = "sounds"
        static let joinLines = "joinLines"
        static let toastSeconds = "toastSeconds"
        static let translateTo = "translateTo"
        static let neon = "neonFrame"
        static let finderMode = "finderMode"
    }

    static let defaults: [String: Any] = [
        Key.keepLoaded: 600.0, Key.history: true, Key.sounds: true, Key.joinLines: false,
        Key.toastSeconds: 4.0, Key.translateTo: Locale.current.language.languageCode?.identifier ?? "en",
        Key.neon: true, Key.finderMode: Mode.text.rawValue,
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }

    static var history: Bool { UserDefaults.standard.bool(forKey: Key.history) }
    static var sounds: Bool { UserDefaults.standard.bool(forKey: Key.sounds) }
    static var joinLines: Bool { UserDefaults.standard.bool(forKey: Key.joinLines) }
    static var neon: Bool { UserDefaults.standard.bool(forKey: Key.neon) }
    static var toastSeconds: Double { UserDefaults.standard.double(forKey: Key.toastSeconds) }
    static var translateTo: String { UserDefaults.standard.string(forKey: Key.translateTo) ?? "en" }
    static var finderMode: Mode { Mode(rawValue: UserDefaults.standard.string(forKey: Key.finderMode) ?? "") ?? .text }
}

enum Sound {
    static func play(_ name: String) {
        guard Prefs.sounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

import Foundation

/// The menu supports the same bounded language choices as potatoken hub.
/// This stays in Swift rather than `.strings` resources because the release
/// script assembles the app bundle directly from the compiled executable.
enum L {
    enum Language: String, CaseIterable, Sendable {
        case system
        case korean
        case english
        case japanese
        case chinese
    }

    private static let preferenceKey = "PotatusHub.languagePreference"

    static var languagePreference: Language {
        get {
            UserDefaults.standard.string(forKey: preferenceKey)
                .flatMap(Language.init(rawValue:)) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey) }
    }

    static var resolved: Language {
        let preference = languagePreference
        guard preference == .system else { return preference }

        let code = Locale.preferredLanguages.first ?? ""
        if code.hasPrefix("ko") { return .korean }
        if code.hasPrefix("ja") { return .japanese }
        if code.hasPrefix("zh") { return .chinese }
        return .english
    }

    static func t(ko: String, en: String, ja: String, zh: String) -> String {
        switch resolved {
        case .korean: return ko
        case .english, .system: return en
        case .japanese: return ja
        case .chinese: return zh
        }
    }
}

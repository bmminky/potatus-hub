import Foundation

/// A saved module group: which modules, how they are arranged, and the
/// window frame. The JSON shape is what is already on users' disks.
struct SavedGroup: Codable {
    let kinds: [MetricKind]
    let axis: ModuleAxis
    let layout: ModuleLayout?
    let frame: String
}

/// Every persisted setting. The only place that touches `UserDefaults`.
/// Key names and formats are fixed: they must keep reading what earlier
/// versions saved.
final class AppSettings {
    static let shared = AppSettings()

    private static let visibilityPrefix = "PotatusHub.visible."
    private static let legacyFramePrefix = "PotatusHub.frame."
    private static let groupsKey = "PotatusHub.groups.v1"
    private static let savedShadowMarginKey = "PotatusHub.savedShadowMargin"
    private static let languageKey = "PotatusHub.languagePreference"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Module on/off (default on)

    func isVisible(_ kind: MetricKind) -> Bool {
        let key = Self.visibilityPrefix + kind.rawValue
        if defaults.object(forKey: key) == nil { return true }
        return defaults.bool(forKey: key)
    }

    func setVisible(_ visible: Bool, kind: MetricKind) {
        defaults.set(visible, forKey: Self.visibilityPrefix + kind.rawValue)
    }

    // MARK: Language

    var language: L.Language {
        get { defaults.string(forKey: Self.languageKey).flatMap(L.Language.init(rawValue:)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Self.languageKey) }
    }

    // MARK: Module positions

    /// nil when nothing is saved or the data cannot be decoded.
    func loadGroups() -> [SavedGroup]? {
        guard let data = defaults.data(forKey: Self.groupsKey) else { return nil }
        return try? JSONDecoder().decode([SavedGroup].self, from: data)
    }

    /// Saves the groups together with the shadow margin their frames used.
    /// Writes nothing if encoding fails.
    func saveGroups(_ groups: [SavedGroup], shadowMargin: CGFloat) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        defaults.set(data, forKey: Self.groupsKey)
        defaults.set(Double(shadowMargin), forKey: Self.savedShadowMarginKey)
    }

    /// Frames saved before the shadow margin existed used 14pt padding.
    var savedShadowMargin: CGFloat {
        defaults.object(forKey: Self.savedShadowMarginKey).flatMap { $0 as? CGFloat } ?? 14
    }

    /// Position saved by very old versions, one key per module.
    func legacyFrame(for kind: MetricKind) -> NSRect? {
        defaults.string(forKey: Self.legacyFramePrefix + kind.rawValue).map(NSRectFromString)
    }
}

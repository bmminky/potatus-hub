import SwiftUI

enum MetricKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case ram
    case cpu
    case gpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ram: return "RAM"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        }
    }

    var symbol: String {
        switch self {
        case .ram: return "memorychip"
        case .cpu: return "cpu"
        case .gpu: return "rectangle.3.group"
        }
    }

    var accent: Color {
        switch self {
        // Shared with potatoken hub's restrained dark-panel palette.
        case .ram: return Color(red: 0.74, green: 0.74, blue: 0.77) // #BDBDC4
        case .cpu: return Color(red: 0.96, green: 0.86, blue: 0.55) // #F5DB8C
        case .gpu: return Color(red: 0.85, green: 0.47, blue: 0.34) // #D97757
        }
    }
}

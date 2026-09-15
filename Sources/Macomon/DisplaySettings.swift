import Foundation

enum PetLocation: String, CaseIterable {
    case menuBar
    case notch
    case desktop
    case activeWindow
    case free
}

enum PetSizePreset: String, CaseIterable {
    case small
    case medium
    case large
    case extraLarge

    var dimension: CGFloat {
        switch self {
        case .small: return 24
        case .medium: return 32
        case .large: return 48
        case .extraLarge: return 64
        }
    }
}

enum PetMovementSpeed: String, CaseIterable {
    case relaxed
    case normal
    case fast

    var multiplier: CGFloat {
        switch self {
        case .relaxed: return 0.65
        case .normal: return 1
        case .fast: return 1.55
        }
    }
}

enum PetTravelRange: String, CaseIterable {
    case short
    case medium
    case long

    var overlayDistance: CGFloat {
        switch self {
        case .short: return 160
        case .medium: return 300
        case .long: return 520
        }
    }

    var statusItemDistance: CGFloat {
        switch self {
        case .short: return 24
        case .medium: return 40
        case .long: return 64
        }
    }
}

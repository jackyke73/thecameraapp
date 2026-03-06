import SwiftUI

// MARK: - Obsidian/Linear Theme System

struct Theme {
    // MARK: Colors
    static let bgPrimary = Color(hex: "080808") // Deepest black, not pure
    static let bgSecondary = Color(hex: "121212") // Panel background
    static let bgTertiary = Color(hex: "1C1C1C") // Hover/Input background
    
    static let borderSubtle = Color(hex: "2A2A2A")
    static let borderFocus = Color(hex: "404040")
    
    static let textPrimary = Color(hex: "EEEEEE")
    static let textSecondary = Color(hex: "999999")
    static let textTertiary = Color(hex: "666666")
    
    static let accent = Color(hex: "FFFFFF") // Stark white for active states
    static let accentDestructive = Color(hex: "FF453A")
    static let accentSuccess = Color(hex: "32D74B")
    static let accentWarning = Color(hex: "FFD60A")
    static let accentInfo = Color(hex: "64D2FF") // Cyan-ish for tech feel

    // MARK: Layout
    static let cornerRadius: CGFloat = 12
    static let padding: CGFloat = 16
    
    // MARK: Gradients
    static let glassGradient = LinearGradient(
        colors: [Color.black.opacity(0.8), Color.black.opacity(0.6)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View Modifiers

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerRadius
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.4)) // Darken the blur
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.borderSubtle, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func glassPanel() -> some View {
        modifier(GlassPanel())
    }
}

// MARK: - Hex Color Helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

import SwiftUI

struct Theme {
    static let background      = Color(hex: "#070B1A")
    static let surface         = Color(hex: "#0F1429")
    static let surfaceElevated = Color(hex: "#1A2040")
    static let primary         = Color(hex: "#00D4FF")
    static let primaryDark     = Color(hex: "#0099CC")
    static let primaryLight    = Color(hex: "#66E5FF")
    static let textPrimary     = Color.white
    static let textSecondary   = Color(hex: "#8896B3")
    static let online          = Color(hex: "#00E676")
    static let offline         = Color(hex: "#546E7A")
    static let bubbleMine      = Color(hex: "#0099CC")
    static let bubbleOther     = Color(hex: "#1A2040")
    static let accent          = Color(hex: "#6C63FF")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Liquid Glass Modifier
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var opacity: Double = 0.08

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(opacity))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
                }
            )
            .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20, opacity: Double = 0.08) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}

// MARK: - Campo testo Nickord
struct NickordSecureTextField: View {
    var placeholder: String
    @Binding var text: String
    var icon: String
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.primary)
                .frame(width: 20)
            if isSecure {
                SecureField(placeholder, text: $text)
                    .foregroundColor(.white)
            } else {
                TextField(placeholder, text: $text)
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .padding()
        .glassCard(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.primary.opacity(0.25), lineWidth: 1)
        )
    }
}

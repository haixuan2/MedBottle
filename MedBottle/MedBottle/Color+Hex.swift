import SwiftUI

enum AppTheme {
    static let accent = Color.adaptive(
        light: UIColor(red: 0.10, green: 0.42, blue: 0.38, alpha: 1),
        dark: UIColor(red: 0.36, green: 0.78, blue: 0.70, alpha: 1)
    )
    static let primaryText = Color.adaptive(
        light: UIColor(red: 0.10, green: 0.16, blue: 0.15, alpha: 1),
        dark: UIColor(red: 0.91, green: 0.96, blue: 0.94, alpha: 1)
    )
    static let secondaryText = Color.adaptive(
        light: UIColor(red: 0.39, green: 0.46, blue: 0.44, alpha: 1),
        dark: UIColor(red: 0.68, green: 0.76, blue: 0.73, alpha: 1)
    )
    static let tertiaryText = Color.adaptive(
        light: UIColor(red: 0.52, green: 0.58, blue: 0.56, alpha: 1),
        dark: UIColor(red: 0.50, green: 0.59, blue: 0.56, alpha: 1)
    )
    static let backgroundTop = Color.adaptive(
        light: UIColor(red: 0.96, green: 0.98, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.06, green: 0.09, blue: 0.085, alpha: 1)
    )
    static let backgroundBottom = Color.adaptive(
        light: UIColor(red: 0.86, green: 0.91, blue: 0.90, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.15, blue: 0.14, alpha: 1)
    )
    static let surface = Color.adaptive(
        light: UIColor.white.withAlphaComponent(0.72),
        dark: UIColor(red: 0.13, green: 0.18, blue: 0.17, alpha: 0.88)
    )
    static let surfaceStrong = Color.adaptive(
        light: UIColor.white.withAlphaComponent(0.88),
        dark: UIColor(red: 0.16, green: 0.22, blue: 0.21, alpha: 0.94)
    )
    static let surfaceSubtle = Color.adaptive(
        light: UIColor.white.withAlphaComponent(0.52),
        dark: UIColor(red: 0.10, green: 0.14, blue: 0.13, alpha: 0.74)
    )
    static let controlSurface = Color.adaptive(
        light: UIColor.white.withAlphaComponent(0.86),
        dark: UIColor(red: 0.17, green: 0.24, blue: 0.22, alpha: 0.96)
    )
    static let separator = Color.adaptive(
        light: UIColor(red: 0.10, green: 0.42, blue: 0.38, alpha: 0.18),
        dark: UIColor(red: 0.55, green: 0.88, blue: 0.80, alpha: 0.20)
    )
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let red = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >> 8) & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String {
        UIColor(self).hexString
    }

    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return String(
            format: "%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}

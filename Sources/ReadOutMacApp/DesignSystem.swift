import SwiftUI

enum DesignSystem {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 20
    }

    enum CornerRadius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 20
    }

    enum Opacity {
        static let faint: Double = 0.08
        static let subtle: Double = 0.15
        static let medium: Double = 0.5
        static let strong: Double = 0.82
        static let full: Double = 0.9
    }
}

import Foundation
import GlazeCore

/// The paper a book is printed on.
///
/// Only reflowable text gets a choice: a comic's page and a PDF's page carry their
/// own background, and repainting those would be vandalism rather than a setting.
public enum ReadingTheme: String, CaseIterable, Sendable {
    /// Matches the rest of the app, and the one people read in bed.
    case dark
    /// Warm and low-contrast — what a paperback looks like under a lamp.
    case sepia
    case light

    public var localizedName: String {
        switch self {
        case .dark: L10n.string("book.theme.dark")
        case .sepia: L10n.string("book.theme.sepia")
        case .light: L10n.string("book.theme.light")
        }
    }

    /// CSS colours, as `(background, text, link)`.
    public var colors: (background: String, text: String, link: String) {
        switch self {
        case .dark: ("#0e0e10", "#e6e2da", "#e8963d")
        case .sepia: ("#f3e9d6", "#3b3229", "#9a5a1e")
        case .light: ("#ffffff", "#1c1c1e", "#0a63c9")
        }
    }

    /// The same paper colour, for whatever holds the page. The area a scroll inset
    /// leaves above the text belongs to the page, not to the app behind it.
    public var backgroundComponents: (red: Double, green: Double, blue: Double) {
        switch self {
        case .dark: (0.055, 0.055, 0.063)
        case .sepia: (0.953, 0.914, 0.839)
        case .light: (1, 1, 1)
        }
    }
}

/// How large the text is set, as a multiple of the book's own size.
public enum ReadingFontScale {
    public static let minimum = 0.8
    public static let maximum = 2.0
    public static let step = 0.1
    public static let `default` = 1.0

    public static func clamp(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}

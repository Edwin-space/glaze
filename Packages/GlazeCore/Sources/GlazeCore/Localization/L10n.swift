import Foundation

public enum L10n {
    /// The app's supported display language, not the device's regional locale.
    public static func displayLanguageCode(for languages: [String] = Locale.preferredLanguages) -> String {
        for language in languages {
            let code = language.replacingOccurrences(of: "_", with: "-")
                .split(separator: "-").first.map(String.init)?.lowercased()
            if let code, code == "ko" || code == "en" { return code }
        }
        return "en"
    }

    public static func languageName(
        for code: String,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String? {
        guard let normalized = SubtitleLanguageCode.normalized(code) else { return nil }
        let locale = Locale(identifier: displayLanguageCode(for: preferredLanguages))
        return locale.localizedString(forLanguageCode: normalized)?.capitalized(with: locale)
    }

    public static func string(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static let localizedBundle: Bundle = {
        let languageCode = displayLanguageCode()
        if let path = Bundle.module.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        if let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        return Bundle.module
    }()

}

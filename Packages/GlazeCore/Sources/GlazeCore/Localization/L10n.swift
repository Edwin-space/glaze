import Foundation

public enum L10n {
    public static func string(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static let localizedBundle: Bundle = {
        let languageCode = preferredLanguageCode()
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

    private static func preferredLanguageCode() -> String {
        for language in Locale.preferredLanguages {
            let code = language
                .replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
                .first
                .map(String.init)?
                .lowercased()

            switch code {
            case "ko":
                return "ko"
            case "en":
                return "en"
            default:
                continue
            }
        }

        return "en"
    }
}

import Foundation

/// What has to be said about the code Glaze did not write.
///
/// This is not decoration. libVLC and FFmpeg are LGPL-2.1, and the licence requires
/// that anyone given a copy of this app is told plainly that the library is in it,
/// under which licence, and where to get its source. Shipping without that notice is
/// shipping in breach, so the list lives next to the code rather than in a document
/// somebody has to remember to update.
public struct OpenSourceNotice: Identifiable, Equatable, Sendable {
    public let name: String
    public let copyright: String
    public let license: OpenSourceLicense
    public let sourceURL: URL
    /// How Glaze uses it. The LGPL cares about the difference between a library that
    /// is loaded at runtime and one linked into the executable, so it is stated.
    public let usage: String

    public var id: String { name }

    public init(
        name: String,
        copyright: String,
        license: OpenSourceLicense,
        sourceURL: URL,
        usage: String
    ) {
        self.name = name
        self.copyright = copyright
        self.license = license
        self.sourceURL = sourceURL
        self.usage = usage
    }
}

public enum OpenSourceLicense: String, Equatable, Sendable {
    case lgpl21 = "LGPL-2.1-or-later"
    case apache2 = "Apache-2.0"
    case mit = "MIT"

    public var displayName: String { rawValue }

    public var url: URL {
        switch self {
        case .lgpl21: URL(string: "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html")!
        case .apache2: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!
        case .mit: URL(string: "https://opensource.org/license/mit")!
        }
    }

    /// The full text, for the licences that require a copy to travel with the app.
    public var bundledText: String? {
        guard self == .lgpl21,
              let url = Bundle.module.url(forResource: "LGPL-2.1", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }
}

public enum OpenSourceNotices {
    /// Everything this build of Glaze carries, in the order it matters.
    public static var all: [OpenSourceNotice] {
        playbackEngine + transcription
    }

    private static var playbackEngine: [OpenSourceNotice] {
        #if os(macOS)
        [
            OpenSourceNotice(
                name: "libVLC / libVLCcore",
                copyright: "© VideoLAN and contributors",
                license: .lgpl21,
                sourceURL: URL(string: "https://code.videolan.org/videolan/vlc")!,
                usage: L10n.string("legal.usage.libvlc_dlopen")
            ),
            OpenSourceNotice(
                name: "FFmpeg",
                copyright: "© the FFmpeg developers",
                license: .lgpl21,
                sourceURL: URL(string: "https://ffmpeg.org/download.html")!,
                usage: L10n.string("legal.usage.ffmpeg")
            )
        ]
        #else
        [
            OpenSourceNotice(
                name: "VLCKit (libVLC)",
                copyright: "© VideoLAN and contributors",
                license: .lgpl21,
                sourceURL: URL(string: "https://code.videolan.org/videolan/VLCKit")!,
                usage: L10n.string("legal.usage.vlckit_static")
            )
        ]
        #endif
    }

    /// Only the Mac transcribes, so only the Mac carries WhisperKit and what it pulls in.
    private static var transcription: [OpenSourceNotice] {
        #if os(macOS)
        [
            OpenSourceNotice(
                name: "WhisperKit",
                copyright: "© 2024 Argmax, Inc.",
                license: .mit,
                sourceURL: URL(string: "https://github.com/argmaxinc/argmax-oss-swift")!,
                usage: L10n.string("legal.usage.whisperkit")
            ),
            OpenSourceNotice(
                name: "swift-transformers",
                copyright: "© Hugging Face",
                license: .apache2,
                sourceURL: URL(string: "https://github.com/huggingface/swift-transformers")!,
                usage: L10n.string("legal.usage.support")
            ),
            OpenSourceNotice(
                name: "swift-jinja",
                copyright: "© Hugging Face",
                license: .apache2,
                sourceURL: URL(string: "https://github.com/huggingface/swift-jinja")!,
                usage: L10n.string("legal.usage.support")
            ),
            OpenSourceNotice(
                name: "yyjson",
                copyright: "© 2020 YaoYuan",
                license: .mit,
                sourceURL: URL(string: "https://github.com/ibireme/yyjson")!,
                usage: L10n.string("legal.usage.support")
            ),
            OpenSourceNotice(
                name: "swift-crypto, swift-collections, swift-argument-parser, swift-asn1",
                copyright: "© Apple Inc. and the Swift project authors",
                license: .apache2,
                sourceURL: URL(string: "https://github.com/apple/swift-crypto")!,
                usage: L10n.string("legal.usage.support")
            )
        ]
        #else
        []
        #endif
    }
}

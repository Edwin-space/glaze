import Darwin
import GlazeCore
import Foundation

enum NativeVLCError: LocalizedError {
    case runtimeMissing([URL])
    case libraryUnavailable(String)
    case symbolMissing(String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing(let candidates):
            return "Bundled VLC runtime is missing. candidates: \(candidates.map(\.path).joined(separator: ", "))"
        case .libraryUnavailable(let message):
            return message
        case .symbolMissing(let name):
            return "Missing libVLC symbol: \(name)"
        }
    }
}

@MainActor
final class NativeVLCLibrary: @unchecked Sendable {
    typealias InstanceHandle = OpaquePointer
    typealias MediaHandle = OpaquePointer
    typealias MediaPlayerHandle = OpaquePointer

    typealias NewInstance = @convention(c) (Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> InstanceHandle?
    typealias ReleaseInstance = @convention(c) (InstanceHandle?) -> Void
    typealias NewMediaPath = @convention(c) (InstanceHandle?, UnsafePointer<CChar>?) -> MediaHandle?
    typealias NewMediaLocation = @convention(c) (InstanceHandle?, UnsafePointer<CChar>?) -> MediaHandle?
    typealias ReleaseMedia = @convention(c) (MediaHandle?) -> Void
    typealias AddMediaOption = @convention(c) (MediaHandle?, UnsafePointer<CChar>?) -> Void
    typealias NewPlayer = @convention(c) (InstanceHandle?) -> MediaPlayerHandle?
    typealias NewPlayerFromMedia = @convention(c) (MediaHandle?) -> MediaPlayerHandle?
    typealias SetMedia = @convention(c) (MediaPlayerHandle?, MediaHandle?) -> Void
    typealias SetNSObject = @convention(c) (MediaPlayerHandle?, UnsafeMutableRawPointer?) -> Void
    typealias Play = @convention(c) (MediaPlayerHandle?) -> Int32
    typealias SetPause = @convention(c) (MediaPlayerHandle?, Int32) -> Void
    typealias IsPlaying = @convention(c) (MediaPlayerHandle?) -> Int32
    typealias GetState = @convention(c) (MediaPlayerHandle?) -> Int32
    typealias GetTime = @convention(c) (MediaPlayerHandle?) -> Int64
    typealias SetTime = @convention(c) (MediaPlayerHandle?, Int64) -> Int32
    typealias GetLength = @convention(c) (MediaPlayerHandle?) -> Int64
    typealias GetVolume = @convention(c) (MediaPlayerHandle?) -> Int32
    typealias SetVolume = @convention(c) (MediaPlayerHandle?, Int32) -> Int32
    typealias Stop = @convention(c) (MediaPlayerHandle?) -> Void
    typealias ReleasePlayer = @convention(c) (MediaPlayerHandle?) -> Void

    /// `libvlc_state_t` from the bundled libVLC 3.0.21. The numbering changed in
    /// libVLC 4, so this is tied to the runtime we ship in `Tools/vlc` — check it
    /// again if that is ever updated.
    enum PlayerState: Int32 {
        case nothingSpecial = 0
        case opening = 1
        case buffering = 2
        case playing = 3
        case paused = 4
        case stopped = 5
        case ended = 6
        case error = 7
    }

    private static var cachedLibrary: NativeVLCLibrary?

    static func shared() throws -> NativeVLCLibrary {
        if let cachedLibrary {
            return cachedLibrary
        }

        let library = try NativeVLCLibrary()
        cachedLibrary = library
        return library
    }

    static func prewarm() {
        guard let library = try? shared() else {
            return
        }

        _ = library.sharedPlaybackInstance()
    }

    let runtimeURL: URL
    let pluginsURL: URL
    let newInstance: NewInstance
    let releaseInstance: ReleaseInstance
    let newMediaPath: NewMediaPath
    let newMediaLocation: NewMediaLocation
    let releaseMedia: ReleaseMedia
    let addMediaOption: AddMediaOption
    let newPlayer: NewPlayer
    let newPlayerFromMedia: NewPlayerFromMedia
    let setMedia: SetMedia
    let setNSObject: SetNSObject
    let play: Play
    let setPause: SetPause
    let isPlaying: IsPlaying
    let getState: GetState
    let getTime: GetTime
    let setTime: SetTime
    let getLength: GetLength
    let getVolume: GetVolume
    let setVolume: SetVolume
    let stop: Stop
    let releasePlayer: ReleasePlayer

    private let coreHandle: UnsafeMutableRawPointer
    private let libraryHandle: UnsafeMutableRawPointer
    private var playbackInstance: InstanceHandle?

    private init() throws {
        runtimeURL = try Self.resolveRuntimeURL()
        pluginsURL = runtimeURL.appendingPathComponent("plugins")

        let libraryURL = runtimeURL.appendingPathComponent("lib/libvlc.dylib")
        let coreURL = runtimeURL.appendingPathComponent("lib/libvlccore.dylib")

        setenv("VLC_PLUGIN_PATH", pluginsURL.path, 1)
        setenv("VLC_DATA_PATH", Self.resolveDataURL(runtimeURL: runtimeURL).path, 1)

        guard let coreHandle = dlopen(coreURL.path, RTLD_NOW | RTLD_GLOBAL) else {
            throw NativeVLCError.libraryUnavailable("libvlccore.dylib is not available: \(Self.dlErrorMessage())")
        }
        self.coreHandle = coreHandle

        guard let libraryHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_GLOBAL) else {
            throw NativeVLCError.libraryUnavailable("libvlc.dylib is not available: \(Self.dlErrorMessage())")
        }
        self.libraryHandle = libraryHandle

        newInstance = try Self.loadSymbol("libvlc_new", from: libraryHandle)
        releaseInstance = try Self.loadSymbol("libvlc_release", from: libraryHandle)
        newMediaPath = try Self.loadSymbol("libvlc_media_new_path", from: libraryHandle)
        newMediaLocation = try Self.loadSymbol("libvlc_media_new_location", from: libraryHandle)
        releaseMedia = try Self.loadSymbol("libvlc_media_release", from: libraryHandle)
        addMediaOption = try Self.loadSymbol("libvlc_media_add_option", from: libraryHandle)
        newPlayer = try Self.loadSymbol("libvlc_media_player_new", from: libraryHandle)
        newPlayerFromMedia = try Self.loadSymbol("libvlc_media_player_new_from_media", from: libraryHandle)
        setMedia = try Self.loadSymbol("libvlc_media_player_set_media", from: libraryHandle)
        setNSObject = try Self.loadSymbol("libvlc_media_player_set_nsobject", from: libraryHandle)
        play = try Self.loadSymbol("libvlc_media_player_play", from: libraryHandle)
        setPause = try Self.loadSymbol("libvlc_media_player_set_pause", from: libraryHandle)
        isPlaying = try Self.loadSymbol("libvlc_media_player_is_playing", from: libraryHandle)
        getState = try Self.loadSymbol("libvlc_media_player_get_state", from: libraryHandle)
        getTime = try Self.loadSymbol("libvlc_media_player_get_time", from: libraryHandle)
        setTime = try Self.loadSymbol("libvlc_media_player_set_time", from: libraryHandle)
        getLength = try Self.loadSymbol("libvlc_media_player_get_length", from: libraryHandle)
        getVolume = try Self.loadSymbol("libvlc_audio_get_volume", from: libraryHandle)
        setVolume = try Self.loadSymbol("libvlc_audio_set_volume", from: libraryHandle)
        stop = try Self.loadSymbol("libvlc_media_player_stop", from: libraryHandle)
        releasePlayer = try Self.loadSymbol("libvlc_media_player_release", from: libraryHandle)
    }

    func sharedPlaybackInstance() -> InstanceHandle? {
        if let playbackInstance {
            return playbackInstance
        }

        let args = [
            "--no-video-title-show",
            "--quiet",
            "--avcodec-hw=any",
            "--no-sub-autodetect-file",
            // Instance-wide floor; each media item then sets its own from
            // `MediaCachingPolicy` once its address is known.
            "--file-caching=\(MediaCachingPolicy.localMilliseconds)",
            "--network-caching=\(MediaCachingPolicy.remoteMilliseconds)"
        ]

        let instance = args.withCStringArray { pointer in
            newInstance(Int32(args.count), pointer)
        }
        playbackInstance = instance
        return instance
    }

    private static func resolveRuntimeURL() throws -> URL {
        // Frameworks first: that is where Apple's bundle layout puts loadable code,
        // and where a shipped build stages the runtime. The rest are the paths a
        // working copy and older bundles used.
        let candidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("vlc"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/vlc"),
            Bundle.main.resourceURL?.appendingPathComponent("Tools/vlc"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Tools/vlc"),
            executableRelativeResourcesURL().appendingPathComponent("Tools/vlc"),
            sourceCheckoutRuntimeURL(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tools/vlc")
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.appendingPathComponent("lib/libvlc.dylib").path) {
            return candidate
        }

        throw NativeVLCError.runtimeMissing(candidates)
    }

    /// VLC's data files live in Resources, apart from the libraries, because
    /// everything under Frameworks must be signed and data cannot be.
    private static func resolveDataURL(runtimeURL: URL) -> URL {
        let staged = Bundle.main.resourceURL?.appendingPathComponent("vlc-share")
        if let staged, FileManager.default.fileExists(atPath: staged.path) {
            return staged
        }
        // A working copy still has them beside the runtime.
        return runtimeURL.appendingPathComponent("share")
    }

    private static func executableRelativeResourcesURL() -> URL {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        return executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    private static func sourceCheckoutRuntimeURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/vlc")
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw NativeVLCError.symbolMissing(name)
        }

        return unsafeBitCast(symbol, to: T.self)
    }

    private static func dlErrorMessage() -> String {
        guard let error = dlerror() else {
            return "unknown dyld error"
        }

        return String(cString: error)
    }
}

private extension Array where Element == String {
    func withCStringArray<Result>(_ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Result) -> Result {
        let cStrings = map { strdup($0) }
        defer {
            for pointer in cStrings {
                free(pointer)
            }
        }

        var pointers = cStrings.map { UnsafePointer<CChar>($0) }
        pointers.append(nil)
        return pointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress)
        }
    }
}

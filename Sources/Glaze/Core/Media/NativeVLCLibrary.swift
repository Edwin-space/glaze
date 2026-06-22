import Darwin
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
    typealias ReleaseMedia = @convention(c) (MediaHandle?) -> Void
    typealias NewPlayerFromMedia = @convention(c) (MediaHandle?) -> MediaPlayerHandle?
    typealias SetNSObject = @convention(c) (MediaPlayerHandle?, UnsafeMutableRawPointer?) -> Void
    typealias Play = @convention(c) (MediaPlayerHandle?) -> Int32
    typealias Stop = @convention(c) (MediaPlayerHandle?) -> Void
    typealias ReleasePlayer = @convention(c) (MediaPlayerHandle?) -> Void

    private static var cachedLibrary: NativeVLCLibrary?

    static func shared() throws -> NativeVLCLibrary {
        if let cachedLibrary {
            return cachedLibrary
        }

        let library = try NativeVLCLibrary()
        cachedLibrary = library
        return library
    }

    let runtimeURL: URL
    let pluginsURL: URL
    let newInstance: NewInstance
    let releaseInstance: ReleaseInstance
    let newMediaPath: NewMediaPath
    let releaseMedia: ReleaseMedia
    let newPlayerFromMedia: NewPlayerFromMedia
    let setNSObject: SetNSObject
    let play: Play
    let stop: Stop
    let releasePlayer: ReleasePlayer

    private let coreHandle: UnsafeMutableRawPointer
    private let libraryHandle: UnsafeMutableRawPointer

    private init() throws {
        runtimeURL = try Self.resolveRuntimeURL()
        pluginsURL = runtimeURL.appendingPathComponent("plugins")

        let libraryURL = runtimeURL.appendingPathComponent("lib/libvlc.dylib")
        let coreURL = runtimeURL.appendingPathComponent("lib/libvlccore.dylib")

        setenv("VLC_PLUGIN_PATH", pluginsURL.path, 1)
        setenv("VLC_DATA_PATH", runtimeURL.appendingPathComponent("share").path, 1)

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
        releaseMedia = try Self.loadSymbol("libvlc_media_release", from: libraryHandle)
        newPlayerFromMedia = try Self.loadSymbol("libvlc_media_player_new_from_media", from: libraryHandle)
        setNSObject = try Self.loadSymbol("libvlc_media_player_set_nsobject", from: libraryHandle)
        play = try Self.loadSymbol("libvlc_media_player_play", from: libraryHandle)
        stop = try Self.loadSymbol("libvlc_media_player_stop", from: libraryHandle)
        releasePlayer = try Self.loadSymbol("libvlc_media_player_release", from: libraryHandle)
    }

    func makeInstance() -> InstanceHandle? {
        let args = [
            "--no-video-title-show",
            "--quiet",
            "--avcodec-hw=any"
        ]

        return args.withCStringArray { pointer in
            newInstance(Int32(args.count), pointer)
        }
    }

    private static func resolveRuntimeURL() throws -> URL {
        let candidates = [
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

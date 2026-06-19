import Darwin
import Foundation

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

    static let shared = NativeVLCLibrary()

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

    private init() {
        runtimeURL = Self.resolveRuntimeURL()
        pluginsURL = runtimeURL.appendingPathComponent("plugins")

        let libraryURL = runtimeURL.appendingPathComponent("lib/libvlc.dylib")
        let coreURL = runtimeURL.appendingPathComponent("lib/libvlccore.dylib")

        setenv("VLC_PLUGIN_PATH", pluginsURL.path, 1)
        setenv("VLC_DATA_PATH", runtimeURL.appendingPathComponent("share").path, 1)

        guard let coreHandle = dlopen(coreURL.path, RTLD_NOW | RTLD_GLOBAL) else {
            fatalError("libvlccore.dylib is not available: \(Self.dlErrorMessage())")
        }
        self.coreHandle = coreHandle

        guard let libraryHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_GLOBAL) else {
            fatalError("libvlc.dylib is not available: \(Self.dlErrorMessage())")
        }
        self.libraryHandle = libraryHandle

        newInstance = Self.loadSymbol("libvlc_new", from: libraryHandle)
        releaseInstance = Self.loadSymbol("libvlc_release", from: libraryHandle)
        newMediaPath = Self.loadSymbol("libvlc_media_new_path", from: libraryHandle)
        releaseMedia = Self.loadSymbol("libvlc_media_release", from: libraryHandle)
        newPlayerFromMedia = Self.loadSymbol("libvlc_media_player_new_from_media", from: libraryHandle)
        setNSObject = Self.loadSymbol("libvlc_media_player_set_nsobject", from: libraryHandle)
        play = Self.loadSymbol("libvlc_media_player_play", from: libraryHandle)
        stop = Self.loadSymbol("libvlc_media_player_stop", from: libraryHandle)
        releasePlayer = Self.loadSymbol("libvlc_media_player_release", from: libraryHandle)
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

    private static func resolveRuntimeURL() -> URL {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Tools/vlc"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Tools/vlc"),
            executableRelativeResourcesURL().appendingPathComponent("Tools/vlc"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tools/vlc")
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.appendingPathComponent("lib/libvlc.dylib").path) {
            return candidate
        }

        fatalError("Bundled VLC runtime is missing. candidates: \(candidates.map(\.path).joined(separator: ", "))")
    }

    private static func executableRelativeResourcesURL() -> URL {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        return executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T {
        guard let symbol = dlsym(handle, name) else {
            fatalError("Missing libVLC symbol: \(name)")
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

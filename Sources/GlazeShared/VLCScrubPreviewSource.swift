import CoreGraphics
import Foundation
import GlazeCore
import ImageIO
import Synchronization
import UniformTypeIdentifiers
import VLCKit

/// Stills for the timeline, made by the same engine that plays the film.
///
/// VLCKit's thumbnailer opens the media on its own and takes a frame at a given time,
/// which is the only thing on the phone or the television that can do this for a
/// Matroska file or a stream from a NAS — AVFoundation cannot open either.
///
/// Shared by the phone and the television on purpose: it is the same VLCKit, the same
/// media, and the same question.
final class VLCScrubPreviewSource: ScrubPreviewSource, @unchecked Sendable {
    private let url: URL
    private let width: CGFloat
    /// The film's shape. Told to us rather than fetched: the player knows it only
    /// once the film is open, and reaching back for it from here meant hopping onto
    /// the main actor from a thread that is not on it — which trapped the process.
    private let shape = Mutex<CGSize?>(nil)

    init(url: URL, width: CGFloat = 320) {
        self.url = url
        self.width = width
    }

    /// Called from the player once the film reports its dimensions.
    func useVideoSize(_ size: CGSize?) {
        shape.withLock { $0 = size }
    }

    func frame(at time: TimeInterval) async -> Data? {
        let url = url
        let width = width
        // VLCKit scales the picture into exactly the box it is given, so a box of
        // the wrong shape squashes the film. Its default is 320×240, which turned
        // every widescreen frame into 4:3.
        let height = shape.withLock({ $0 }).map { size -> CGFloat in
            guard size.width > 0, size.height > 0 else { return width * 9 / 16 }
            return (width * size.height / size.width).rounded()
        } ?? width * 9 / 16
        return await withCheckedContinuation { continuation in
            // The thumbnailer is one-shot: its settings are read when the fetch starts
            // and ignored afterwards, so each frame gets its own. Built on the main
            // thread, which is where VLCKit expects its objects to be made; the answer
            // comes back on a thread of VLCKit's choosing.
            Task { @MainActor in
                guard let grab = ThumbnailGrab(url: url, time: time, width: width, height: height, finish: { data in
                    continuation.resume(returning: data)
                }) else {
                    continuation.resume(returning: nil)
                    return
                }
                grab.start()
            }
        }
    }
}

/// One frame, from opening the media to handing back the bytes.
///
/// Holds itself alive until the thumbnailer answers: VLCKit keeps only a weak
/// reference to its delegate, and a grab that went out of scope reported nothing.
///
/// Deliberately **not** main-actor isolated. VLCKit runs the thumbnailer on a thread
/// of its own and calls the delegate from there; declaring the callback as main-actor
/// work and then letting it arrive on that thread trapped the process outright
/// (`_dispatch_assert_queue_fail`), which is what crashed the phone the moment
/// someone dragged along the timeline. The little state there is is behind a lock.
private final class ThumbnailGrab: NSObject, VLCMediaThumbnailerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var thumbnailer: VLCMediaThumbnailer?
    private var finish: ((Data?) -> Void)?
    private var keptAlive: ThumbnailGrab?

    init?(
        url: URL,
        time: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        finish: @escaping (Data?) -> Void
    ) {
        guard let media = VLCMedia(url: url) else { return nil }
        self.finish = finish
        super.init()
        let thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumbnailer.snapshotTime = VLCTime(number: NSNumber(value: Int(time * 1_000)))
        thumbnailer.thumbnailWidth = width
        thumbnailer.thumbnailHeight = height
        // Software decoding a 4K frame on a phone is the difference between a still
        // that arrives while the thumb is still on the bar and one that never does.
        thumbnailer.hardwareDecodingEnabled = true
        self.thumbnailer = thumbnailer
    }

    func start() {
        lock.lock()
        keptAlive = self
        let thumbnailer = thumbnailer
        lock.unlock()
        thumbnailer?.fetchThumbnail()
    }

    func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        complete(with: Self.jpeg(from: thumbnail))
    }

    func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        complete(with: nil)
    }

    /// Answers once, whichever way the thumbnailer ended, and lets go of itself.
    private func complete(with data: Data?) {
        lock.lock()
        let finish = finish
        self.finish = nil
        keptAlive = nil
        lock.unlock()
        finish?(data)
    }

    private static func jpeg(from image: CGImage) -> Data? {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }
}

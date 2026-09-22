import CoreGraphics
import Foundation
import GlazeCore
import ImageIO
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
final class VLCScrubPreviewSource: ScrubPreviewSource {
    private let url: URL
    private let width: CGFloat

    init(url: URL, width: CGFloat = 320) {
        self.url = url
        self.width = width
    }

    func frame(at time: TimeInterval) async -> Data? {
        let url = url
        let width = width
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                // The thumbnailer is one-shot: its settings are read when the fetch
                // starts and ignored afterwards, so each frame gets its own.
                guard let grab = ThumbnailGrab(url: url, time: time, width: width, finish: { data in
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
/// reference to its delegate, and a grab that went out of scope reported nothing at all.
/// VLCKit calls its delegate on the thread it was started from, which is the main
/// actor here; the conformance says so rather than hopping again inside each callback.
@MainActor
private final class ThumbnailGrab: NSObject, @preconcurrency VLCMediaThumbnailerDelegate {
    private var thumbnailer: VLCMediaThumbnailer?
    private var finish: ((Data?) -> Void)?
    private var keptAlive: ThumbnailGrab?

    init?(url: URL, time: TimeInterval, width: CGFloat, finish: @escaping (Data?) -> Void) {
        guard let media = VLCMedia(url: url) else { return nil }
        self.finish = finish
        super.init()
        let thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumbnailer.snapshotTime = VLCTime(number: NSNumber(value: Int(time * 1_000)))
        thumbnailer.thumbnailWidth = width
        thumbnailer.thumbnailHeight = 0
        self.thumbnailer = thumbnailer
    }

    func start() {
        keptAlive = self
        thumbnailer?.fetchThumbnail()
    }

    func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        complete(with: Self.jpeg(from: thumbnail))
    }

    func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        complete(with: nil)
    }

    private func complete(with data: Data?) {
        guard let finish else { return }
        self.finish = nil
        finish(data)
        keptAlive = nil
    }

    private static func jpeg(from image: CGImage) -> Data? {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }
}

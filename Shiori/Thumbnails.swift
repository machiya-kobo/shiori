import Foundation
import ImageIO
import SwiftUI

/// Small images for rows: the web results' thumbnails and the media cards'
/// art. Each is downloaded once at a time (two rows asking share one
/// download), decoded off the main actor straight to the size it's drawn
/// at (a poster or a proxied photo can be thousands of pixels across), and
/// kept in memory only, by bytes, for the session. One that failed isn't
/// asked again for a couple of minutes.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()

    private let images: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        // By decoded bytes, not count: a poster and a favicon aren't alike.
        cache.totalCostLimit = 48 << 20
        return cache
    }()
    private var failedAt: [String: Date] = [:]
    private static let retryAfter: TimeInterval = 120
    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]

    /// `points`: the larger side it's drawn at; `fetch` gets the bytes.
    func image(_ address: String, points: CGFloat, fetch: @escaping @Sendable () async -> Data?) async -> PlatformImage? {
        guard !address.isEmpty else { return nil }
        // Room for a 3× screen, whatever this one is.
        let pixels = Int((points * 3).rounded(.up))
        let key = "\(pixels)|\(address)"
        if let image = images.object(forKey: key as NSString) { return image }
        if let at = failedAt[key], Date.now.timeIntervalSince(at) < Self.retryAfter { return nil }
        let task = inFlight[key] ?? Task { await Self.decode(await fetch(), maxPixels: pixels) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            images.setObject(image, forKey: key as NSString, cost: Self.cost(image))
            failedAt[key] = nil
        } else {
            if failedAt.count > 2000 { failedAt.removeAll() }
            failedAt[key] = .now
        }
        return image
    }

    /// Decoded at `maxPixels` on its longer side, never larger than the
    /// original, off the main actor.
    @concurrent
    nonisolated private static func decode(_ data: Data?, maxPixels: Int) async -> PlatformImage? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: image)
        #else
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        #endif
    }

    private static func cost(_ image: PlatformImage) -> Int {
        #if canImport(UIKit)
        let size = image.size
        return Int(size.width * image.scale * size.height * image.scale) * 4
        #else
        return Int(image.size.width * image.size.height) * 4
        #endif
    }
}

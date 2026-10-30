import Foundation
import UIKit
import ImageIO
import CryptoKit
import SwiftUI

// Decode directly to the requested pixel size; never decode the full camera image first.
enum ShiftPhotoProcessing {
    static func thumbnail(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixels),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    // Sticker/Memoji transparency must survive registration and backup.
    static func staffPortrait(_ data: Data) -> Data? {
        guard let image = thumbnail(data, maxPixels: 640), let cg = image.cgImage else { return nil }
        switch cg.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return image.pngData()
        default:
            return image.jpegData(compressionQuality: 0.8)
        }
    }
    static func jpeg(_ data: Data, maxPixels: Int, quality: CGFloat = 0.8) -> Data? {
        thumbnail(data, maxPixels: maxPixels)?.jpegData(compressionQuality: quality)
    }
}
enum ShiftPhotoCache {
    private static let cache: NSCache<NSData, UIImage> = {
        let cache = NSCache<NSData, UIImage>(); cache.countLimit = 160; cache.totalCostLimit = 32 * 1024 * 1024; return cache
    }()
    private static func key(_ data: Data, pixels: Int) -> NSData {
        var bytes = Data(SHA256.hash(data: data))
        var size = UInt32(max(1, pixels)).littleEndian
        withUnsafeBytes(of: &size) { bytes.append(contentsOf: $0) }
        return bytes as NSData
    }
    static func cached(_ data: Data, pixels: Int) -> UIImage? { cache.object(forKey: key(data, pixels: pixels)) }
    static func image(_ data: Data, pixels: Int = 1024) -> UIImage? {
        let key = key(data, pixels: pixels)
        if let image = cache.object(forKey: key) { return image }
        guard let image = ShiftPhotoProcessing.thumbnail(data, maxPixels: pixels) else { return nil }
        let cost = (image.cgImage?.bytesPerRow ?? pixels * 4) * (image.cgImage?.height ?? pixels)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}

struct AsyncStaffPortrait: View {
    let data: Data
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let current = image {
                Image(uiImage: current).resizable().scaledToFill()
            } else { Color.gray.opacity(0.12).overlay(Image(systemName: "person.fill").foregroundStyle(.secondary)) }
        }
        .task(id: data) {
            image = nil
            let bytes = data
            let decoded = await Task.detached(priority: .userInitiated) { ShiftPhotoCache.image(bytes, pixels: 128) }.value
            guard !Task.isCancelled else { return }
            image = decoded
        }
    }
}

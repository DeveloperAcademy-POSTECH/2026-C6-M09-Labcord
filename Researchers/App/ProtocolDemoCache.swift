#if DEBUG
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import LabcordiOS
import UIKit

enum ProtocolDemoCache {
    nonisolated struct Entry: Decodable, Sendable {
        let sha256: String
        let filenames: [String]
        let checkpointAsset: String
        let imageAsset: String?
        let page: Int?
    }

    private nonisolated struct Source: Sendable {
        let entry: Entry
        let checkpoint: Data
        let image: Data?
    }

    static func checkpoints(
        for inputs: [ProtocolAnalysisJobInput]
    ) async -> [(input: ProtocolAnalysisJobInput, checkpoint: Data)]? {
        guard !inputs.isEmpty,
              let data = NSDataAsset(name: "LabcordDemo-protocol-cache")?.data,
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return nil
        }
        let sources = entries.compactMap { entry -> Source? in
            guard let checkpoint = NSDataAsset(name: entry.checkpointAsset)?.data else {
                return nil
            }
            let image = entry.imageAsset.flatMap { NSDataAsset(name: $0)?.data }
            return Source(entry: entry, checkpoint: checkpoint, image: image)
        }
        let matching = Task.detached(priority: .userInitiated) {
            match(inputs, to: sources)
        }
        return await withTaskCancellationHandler {
            await matching.value
        } onCancel: {
            matching.cancel()
        }
    }

    private nonisolated static func match(
        _ inputs: [ProtocolAnalysisJobInput], to sources: [Source]
    ) -> [(input: ProtocolAnalysisJobInput, checkpoint: Data)]? {
        let photoReferences = sources.compactMap { source -> (Source, ImageSignature)? in
            guard let image = source.image, let signature = ImageSignature(image) else {
                return nil
            }
            return (source, signature)
        }
        var matches: [(ProtocolAnalysisJobInput, Source)] = []
        for input in inputs {
            guard !Task.isCancelled,
                  let data = try? Data(contentsOf: input.url, options: .mappedIfSafe),
                  let source = match(input, data: data, sources: sources, photos: photoReferences)
            else { return nil }
            matches.append((input, source))
        }

        let pages = matches.filter { $0.1.entry.page != nil }
            .sorted { ($0.1.entry.page ?? 0) < ($1.1.entry.page ?? 0) }
        var orderedPages = pages.makeIterator()
        return matches.map { match in
            let (input, source) = match.1.entry.page == nil ? match : orderedPages.next() ?? match
            return (input, source.checkpoint)
        }
    }

    private nonisolated static func match(
        _ input: ProtocolAnalysisJobInput, data: Data, sources: [Source],
        photos: [(Source, ImageSignature)]
    ) -> Source? {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let source = sources.first(where: { $0.entry.sha256 == digest }) { return source }

        if !input.isPhoto {
            let name = normalizedName(input.name)
            let matches = sources.filter { source in
                source.entry.filenames.contains { normalizedName($0) == name }
            }
            if matches.count == 1 { return matches.first }
        }

        guard !photos.isEmpty, let signature = ImageSignature(data) else { return nil }
        let matches = photos.filter { _, reference in signature.matches(reference) }
        return matches.count == 1 ? matches.first?.0 : nil
    }

    private nonisolated static func normalizedName(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }
}

private nonisolated struct ImageSignature {
    private static let side = 96
    let aspectRatio: Double
    let pixels: [UInt8]

    init?(_ data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 384
              ] as CFDictionary) else { return nil }

        let side = Self.side
        var buffer = [UInt8](repeating: 255, count: side * side)
        let drawn = buffer.withUnsafeMutableBytes { pixels in
            guard let context = CGContext(
                data: pixels.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        aspectRatio = Double(image.width) / Double(image.height)
        pixels = buffer
    }

    func matches(_ reference: ImageSignature) -> Bool {
        guard abs(aspectRatio / reference.aspectRatio - 1) < 0.015 else { return false }
        let differences = zip(pixels, reference.pixels).map { abs(Int($0) - Int($1)) }
        let meanDifference = Double(differences.reduce(0, +)) / Double(pixels.count)
        let visiblyDifferentCount = differences.filter { $0 > 24 }.count
        return meanDifference < 4 && Double(visiblyDifferentCount) / Double(pixels.count) < 0.02
    }
}
#endif

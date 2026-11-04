import Foundation
import OmniParser

nonisolated enum ProtocolDocumentTermCleaner {
    static func sourceSpans(_ document: DocumentParseResult) -> [ProtocolTermSourceSpan]? {
        var text = ""
        var blockSpans: [ProtocolTermSourceSpan] = []
        var scalarOffset = 0
        for (blockIndex, block) in document.blocks.enumerated() where !block.text.isEmpty
                && block.kind != .table && block.kind != .image {
            if !text.isEmpty { text.append("\n"); scalarOffset += 1 }
            let count = block.text.unicodeScalars.count
            blockSpans.append(.init(
                start: scalarOffset, end: scalarOffset + count, blockIndex: blockIndex))
            text.append(block.text)
            scalarOffset += count
        }
        return Array(text.unicodeScalars) == Array(document.fullText.unicodeScalars)
            ? blockSpans : nil
    }
}

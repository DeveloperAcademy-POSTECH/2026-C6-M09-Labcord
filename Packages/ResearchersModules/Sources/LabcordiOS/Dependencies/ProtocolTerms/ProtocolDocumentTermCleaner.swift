import Foundation
import OmniParser

/// fullText를 재구성해 원래 블록과 Unicode scalar 좌표가 일치하는지 확인합니다.
nonisolated enum ProtocolDocumentTermCleaner {
    static func sourceSpans(_ document: DocumentParseResult) -> [ProtocolTermSourceSpan]? {
        var text = ""
        var spans: [ProtocolTermSourceSpan] = []
        var offset = 0
        for (index, block) in document.blocks.enumerated() where !block.text.isEmpty
                && block.kind != .table && block.kind != .image {
            if !text.isEmpty { text.append("\n"); offset += 1 }
            let count = block.text.unicodeScalars.count
            spans.append(.init(start: offset, end: offset + count, blockIndex: index))
            text.append(block.text)
            offset += count
        }
        return Array(text.unicodeScalars) == Array(document.fullText.unicodeScalars) ? spans : nil
    }
}

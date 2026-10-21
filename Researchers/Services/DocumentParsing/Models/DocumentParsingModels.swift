import CoreGraphics
import Foundation
import ImageIO

nonisolated public enum DocumentInput: @unchecked Sendable {
  case url(URL)
  case data(Data, fileName: String?)
  case image(CGImage, orientation: CGImagePropertyOrientation)
}

nonisolated public enum DocumentFormat: String, Sendable, CaseIterable {
  case txt
  case csv
  case json
  case xml
  case jpeg
  case png
  case image
  case heic
  case tiff
  case pdf
  case docx
  case xlsx
  case pptx
  case hwp
  case hwpx
  case rtf
  case html
  case markdown
  case doc
  case xls
  case ppt
}

nonisolated public struct DocumentLocation: Sendable, Equatable {
  public var part: String?
  public var page: Int?
  public var row: Int?
  public var column: Int?
  public var paragraph: Int?
  public var bounds: CGRect?
  public var rowSpan: Int?
  public var columnSpan: Int?

  public init(
    part: String? = nil,
    page: Int? = nil,
    row: Int? = nil,
    column: Int? = nil,
    paragraph: Int? = nil,
    bounds: CGRect? = nil,
    rowSpan: Int? = nil,
    columnSpan: Int? = nil
  ) {
    self.part = part
    self.page = page
    self.row = row
    self.column = column
    self.paragraph = paragraph
    self.bounds = bounds
    self.rowSpan = rowSpan
    self.columnSpan = columnSpan
  }
}

nonisolated public enum DocumentBlockKind: String, Sendable {
  case paragraph
  case heading
  case table
  case tableCell
  case imageOCR
  case image
}

nonisolated public struct DocumentBlock: Sendable, Equatable {
  public var kind: DocumentBlockKind
  public var text: String
  public var readingOrder: Int
  public var location: DocumentLocation
  public var ocrConfidence: Float?
  public var ocrOriginalText: String?

  public init(
    kind: DocumentBlockKind,
    text: String,
    readingOrder: Int,
    location: DocumentLocation = DocumentLocation(),
    ocrConfidence: Float? = nil,
    ocrOriginalText: String? = nil
  ) {
    self.kind = kind
    self.text = text
    self.readingOrder = readingOrder
    self.location = location
    self.ocrConfidence = ocrConfidence
    self.ocrOriginalText = ocrOriginalText
  }
}

nonisolated public enum DocumentWarningCode: String, Sendable {
  case uncertainReadingOrder
  case extractionFailed
  case imageOCRFailed
  case resourceLimitReached
  case externalImageSkipped
  case unsupportedElement
  case malformedContent
}

nonisolated public struct DocumentWarning: Sendable, Equatable {
  public var code: DocumentWarningCode
  public var message: String
  public var location: DocumentLocation?

  public init(code: DocumentWarningCode, message: String, location: DocumentLocation? = nil) {
    self.code = code
    self.message = message
    self.location = location
  }
}

nonisolated public struct DocumentParseResult: Sendable, Equatable {
  public var format: DocumentFormat
  public var fullText: String
  public var blocks: [DocumentBlock]
  public var warnings: [DocumentWarning]
  public var images: [DocumentEmbeddedImage]
  public var metrics: DocumentParsingMetrics?

  public init(
    format: DocumentFormat,
    blocks: [DocumentBlock],
    warnings: [DocumentWarning],
    images: [DocumentEmbeddedImage] = [],
    metrics: DocumentParsingMetrics? = nil
  ) {
    self.metrics = metrics
    self.format = format
    self.blocks = blocks.enumerated().sorted {
      if $0.element.readingOrder != $1.element.readingOrder {
        return $0.element.readingOrder < $1.element.readingOrder
      }
      return $0.offset < $1.offset
    }.enumerated().map { order, entry in
      var block = entry.element
      block.readingOrder = order
      return block
    }
    self.fullText = self.blocks
      .filter {
        $0.kind == .paragraph || $0.kind == .heading || $0.kind == .tableCell
          || $0.kind == .imageOCR
      }
      .map(\.text)
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    self.warnings = warnings
    self.images = images
  }
}

nonisolated public enum DocumentParsingPhase: String, Sendable {
  case identifying
  case extracting
  case recognizingText
  case completed
  case failed
  case cancelled
}

nonisolated public struct DocumentProgress: Sendable, Equatable {
  public var inputIndex: Int
  public var phase: DocumentParsingPhase
  public var fractionCompleted: Double

  public init(inputIndex: Int, phase: DocumentParsingPhase, fractionCompleted: Double) {
    self.inputIndex = inputIndex
    self.phase = phase
    self.fractionCompleted = min(max(fractionCompleted, 0), 1)
  }
}

nonisolated public struct DocumentParserOptions: Sendable {
  public var maximumInputBytes: Int
  public var maximumExpandedBytes: Int
  public var maximumArchiveEntries: Int
  public var maximumImagePixels: Int
  public var maximumConcurrentDocuments: Int
  public var maximumDocumentPages: Int
  public var maximumEmbeddedImages: Int
  public var maximumPDFOperators: Int
  public var maximumConcurrentPDFPages: Int
  public var pdfWorkingMemoryTargetBytes: Int
  public var maximumPDFImageBytes: Int

  public init(
    maximumInputBytes: Int = 100 * 1024 * 1024,
    maximumExpandedBytes: Int = 500 * 1024 * 1024,
    maximumArchiveEntries: Int = 10_000,
    maximumImagePixels: Int = 40_000_000,
    maximumConcurrentDocuments: Int = 2,
    maximumDocumentPages: Int = 1_000,
    maximumEmbeddedImages: Int = 128,
    maximumPDFOperators: Int = 100_000,
    maximumConcurrentPDFPages: Int = ProcessInfo.processInfo.activeProcessorCount,
    pdfWorkingMemoryTargetBytes: Int = 256 * 1024 * 1024,
    maximumPDFImageBytes: Int = 500 * 1024 * 1024
  ) {
    self.maximumInputBytes = max(1, maximumInputBytes)
    self.maximumExpandedBytes = max(1, maximumExpandedBytes)
    self.maximumArchiveEntries = max(1, maximumArchiveEntries)
    self.maximumImagePixels = max(1, maximumImagePixels)
    self.maximumConcurrentDocuments = max(1, maximumConcurrentDocuments)
    self.maximumDocumentPages = max(1, maximumDocumentPages)
    self.maximumEmbeddedImages = max(1, maximumEmbeddedImages)
    self.maximumPDFOperators = max(1, maximumPDFOperators)
    self.maximumConcurrentPDFPages = max(1, maximumConcurrentPDFPages)
    self.pdfWorkingMemoryTargetBytes = max(1, pdfWorkingMemoryTargetBytes)
    self.maximumPDFImageBytes = max(1, maximumPDFImageBytes)
  }
}

nonisolated public enum DocumentParsingError: Error, Sendable, Equatable {
  case unreadableInput
  case inputTooLarge
  case encryptedDocument
  case unsupportedFormat
  case malformedDocument
  case cancelled
}

nonisolated public enum DocumentBatchResult: Sendable {
  case success(DocumentParseResult)
  case failure(DocumentParsingError)
}

import CoreGraphics
import Foundation
import ImageIO

/// 파싱할 원본 입력. URL은 로컬 파일만 받으며 네트워크 요청을 시작하지 않는다.
/// CGImage는 호출 동안 읽기 전용으로 사용해야 하며 방향을 별도로 전달한다.
nonisolated public enum DocumentInput: @unchecked Sendable {
  /// 로컬 파일 URL. 파싱 중 보안 접근을 유지하며 상대 그림 참조의 기준 디렉터리도 보존한다.
  case url(URL)
  /// 메모리 입력. fileName은 판별 힌트이며 상대 그림을 찾을 기준 디렉터리는 제공하지 않는다.
  case data(Data, fileName: String?)
  /// 디코딩된 비트맵과 실제 방향. 이미 정방향으로 회전한 픽셀이면 up을 전달한다.
  case image(CGImage, orientation: CGImagePropertyOrientation)
}

/// 실제 판별된 형식. image는 확장자가 아니라 CGImage 직접 입력을 뜻한다.
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

/// 원본에서 요소를 찾기 위한 위치. 알 수 없는 필드는 nil로 두며 페이지 좌표를 임의로 만들지 않는다.
nonisolated public struct DocumentLocation: Sendable, Equatable {
  /// 시트·슬라이드 이름, XML 경로, 바이너리 스트림 등 형식별 원본 식별자.
  public var part: String?
  /// 1부터 시작하는 페이지 번호. TIFF에서는 프레임 번호다.
  public var page: Int?
  /// 표 셀의 행 번호. 원본 셀 주소를 알 수 있을 때 1부터 시작한다.
  public var row: Int?
  /// 표 셀의 열 번호. 원본 셀 주소를 알 수 있을 때 1부터 시작한다.
  public var column: Int?
  /// 파트 안의 문단 또는 원본 텍스트 줄 번호. 1부터 시작한다.
  public var paragraph: Int?
  /// 제공 가능한 경우 좌상단 기준 0...1 위치. PDF는 회전을 반영한 MediaBox 기준이다.
  public var bounds: CGRect?
  /// 병합 셀이 차지하는 행 수. 복원할 수 없는 경우 nil이다.
  public var rowSpan: Int?
  /// 병합 셀이 차지하는 열 수. 복원할 수 없는 경우 nil이다.
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

/// 추출 요소의 역할. 표·이미지 배치 블록과 실제 텍스트 블록을 구분할 때 사용한다.
nonisolated public enum DocumentBlockKind: String, Sendable {
  case paragraph
  case heading
  /// 표 구조의 시작 또는 영역. 실제 셀 내용은 tableCell 블록에 있다.
  case table
  case tableCell
  /// 이미지나 스캔 영역에서 인식한 텍스트. fullText에도 포함된다.
  case imageOCR
  /// 그림의 배치·설명. 설명은 OCR 결과가 아니므로 fullText에 합치지 않는다.
  case image
}

/// 텍스트 또는 구조 요소 하나. OCR 위치·신뢰도는 제공 가능한 경우에만 포함한다.
nonisolated public struct DocumentBlock: Sendable, Equatable {
  public var kind: DocumentBlockKind
  /// 추출 문자열. 구조 블록은 빈 문자열일 수 있으며 image 블록은 원본 설명을 담을 수 있다.
  public var text: String
  /// 최종 결과에서 0부터 다시 부여한 읽기 순서.
  public var readingOrder: Int
  public var location: DocumentLocation
  /// Vision이 제공하는 인식 신뢰도. 일반 본문·표 등 OCR이 아닌 블록은 nil이다.
  public var ocrConfidence: Float?
  /// 숫자 OCR 보완이 적용된 경우의 원래 인식 문자열. 임의 치환 이력을 의미하지 않는다.
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

/// 결과를 버릴 정도는 아니지만 호출 측에 알려야 하는 부분 추출·자원 제한의 종류다.
nonisolated public enum DocumentWarningCode: String, Sendable {
  case uncertainReadingOrder
  case extractionFailed
  case imageOCRFailed
  case resourceLimitReached
  case externalImageSkipped
  case unsupportedElement
  case malformedContent
}

/// 부분 결과를 사용할 때 함께 확인할 경고. 경고가 있어도 읽은 본문과 다른 요소는 유효할 수 있다.
nonisolated public struct DocumentWarning: Sendable, Equatable {
  public var code: DocumentWarningCode
  public var message: String
  /// 실패·제한이 발생한 위치. 문서 전체에 대한 경고라면 nil일 수 있다.
  public var location: DocumentLocation?

  public init(code: DocumentWarningCode, message: String, location: DocumentLocation? = nil) {
    self.code = code
    self.message = message
    self.location = location
  }
}

/// 문서 하나의 파싱 결과. 초기화할 때 블록 순서와 전체 텍스트를 함께 정리한다.
nonisolated public struct DocumentParseResult: Sendable, Equatable {
  /// 확장자 힌트가 아닌 실제 판별 결과.
  public var format: DocumentFormat
  /// 초기화 때 문단·제목·셀·OCR 텍스트를 합친 값. 이후 blocks를 수정해도 자동 갱신하지 않는다.
  public var fullText: String
  /// 읽기 순서로 정리한 텍스트·구조 블록. 서로 다른 블록의 원문 위치를 함께 확인할 수 있다.
  public var blocks: [DocumentBlock]
  /// 일부 요소 누락·불확실한 순서·한도 도달 등을 알리는 경고.
  public var warnings: [DocumentWarning]
  /// 추출한 내장 그림 PNG. 직접 입력한 이미지 원본을 다시 반환하는 배열은 아니다.
  public var images: [DocumentEmbeddedImage]
  /// 현재 PDF에서만 제공하는 단계별 시간·작업 예산 수치. 다른 형식은 nil이다.
  public var metrics: DocumentParsingMetrics?

  /// 블록의 기존 순서가 같으면 입력 순서를 유지하며 정렬하고, 그 결과로 fullText를 한 번 생성한다.
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

/// 진행 이벤트의 단계. completed도 일부 요소에 대한 warnings를 포함할 수 있다.
nonisolated public enum DocumentParsingPhase: String, Sendable {
  case identifying
  case extracting
  case recognizingText
  case completed
  case failed
  case cancelled
}

/// 문서별 진행 상태. 배치에서는 inputIndex로 이벤트를 묶어서 사용한다.
nonisolated public struct DocumentProgress: Sendable, Equatable {
  /// parse는 0, parseBatch는 원본 입력 배열의 0부터 시작하는 인덱스.
  public var inputIndex: Int
  public var phase: DocumentParsingPhase
  /// 0...1 범위의 단계별 진행률. 처리한 바이트 수의 정확한 비율은 아니다.
  public var fractionCompleted: Double

  public init(inputIndex: Int, phase: DocumentParsingPhase, fractionCompleted: Double) {
    self.inputIndex = inputIndex
    self.phase = phase
    self.fractionCompleted = min(max(fractionCompleted, 0), 1)
  }
}

/// 입력·추출·병렬 작업의 제한값. 변경 후에도 프로세스 전체 메모리의 강제 상한은 아니다.
nonisolated public struct DocumentParserOptions: Sendable {
  /// 문서 하나 또는 읽으려는 그림 데이터의 바이트 한도.
  public var maximumInputBytes: Int
  /// 압축 해제·CFB 읽기와 형식별 보관 그림에 적용하는 누적 바이트 제한.
  public var maximumExpandedBytes: Int
  /// ZIP·CFB에서 검사할 항목 수 제한.
  public var maximumArchiveEntries: Int
  /// 이미지 한 프레임 또는 PDF 페이지 래스터의 픽셀 수 제한.
  public var maximumImagePixels: Int
  /// parseBatch가 동시에 시작할 문서 수. 독립 parse 호출들을 전역으로 제한하지 않는다.
  public var maximumConcurrentDocuments: Int
  /// PDF 페이지 또는 다중 프레임 이미지의 처리 개수 제한.
  public var maximumDocumentPages: Int
  /// 문서 안에서 검사·추출할 그림 개수 제한.
  public var maximumEmbeddedImages: Int
  /// PDF 페이지의 그리기 연산 검사 수 제한.
  public var maximumPDFOperators: Int
  /// PDF 진행 페이지 수의 요청 상한. 실제 상한은 CPU·페이지 수·작업 예산도 반영한다.
  public var maximumConcurrentPDFPages: Int
  /// RGBA·임시 작업 여유의 추정 예산. 결과 PNG와 프레임워크 내부 메모리는 별도로 남을 수 있다.
  public var pdfWorkingMemoryTargetBytes: Int
  /// PDF 문서별 보관 PNG 바이트 한도. 넘는 그림은 경고로 남기며 전체 페이지 OCR은 계속한다.
  public var maximumPDFImageBytes: Int

  /// 모든 제한은 최소 1로 초기화한다. 속성은 이후 변경 가능하므로 유효한 양수로 설정한다.
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

/// 문서 전체를 처리할 수 없는 오류. 복구 가능한 요소 실패는 이 오류 대신 warnings로 반환한다.
nonisolated public enum DocumentParsingError: Error, Sendable, Equatable {
  /// 파일을 열거나 원본 데이터를 읽을 수 없다.
  case unreadableInput
  /// 입력·해제 크기·픽셀 등 문서 전체 처리에 필요한 제한을 넘었다.
  case inputTooLarge
  /// 암호화·잠금된 문서이며 비밀번호 해제 기능은 제공하지 않는다.
  case encryptedDocument
  /// 지원하는 형식으로 식별할 수 없거나 로컬 파일이 아닌 URL이다.
  case unsupportedFormat
  /// 컨테이너·문서 구조가 손상되어 유효한 결과를 만들 수 없다.
  case malformedDocument
  /// 단일 문서 파싱의 취소를 나타낸다. 배치 전체는 CancellationError를 던질 수도 있다.
  case cancelled
}

/// 입력 하나의 성공 또는 실패. parseBatch의 배열 위치가 원래 입력 위치와 대응한다.
nonisolated public enum DocumentBatchResult: Sendable {
  case success(DocumentParseResult)
  case failure(DocumentParsingError)
}

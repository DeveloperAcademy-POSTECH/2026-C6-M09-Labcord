import CoreGraphics
import Foundation

/// 직렬 준비 단계에서 완성한 불변 래스터만 공유한다. PDFKit/CGPDF 객체는 넘기지 않는다.
/// CGImage는 읽기 전용이며 이 래퍼에는 CGContext·가변 픽셀 버퍼를 보관하지 않는다.
nonisolated struct DocumentPDFRaster: @unchecked Sendable {
  let image: CGImage
}

nonisolated struct DocumentPDFImageJob: Sendable {
  let raster: DocumentPDFRaster
  let location: DocumentLocation

  /// 작업은 같은 페이지 래스터의 crop에서만 생성된다. 전체 픽셀 영역이 같을 때만 재사용한다.
  func covers(_ pageRaster: DocumentPDFRaster?) -> Bool {
    guard let pageRaster else { return false }
    return location.bounds == CGRect(x: 0, y: 0, width: 1, height: 1)
      && raster.image.width == pageRaster.image.width
      && raster.image.height == pageRaster.image.height
  }
}

/// OCR 작업 하나에 필요한 래스터·그림 작업·부분 결과를 묶는다.
/// 인덱스는 0부터 시작하며, 외부에 반환하는 페이지 번호로 바꿀 때 1을 더한다.
nonisolated struct DocumentPDFPreparedPage: Sendable {
  let index: Int
  var result = DocumentPDFImageExtractor.Result()
  var raster: DocumentPDFRaster?
  var imageJobs: [DocumentPDFImageJob] = []
  var extractImages = false
  var estimatedBytes = 0
}

/// Vision 내부 메모리의 강제 상한이 아닌 작업당 보수적인 예약 여유다.
nonisolated enum DocumentPDFWorkingMemory {
  // 배치는 여러 문서의 Vision 모델·중간 버퍼가 겹친다. 단일 문서의 작업창은 유지한다.
  static var recognitionReserveBytes: Int {
    (DocumentPDFScheduling.pool == nil ? 32 : 48) * 1024 * 1024
  }
}

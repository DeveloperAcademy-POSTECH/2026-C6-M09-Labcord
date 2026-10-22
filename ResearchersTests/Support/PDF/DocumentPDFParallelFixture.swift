import Foundation
import UIKit

/// 본문·그림·스캔이 섞인 PDF를 만들어 직렬·병렬 결과와 페이지 처리 범위를 비교한다.
nonisolated enum DocumentPDFParallelFixture {
  static func make(pages: Int = 6) throws -> Data {
    guard let image = DocumentImageFixtures.textImage("한글 IMAGE 123") else {
      throw CocoaError(.coderInvalidValue)
    }
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
    return renderer.pdfData { context in
      for page in 0..<pages {
        context.beginPage()
        if page % 3 != 1 {
          ("Native Page \(page + 1)" as NSString).draw(
            at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        if page % 3 != 0 {
          UIImage(cgImage: image).draw(in: CGRect(x: 40, y: 400, width: 520, height: 104))
        }
      }
    }
  }

}

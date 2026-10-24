import CoreGraphics
import Foundation

/// PDF 연산자를 스캐너 상태 갱신에 연결한다.
/// 좌표는 현재 변환 행렬을 적용해 페이지 공간으로 모으고 클립은 사각 경계로 근사한다.
nonisolated extension DocumentPDFScanner {
  /// q/Q는 그래픽 상태 저장·복원, cm은 행렬 합성, Do는 외부 그림 또는 중첩 Form 그리기다.
  static func registerGraphics(on table: CGPDFOperatorTableRef) {
    CGPDFOperatorTableSetCallback(table, "q") { scanner, info in
      guard let state = DocumentPDFScanner.context(scanner, info) else { return }
      state.stack.append(state.graphics)
    }
    CGPDFOperatorTableSetCallback(table, "Q") { scanner, info in
      guard let state = DocumentPDFScanner.context(scanner, info) else { return }
      if let saved = state.stack.popLast() { state.graphics = saved }
    }
    CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
      guard let state = DocumentPDFScanner.context(scanner, info),
        let values = DocumentPDFScanner.numbers(scanner, count: 6)
      else { return }
      let transform = CGAffineTransform(
        a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
      state.graphics.transform = transform.concatenating(state.graphics.transform)
    }
    CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
      DocumentPDFScanner.context(scanner, info)?.drawObject(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "BI") { scanner, info in
      DocumentPDFScanner.context(scanner, info)?.appendImage(name: "inline")
    }
    for name in ["BT", "ET", "Tj", "TJ", "Tf", "Tm", "Td", "TD", "T*", "gs"] {
      CGPDFOperatorTableSetCallback(table, name) { scanner, info in
        _ = DocumentPDFScanner.context(scanner, info)
      }
    }
  }

  static func registerPaths(on table: CGPDFOperatorTableRef) {
    CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
      guard let state = DocumentPDFScanner.context(scanner, info),
        let values = DocumentPDFScanner.numbers(scanner, count: 2)
      else { return }
      state.currentPoint = CGPoint(x: values[0], y: values[1]).applying(state.graphics.transform)
      state.subpathStart = state.currentPoint
    }
    CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
      guard let state = DocumentPDFScanner.context(scanner, info),
        let values = DocumentPDFScanner.numbers(scanner, count: 2)
      else { return }
      let next = CGPoint(x: values[0], y: values[1]).applying(state.graphics.transform)
      state.path.append(DocumentPDFScanner.Segment(start: state.currentPoint, end: next))
      state.currentPoint = next
    }
    CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
      guard let state = DocumentPDFScanner.context(scanner, info),
        let values = DocumentPDFScanner.numbers(scanner, count: 4)
      else { return }
      let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
      let points = [
        CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
        CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)
      ]
      .map { $0.applying(state.graphics.transform) }
      for index in 0..<4 {
        state.path.append(
          DocumentPDFScanner.Segment(start: points[index], end: points[(index + 1) % 4]))
      }
    }
    CGPDFOperatorTableSetCallback(table, "h") { scanner, info in
      guard let state = DocumentPDFScanner.context(scanner, info) else { return }
      state.path.append(
        DocumentPDFScanner.Segment(start: state.currentPoint, end: state.subpathStart))
      state.currentPoint = state.subpathStart
    }
  }

  /// 실제로 그린 선만 표 후보로 남긴다. 클립은 경로의 사각 경계로 근사하므로 복잡한 윤곽과 다를 수 있다.
  static func registerPainting(on table: CGPDFOperatorTableRef) {
    for name in ["S", "s", "B", "B*", "b", "b*"] {
      CGPDFOperatorTableSetCallback(table, name) { scanner, info in
        guard let state = DocumentPDFScanner.context(scanner, info) else { return }
        let available = max(0, 2_000 - state.segments.count)
        state.segments.append(contentsOf: state.path.prefix(available))
        if state.path.count > available { state.limited = true }
        state.path = []
      }
    }
    for name in ["n", "f", "f*", "F"] {
      CGPDFOperatorTableSetCallback(table, name) { scanner, info in
        DocumentPDFScanner.context(scanner, info)?.path = []
      }
    }
    for name in ["W", "W*"] {
      CGPDFOperatorTableSetCallback(table, name) { scanner, info in
        guard let state = DocumentPDFScanner.context(scanner, info), let first = state.path.first
        else { return }
        let bounds = state.path.reduce(CGRect(origin: first.start, size: .zero)) {
          $0.union(CGRect(origin: $1.start, size: .zero))
            .union(CGRect(origin: $1.end, size: .zero))
        }
        state.graphics.clip = state.graphics.clip?.intersection(bounds) ?? bounds
      }
    }
  }
}

import CoreGraphics
import Foundation

nonisolated extension DocumentPDFScanner {
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

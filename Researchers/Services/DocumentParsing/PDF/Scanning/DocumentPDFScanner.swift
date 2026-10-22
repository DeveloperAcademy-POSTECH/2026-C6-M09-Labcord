import CoreGraphics
import Foundation

/// PDF 그리기 연산을 따라가 표 선분과 그림의 표시 위치를 수집한다.
/// 그래픽 상태·중첩 Form을 추적하지만 임의의 복잡한 클립 윤곽까지 복원하지는 않는다.
nonisolated final class DocumentPDFScanner {
  struct Segment {
    let start: CGPoint
    let end: CGPoint
  }

  struct Placement {
    let name: String
    let bounds: CGRect
  }

  struct GraphicsState {
    var transform = CGAffineTransform.identity
    var clip: CGRect?
  }

  let options: DocumentParserOptions
  var graphics = GraphicsState()
  var stack: [GraphicsState] = []
  var path: [Segment] = []
  var currentPoint = CGPoint.zero
  var subpathStart = CGPoint.zero
  var segments: [Segment] = []
  var images: [Placement] = []
  var visited: Set<CGPDFStreamRef> = []
  var operatorCount = 0
  var limited = false
  var malformed = false
  var depth = 0

  init(options: DocumentParserOptions) {
    self.options = options
  }

  func scan(_ page: CGPDFPage) {
    let content = CGPDFContentStreamCreateWithPage(page)
    defer { CGPDFContentStreamRelease(content) }
    scan(content)
  }

  func scan(_ content: CGPDFContentStreamRef) {
    guard let table = CGPDFOperatorTableCreate() else {
      malformed = true
      return
    }
    defer { CGPDFOperatorTableRelease(table) }
    Self.registerGraphics(on: table)
    Self.registerPaths(on: table)
    Self.registerPainting(on: table)
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    let scanner = CGPDFScannerCreate(content, table, pointer)
    defer { CGPDFScannerRelease(scanner) }
    if !CGPDFScannerScan(scanner), !limited, !Task.isCancelled { malformed = true }
  }

  /// 모든 등록 콜백에서 연산 한도와 취소를 확인한다. 한도를 넘으면 스캐너 자체를 멈춘다.
  static func context(
    _ scanner: CGPDFScannerRef,
    _ info: UnsafeMutableRawPointer?
  ) -> DocumentPDFScanner? {
    guard let info else { return nil }
    let context = Unmanaged<DocumentPDFScanner>.fromOpaque(info).takeUnretainedValue()
    context.operatorCount += 1
    guard !Task.isCancelled,
      context.operatorCount <= max(1, context.options.maximumPDFOperators)
    else {
      context.limited = !Task.isCancelled
      CGPDFScannerStop(scanner)
      return nil
    }
    return context
  }

  static func numbers(_ scanner: CGPDFScannerRef, count: Int) -> [CGFloat]? {
    var values: [CGFloat] = []
    for _ in 0..<count {
      var number: CGPDFReal = 0
      guard CGPDFScannerPopNumber(scanner, &number), number.isFinite else { return nil }
      values.append(CGFloat(number))
    }
    return values.reversed()
  }

  func appendImage(name: String) {
    guard options.extractImages || options.performOCR else { return }
    guard images.count < max(1, options.maximumEmbeddedImages) else {
      limited = true
      return
    }
    var bounds = CGRect(x: 0, y: 0, width: 1, height: 1).applying(graphics.transform)
    guard bounds.minX.isFinite, bounds.minY.isFinite,
      bounds.width.isFinite, bounds.height.isFinite
    else { malformed = true; return }
    if let clip = graphics.clip { bounds = bounds.intersection(clip) }
    if !bounds.isEmpty, !bounds.isNull {
      images.append(Placement(name: "\(name)[\(images.count)]", bounds: bounds))
    }
  }

  func drawObject(_ scanner: CGPDFScannerRef) {
    var name: UnsafePointer<CChar>?
    guard CGPDFScannerPopName(scanner, &name), let name,
      let object = CGPDFContentStreamGetResource(
        CGPDFScannerGetContentStream(scanner), "XObject", name)
    else {
      malformed = true
      return
    }
    var stream: CGPDFStreamRef?
    guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return }
    guard let dictionary = CGPDFStreamGetDictionary(stream) else {
      malformed = true
      return
    }
    var subtype: UnsafePointer<CChar>?
    guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
    switch String(cString: subtype) {
    case "Image": appendImage(name: String(cString: name))
    case "Form": scanForm(stream, parent: CGPDFScannerGetContentStream(scanner))
    default: break
    }
  }

  /// 중첩 Form의 변환·클립·경로 상태는 방문 후 복원한다. 같은 Form의 반복 배치는 각각 추적한다.
  private func scanForm(_ stream: CGPDFStreamRef, parent: CGPDFContentStreamRef) {
    guard depth < 16, visited.insert(stream).inserted else {
      limited = true
      return
    }
    let savedGraphics = graphics
    let savedStack = stack
    let savedPath = path
    let savedPoint = currentPoint
    let savedStart = subpathStart
    defer {
      graphics = savedGraphics
      stack = savedStack
      path = savedPath
      currentPoint = savedPoint
      subpathStart = savedStart
      depth -= 1
      visited.remove(stream)
    }
    depth += 1
    guard let dictionary = CGPDFStreamGetDictionary(stream) else {
      malformed = true
      return
    }
    var matrix: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(dictionary, "Matrix", &matrix), let matrix {
      var values = [CGPDFReal](repeating: 0, count: 6)
      for index in 0..<6 {
        guard CGPDFArrayGetNumber(matrix, index, &values[index]), values[index].isFinite
        else {
          malformed = true
          return
        }
      }
      let transform = CGAffineTransform(
        a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
      graphics.transform = transform.concatenating(graphics.transform)
    }
    var resources: CGPDFDictionaryRef?
    CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
    clipForm(dictionary)
    path = []
    let content = CGPDFContentStreamCreateWithStream(stream, resources ?? dictionary, parent)
    defer { CGPDFContentStreamRelease(content) }
    scan(content)
  }

  private func clipForm(_ dictionary: CGPDFDictionaryRef) {
    var box: CGPDFArrayRef?
    guard CGPDFDictionaryGetArray(dictionary, "BBox", &box), let box else {
      malformed = true
      return
    }
    var values = [CGPDFReal](repeating: 0, count: 4)
    for index in 0..<4 {
      guard CGPDFArrayGetNumber(box, index, &values[index]), values[index].isFinite else {
        malformed = true
        return
      }
    }
    let bounds = CGRect(x: values[0], y: values[1],
                        width: values[2] - values[0], height: values[3] - values[1])
      .applying(graphics.transform)
    graphics.clip = graphics.clip?.intersection(bounds) ?? bounds
  }
}

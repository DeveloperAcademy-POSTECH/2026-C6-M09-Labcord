import Foundation

/// PDF 그리기 연산을 직접 작성해 중첩 Form·변환·반복 배치를 원하는 위치에 재현한다.
nonisolated enum DocumentPDFRawFixture {
  static func nestedImages(rotation: Int = 0, repeated: Bool = false) -> Data {
    let command =
      "q 100 0 0 100 20 30 cm /Form Do Q"
      + (repeated ? " q 50 0 0 50 120 120 cm /Form Do Q" : "")
    let form = "q .5 0 0 .5 .1 .1 cm /Image Do Q"
    let objects = [
      Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
      Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
      Data(
        ("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Rotate \(rotation) "
          + "/Resources << /XObject << /Form 5 0 R >> >> /Contents 4 0 R >>").utf8),
      stream(command, dictionary: ""),
      stream(
        form,
        dictionary: "/Type /XObject /Subtype /Form /BBox [0 0 1 1] "
          + "/Matrix [1 0 0 1 .1 .2] /Resources << /XObject << /Image 6 0 R >> >>"),
      stream(
        Data(repeating: 128, count: 12),
        dictionary:
          "/Type /XObject /Subtype /Image /Width 2 /Height 2 "
          + "/ColorSpace /DeviceRGB /BitsPerComponent 8"
      )
    ]
    var output = Data("%PDF-1.7\n".utf8)
    var offsets = [0]
    for (index, object) in objects.enumerated() {
      offsets.append(output.count)
      output.append(Data("\(index + 1) 0 obj\n".utf8))
      output.append(object)
      output.append(Data("\nendobj\n".utf8))
    }
    let xref = output.count
    output.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() {
      output.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    output.append(
      Data(
        ("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\n"
          + "startxref\n\(xref)\n%%EOF").utf8))
    return output
  }

  private static func stream(_ text: String, dictionary: String) -> Data {
    stream(Data(text.utf8), dictionary: dictionary)
  }

  private static func stream(_ data: Data, dictionary: String) -> Data {
    var output = Data("<< \(dictionary) /Length \(data.count) >>\nstream\n".utf8)
    output.append(data)
    output.append(Data("\nendstream".utf8))
    return output
  }
}

import CoreGraphics
import Foundation
import ImageIO

struct Command: Decodable {
    let kind: String
    let points: [[Double]]
}
struct Symbol: Decodable {
    let name: String
    let width: Double
    let height: Double
    let opacityByte: Int
    let origin: [Double]
    let commands: [Command]
}
struct Configuration: Decodable {
    let selectedIndices: [Int]
    let symbols: [Symbol]
}
func shape(_ symbol: Symbol, scale: CGFloat) -> CGPath? {
    let path = CGMutablePath()
    for command in symbol.commands {
        let points = command.points.map { CGPoint(x: $0[0], y: $0[1]) }
        switch command.kind {
        case "M": path.move(to: points[0])
        case "L": path.addLine(to: points[0])
        case "C": path.addCurve(to: points[2], control1: points[0], control2: points[1])
        case "Z": path.closeSubpath()
        default: return nil
        }
    }
    var transform = CGAffineTransform(
        a: scale, b: 0, c: 0, d: scale,
        tx: symbol.origin[0] * scale, ty: symbol.origin[1] * scale
    )
    return path.copy(using: &transform)
}
func alpha(_ symbol: Symbol, scale: CGFloat, selected: [Int]) -> [UInt8]? {
    guard let path = shape(symbol, scale: scale) else { return nil }
    let width = Int(symbol.width * scale)
    let height = Int(symbol.height * scale)
    var alpha = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
        for column in 0..<width {
            var count = 0
            for index in selected {
                let point = CGPoint(
                    x: Double(column) + (Double(index % 8) + 0.5) / 8,
                    y: Double(row) + (Double(index / 8) + 0.5) / 8
                )
                if path.contains(point, using: .winding) { count += 1 }
            }
            alpha[row * width + column] = UInt8((symbol.opacityByte * count + 8) / 16)
        }
    }
    return alpha
}
func image(_ alpha: [UInt8], width: Int, height: Int) -> CGImage? {
    let rgba = alpha.flatMap { [$0, $0, $0, $0] }
    guard let provider = CGDataProvider(data: Data(rgba) as CFData),
          let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let input = try JSONDecoder().decode(
    Configuration.self, from: Data(contentsOf: root.appendingPathComponent("input.json"))
)
let expected = [1, 5, 11, 15, 16, 20, 26, 30, 33, 37, 43, 47, 48, 52, 58, 62]
guard input.selectedIndices == expected, input.symbols.count == 4 else {
    fatalError("fixed configuration required")
}
let began = ProcessInfo.processInfo.systemUptime
var records: [[String: Any]] = []
var contains = 0
for scale in 1...3 {
    for symbol in input.symbols {
        let start = ProcessInfo.processInfo.systemUptime
        guard start - began < 30 else { fatalError("export time limit") }
        guard let mask = alpha(symbol, scale: CGFloat(scale), selected: expected) else {
            fatalError("path")
        }
        let width = Int(symbol.width) * scale
        let height = Int(symbol.height) * scale
        let calls = width * height * 16
        contains += calls
        guard contains <= 1_515_136, let cgImage = image(mask, width: width, height: height) else {
            fatalError("image or contains limit")
        }
        let title = "Entry" + symbol.name.capitalized + "Sampled"
        let folder = root.appendingPathComponent("GeneratedAssets.xcassets/\(title).imageset")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = symbol.name + "@\(scale)x.png"
        let url = folder.appendingPathComponent(filename)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else { fatalError("PNG destination") }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("PNG finalize") }
        let prefix = symbol.name + "@\(scale)x"
        try Data(mask).write(to: root.appendingPathComponent("RawEvidence/\(prefix).a8"))
        try Data(mask.flatMap { [$0, $0, $0, $0] }).write(
            to: root.appendingPathComponent("RawEvidence/\(prefix).runtime-premultiplied.rgba")
        )
        records.append([
            "name": symbol.name, "scale": scale, "dimensionsPX": [width, height],
            "canvasSizePT": [symbol.width, symbol.height], "opacityByte": symbol.opacityByte,
            "sourceCanvasOriginInButtonPT": symbol.origin,
            "file": "GeneratedAssets.xcassets/\(title).imageset/\(filename)",
            "containsCalls": calls, "elapsedSeconds": ProcessInfo.processInfo.systemUptime - start,
            "a8File": "RawEvidence/\(prefix).a8",
            "runtimeRGBAFile": "RawEvidence/\(prefix).runtime-premultiplied.rgba"
        ])
    }
}
guard contains == 1_515_136 else { fatalError("unexpected total") }
let report: [String: Any] = [
    "execution": "dedicated iOS Simulator pure CLI; no UI", "records": records,
    "selectedMaskHex": "4411882244118822", "selectedIndices": expected,
    "containsCalls": contains, "elapsedSeconds": ProcessInfo.processInfo.systemUptime - began,
    "alphaResolve": "(opacityByte * coveredCount + 8) / 16; integer division",
    "geometryChanges": "none except fixed canvas origin and requested 1x/2x/3x scale"
]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("export-result.json"))
let elapsed = ProcessInfo.processInfo.systemUptime - began
print("exported 12 PNG, contains=\(contains), seconds=\(elapsed)")

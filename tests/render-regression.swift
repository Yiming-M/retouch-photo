import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

typealias Object = [String: Any]
struct CheckFailure: Error, CustomStringConvertible { let description: String }

func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}

let files = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let temp = files.temporaryDirectory.appendingPathComponent("retouch-photo-render-" + UUID().uuidString)
let side = 32
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
let grayBlue: [UInt8] = [72, 112, 144, 255]
let pink: [UInt8] = [180, 50, 90, 255]

func image(_ name: String, width: Int = side, pixel: (Int) -> [UInt8]) throws {
    let row = (0..<width).flatMap(pixel)
    let data = Data((0..<side).flatMap { _ in row })
    let provider = CGDataProvider(data: data as CFData)!
    let raster = CGImage(width: width, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: width * 4, space: srgb, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let destination = CGImageDestinationCreateWithURL(
        temp.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, raster, nil)
    try check(CGImageDestinationFinalize(destination), "Could not write fixture \(name)")
}

func pixels(_ name: String) throws -> [[UInt8]] {
    let url = temp.appendingPathComponent(name + ".png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let raster = CGImageSourceCreateImageAtIndex(source, 0, nil),
          raster.width == side, raster.height == side else {
        throw CheckFailure(description: "Missing or invalid image: \(name)")
    }
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: side * 4, space: srgb, bitmapInfo: bitmapInfo)!
    context.setBlendMode(.copy)
    context.draw(raster, in: CGRect(x: 0, y: 0, width: side, height: side))
    let bytes = context.data!.bindMemory(to: UInt8.self, capacity: side * side * 4)
    return (0..<(side * side)).map { Array(UnsafeBufferPointer(start: bytes + $0 * 4, count: 4)) }
}

func recipe(_ command: String, _ name: String, _ fields: Object, rejecting field: String? = nil) throws {
    var spec = fields
    spec["output"] = name + ".png"
    if command == "render" {
        spec["version"] = 1
        spec["source"] = fields["source"] ?? "source.png"
    }
    let json = temp.appendingPathComponent(name + ".json")
    try JSONSerialization.data(withJSONObject: spec).write(to: json)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [root.appendingPathComponent("skills/retouch-photo/scripts/photo.sh").path, command, json.path]
    let log = Pipe()
    process.standardOutput = log
    process.standardError = log
    try process.run()
    let output = String(decoding: log.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()

    let imageExists = files.fileExists(atPath: temp.appendingPathComponent(name + ".png").path)
    let receiptExists = files.fileExists(atPath: temp.appendingPathComponent(name + ".png.render.json").path)
    if let field {
        try check(process.terminationStatus != 0 && !imageExists && !receiptExists
                  && output.contains("Expected nonempty string: " + field),
                  "\(name) should reject \(field) before output. \(output)")
    } else {
        try check(process.terminationStatus == 0 && imageExists && (command != "render" || receiptExists),
                  "\(name) failed. \(output)")
    }
}

func close(_ pixel: [UInt8], to expected: [UInt8]) -> Bool {
    pixel[3] == expected[3] && zip(pixel.prefix(3), expected.prefix(3)).allSatisfy {
        abs(Int($0) - Int($1)) <= 1
    }
}

func run() throws {
    try image("source.png") { _ in grayBlue }
    try image("transparent.png") { $0 < side / 2 ? [0, 0, 0, 0] : grayBlue }
    try image("patch.png", width: side / 2) { _ in pink }
    let full = "full.png"
    let protected = "protect.png"
    let left = "left.png"
    let feather = "feather.png"
    func mask(_ name: String, from: Int, to: Int, feather: Int = 0) throws {
        let points = [[from, 0], [to, 0], [to, side], [from, side]]
        try recipe("mask", name, ["width": side, "height": side, "polygons": [["points": points]], "feather": feather])
    }
    try mask("full", from: 0, to: side)
    try mask("protect", from: 4, to: 10)
    try mask("left", from: 0, to: side / 2)
    try mask("feather", from: 0, to: side / 2, feather: 3)
    let blur: [Object] = [["name": "CIGaussianBlur", "params": ["inputRadius": 3]]]
    let exposure: [Object] = [["name": "CIExposureAdjust", "params": ["inputEV": 1]]]
    let overlay: Object = ["source": "source.png", "mask": full]
    let invalid: [Any] = [NSNull(), ["protect.png"], 2, true, ""]
    for (index, value) in invalid.enumerated() {
        try recipe("render", "invalid-protect-\(index)", ["layers": [["mask": full, "protect": value, "filters": exposure]]],
                   rejecting: "protect")
        try recipe("render", "invalid-image-\(index)", ["layers": [["mask": full, "image": value]]], rejecting: "image")
        try recipe("render", "invalid-color-\(index)", ["color_space": value], rejecting: "color_space")
        try recipe("overlay", "invalid-overlay-\(index)", overlay.merging(["protect": value]) { _, new in new },
                   rejecting: "protect")
    }

    try recipe("render", "global-blur", ["filters": blur])
    try check(try pixels("global-blur").allSatisfy { close($0, to: grayBlue) },
              "Global Gaussian blur darkened or made an opaque edge transparent")
    try recipe("render", "layer-blur", ["layers": [["mask": full, "filters": blur]]])
    try check(try pixels("layer-blur").allSatisfy { close($0, to: grayBlue) },
              "Layer Gaussian blur altered an opaque edge")
    try recipe("render", "transparent-blur", ["source": "transparent.png", "filters": blur])
    let alpha = try pixels("transparent-blur")
    try check(alpha[0][3] == 0 && alpha[side - 1][3] == 255
              && (1..<255).contains(Int(alpha[side / 2][3])), "Blur failed to preserve a real transparent region")

    let patch: Object = ["mask": left, "image": "patch.png", "rect": [0, 0, side / 2, side], "filters": blur]
    try recipe("render", "patch-blur", ["layers": [patch]])
    let composite = try pixels("patch-blur")
    try check(composite.enumerated().allSatisfy { i, pixel in
        close(pixel, to: i % side < side / 2 ? pink : grayBlue)
    }, "Blurred patch changed at its edges or extended past its placement")

    let layer: Object = ["mask": feather, "protect": protected, "filters": exposure]
    try recipe("render", "protected-feather", ["layers": [layer]])
    let result = try pixels("protected-feather")
    let row = side * (side / 2)
    try check(result[row + 7] == grayBlue && result[row] != grayBlue && result[row + 31] == grayBlue
              && result[row][0] > result[row + 15][0] && result[row + 15][0] > result[row + 31][0],
              "Protected core, editable area, or feather transition did not match the recipe")
    try recipe("overlay", "valid-overlay", overlay.merging(["protect": protected]) { _, new in new })
    try check(try pixels("valid-overlay")[row + 7] != grayBlue, "Overlay omitted the protected region")

    try recipe("render", "srgb", ["color_space": "srgb"])
    try recipe("render", "p3", ["color_space": "display-p3", "bit_depth": 16])
    for (name, expected) in [("srgb", CGColorSpace.sRGB), ("p3", CGColorSpace.displayP3)] {
        let file = temp.appendingPathComponent(name + ".png")
        let source = CGImageSourceCreateWithURL(file as CFURL, nil)!
        let raster = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        try check(raster.colorSpace?.name == expected && raster.bitsPerComponent == (name == "p3" ? 16 : 8),
                  "Unexpected output color space or depth: \(name)")
    }
    let common: [Object] = [
        ["name": "CIColorControls", "params": ["inputSaturation": 0]],
        ["name": "CISharpenLuminance", "params": ["inputSharpness": 0.4]],
        ["name": "CINoiseReduction", "params": ["inputNoiseLevel": 0.03]],
    ]
    try recipe("render", "common-filters", ["filters": common])
    try check(try pixels("common-filters").allSatisfy { $0[0] == $0[1] && $0[1] == $0[2] && $0[3] == 255 },
              "Color, sharpening, or denoising smoke test failed")
}

do {
    try files.createDirectory(at: temp, withIntermediateDirectories: false)
    defer { try? files.removeItem(at: temp) }
    try run()
    print("Render regressions passed")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

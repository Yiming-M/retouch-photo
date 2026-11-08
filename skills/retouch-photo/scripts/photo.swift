import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision

// Native recipe processing; no GUI automation or generative calls.
let rendererVersion = "2"
typealias Object = [String: Any]
struct Failure: Error, CustomStringConvertible { let description: String }
func require(_ ok: Bool, _ message: String) throws {
    if !ok { throw Failure(description: message) }
}
func keys(_ object: Object, _ allowed: Set<String>) throws {
    let unknown = Set(object.keys).subtracting(allowed)
    try require(unknown.isEmpty, "Unknown keys: \(unknown.sorted().joined(separator: ", "))")
}
func optionalString(_ object: Object, _ key: String) throws -> String? {
    guard let value = object[key] else { return nil }
    guard let result = value as? String, !result.isEmpty else {
        throw Failure(description: "Expected nonempty string: \(key)")
    }
    return result
}
func string(_ object: Object, _ key: String) throws -> String {
    guard let result = try optionalString(object, key) else {
        throw Failure(description: "Missing string: \(key)")
    }
    return result
}
func number(_ value: Any, _ label: String) throws -> Double {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else {
        throw Failure(description: "Expected finite number: \(label)")
    }
    return n.doubleValue
}
func vector(_ value: Any, count: Int, label: String) throws -> [Double] {
    guard let a = value as? [Any], a.count == count else {
        throw Failure(description: "Expected \(count) numbers: \(label)")
    }
    return try a.map { try number($0, label) }
}
func objects(_ value: Any?, _ label: String) throws -> [Object] {
    guard let value else { return [] }
    guard let result = value as? [Object] else { throw Failure(description: "Expected object array: \(label)") }
    return result
}
func object(_ value: Any?, _ label: String) throws -> Object {
    guard let value else { return [:] }
    guard let result = value as? Object else { throw Failure(description: "Expected object: \(label)") }
    return result
}
func path(_ text: String, relativeTo directory: URL) -> URL {
    URL(fileURLWithPath: (text as NSString).expandingTildeInPath, relativeTo: directory).standardizedFileURL
}
func emit(_ value: Object) throws {
    print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
}
func newFile(_ url: URL) throws {
    try require(!FileManager.default.fileExists(atPath: url.path), "Refusing overwrite: \(url.path). Choose a new version.")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
}
func metadata(_ url: URL) throws -> Object {
    guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let t = CGImageSourceGetType(s) as String?,
          let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? Object else {
        throw Failure(description: "Image I/O cannot inspect: \(url.path)")
    }
    return ["path": url.path, "type": t, "raw": UTType(t)?.conforms(to: .rawImage) ?? false,
            "width": p[kCGImagePropertyPixelWidth as String] ?? NSNull(),
            "height": p[kCGImagePropertyPixelHeight as String] ?? NSNull(),
            "orientation": p[kCGImagePropertyOrientation as String] ?? 1,
            "depth": p[kCGImagePropertyDepth as String] ?? NSNull(),
            "profile": p[kCGImagePropertyProfileName as String] ?? NSNull()]
}
func normalized(_ image: CIImage) -> CIImage {
    image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
}
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
let context = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAh.rawValue, .cacheIntermediates: false])

func load(_ url: URL, raw settings: Object = [:]) throws -> (CIImage, Object) {
    var info = try metadata(url)
    if info["raw"] as? Bool == true {
        guard let raw = CIRAWFilter(imageURL: url) else {
            throw Failure(description: "System RAW decoder cannot open this file; no thumbnail fallback: \(url.path)")
        }
        try keys(settings, ["exposure", "neutralTemperature", "neutralTint", "boostAmount", "boostShadowAmount", "luminanceNoiseReductionAmount", "colorNoiseReductionAmount", "sharpnessAmount", "contrastAmount", "localToneMapAmount", "decoderVersion"])
        if let value = settings["decoderVersion"] {
            guard let version = value as? String else { throw Failure(description: "decoderVersion must be a string") }
            let decoder = CIRAWDecoderVersion(rawValue: version)
            try require(raw.supportedDecoderVersions.contains(decoder), "RAW decoder version unavailable: \(version)")
            raw.decoderVersion = decoder
        }
        for (key, value) in settings where key != "decoderVersion" {
            let v = Float(try number(value, key))
            try require(v.isFinite, "RAW value out of range: \(key)")
            switch key {
            case "exposure": raw.exposure = v
            case "neutralTemperature":
                try require((2000...50000).contains(v), "neutralTemperature must be 2000...50000 K")
                raw.neutralTemperature = v
            case "neutralTint":
                try require((-150...150).contains(v), "neutralTint must be -150...150")
                raw.neutralTint = v
            case "boostAmount":
                try require((0...1).contains(v), "boostAmount must be 0...1")
                raw.boostAmount = v
            case "boostShadowAmount":
                try require((0...2).contains(v), "boostShadowAmount must be 0...2")
                raw.boostShadowAmount = v
            default:
                try require((0...1).contains(v), "\(key) must be 0...1")
                switch key {
                case "luminanceNoiseReductionAmount":
                    try require(raw.isLuminanceNoiseReductionSupported, "RAW luminance denoising unsupported")
                    raw.luminanceNoiseReductionAmount = v
                case "colorNoiseReductionAmount":
                    try require(raw.isColorNoiseReductionSupported, "RAW color denoising unsupported")
                    raw.colorNoiseReductionAmount = v
                case "sharpnessAmount":
                    try require(raw.isSharpnessSupported, "RAW sharpening unsupported")
                    raw.sharpnessAmount = v
                case "contrastAmount":
                    try require(raw.isContrastSupported, "RAW contrast unsupported")
                    raw.contrastAmount = v
                case "localToneMapAmount":
                    try require(raw.isLocalToneMapSupported, "RAW local tone map unsupported")
                    raw.localToneMapAmount = v
                default: break
                }
            }
        }
        raw.scaleFactor = 1
        raw.isDraftModeEnabled = false
        guard let image = raw.outputImage else { throw Failure(description: "RAW development failed: \(url.path)") }
        info["decoderVersion"] = raw.decoderVersion.rawValue
        info["effectiveRawSettings"] = ["exposure": raw.exposure, "neutralTemperature": raw.neutralTemperature, "neutralTint": raw.neutralTint, "boostAmount": raw.boostAmount, "boostShadowAmount": raw.boostShadowAmount, "luminanceNoiseReductionAmount": raw.luminanceNoiseReductionAmount, "colorNoiseReductionAmount": raw.colorNoiseReductionAmount, "sharpnessAmount": raw.sharpnessAmount, "contrastAmount": raw.contrastAmount, "localToneMapAmount": raw.localToneMapAmount]
        return (normalized(image), info)
    }
    try require(settings.isEmpty, "The raw object requires an actual RAW source")
    guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        throw Failure(description: "Cannot decode image: \(url.path)")
    }
    return (normalized(image), info)
}

func filters(_ image: CIImage, _ specs: [Object]) throws -> CIImage {
    var result = image
    for spec in specs {
        try keys(spec, ["name", "params"])
        let name = try string(spec, "name")
        guard let filter = CIFilter(name: name), filter.inputKeys.contains(kCIInputImageKey) else {
            throw Failure(description: "Unavailable single-image Core Image filter: \(name)")
        }
        // Extend edge pixels for sampling, then crop each filter back to the canvas.
        filter.setValue(result.clampedToExtent(), forKey: kCIInputImageKey)
        for (key, value) in try object(spec["params"], "params") {
            try require(key != kCIInputImageKey && filter.inputKeys.contains(key), "Unknown/reserved filter input: \(name).\(key)")
            let expected = (filter.attributes[key] as? Object)?[kCIAttributeClass] as? String
            if let values = value as? [NSNumber] {
                try require(expected == "CIVector" && !values.isEmpty, "Filter input requires a different type: \(key)")
                let floats = try values.map { CGFloat(try number($0, key)) }
                filter.setValue(CIVector(values: floats, count: floats.count), forKey: key)
            } else if let n = value as? NSNumber {
                try require(expected == "NSNumber", "Filter input requires a different type: \(key)")
                filter.setValue(n, forKey: key)
            } else { throw Failure(description: "Use a number or numeric vector for \(name).\(key)") }
        }
        guard let next = filter.outputImage else { throw Failure(description: "Filter produced no image: \(name)") }
        result = next.cropped(to: image.extent)
    }
    return result
}
func mask(_ url: URL, extent: CGRect) throws -> CIImage {
    guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true, .colorSpace: NSNull()]) else {
        throw Failure(description: "Cannot read mask: \(url.path)")
    }
    let m = normalized(image)
    try require(m.extent.size == extent.size, "Mask dimensions must match oriented source: \(url.path)")
    return m
}
func effectiveMask(_ spec: Object, directory: URL, extent: CGRect) throws -> CIImage {
    var m = try mask(path(string(spec, "mask"), relativeTo: directory), extent: extent)
    if let name = try optionalString(spec, "protect") {
        let p = try mask(path(name, relativeTo: directory), extent: extent)
        m = m.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .black).cropped(to: extent), kCIInputMaskImageKey: p.applyingFilter("CIColorInvert")])
    }
    return m.cropped(to: extent)
}
func topLeftRect(_ value: Any, within extent: CGRect) throws -> CGRect {
    let v = try vector(value, count: 4, label: "rect/crop [x,y,width,height]")
    try require(v.allSatisfy { $0.rounded() == $0 }, "Pixel rectangles must use integers")
    let r = CGRect(x: v[0], y: extent.height - v[1] - v[3], width: v[2], height: v[3])
    try require(r.width > 0 && r.height > 0 && extent.contains(r), "Rectangle is outside source canvas")
    return r
}
func save(_ image: CIImage, to url: URL, spec: Object = [:]) throws {
    let colorName = try optionalString(spec, "color_space") ?? "srgb"
    try require(["srgb", "display-p3"].contains(colorName), "color_space must be srgb or display-p3")
    let color = colorName == "srgb" ? srgb : CGColorSpace(name: CGColorSpace.displayP3)!
    let depth = try number(spec["bit_depth"] ?? 8, "bit_depth")
    try require(depth == 8 || depth == 16, "bit_depth must be 8 or 16")
    let format: CIFormat = depth == 16 ? .RGBA16 : .RGBA8
    try newFile(url)
    switch url.pathExtension.lowercased() {
    case "png": try context.writePNGRepresentation(of: image, to: url, format: format, colorSpace: color)
    case "tif", "tiff": try context.writeTIFFRepresentation(of: image, to: url, format: format, colorSpace: color)
    case "jpg", "jpeg":
        try require(depth == 8, "JPEG output requires bit_depth 8")
        let quality = try number(spec["jpeg_quality"] ?? 0.95, "jpeg_quality")
        try require((0...1).contains(quality), "jpeg_quality must be 0...1")
        try context.writeJPEGRepresentation(of: image, to: url, colorSpace: color, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality])
    default: throw Failure(description: "Output must be PNG, TIFF or JPEG; RAW deliverable is original + recipe")
    }
}

func render(_ spec: Object, directory: URL, recipeURL: URL) throws {
    try keys(spec, ["version", "source", "output", "raw", "filters", "layers", "crop", "color_space", "bit_depth", "jpeg_quality"])
    try require(try number(spec["version"] ?? 0, "version") == 1, "Recipe version must be 1")
    let source = path(try string(spec, "source"), relativeTo: directory)
    let output = path(try string(spec, "output"), relativeTo: directory)
    let receipt = URL(fileURLWithPath: output.path + ".render.json")
    try newFile(output)
    try newFile(receipt)
    let (input, info) = try load(source, raw: object(spec["raw"], "raw"))
    let extent = input.extent
    var base = try filters(input, objects(spec["filters"], "filters"))
    for layer in try objects(spec["layers"], "layers") {
        try keys(layer, ["image", "rect", "filters", "mask", "protect"])
        let m = try effectiveMask(layer, directory: directory, extent: extent)
        var candidate = base
        if let name = try optionalString(layer, "image") {
            var patch = try load(path(name, relativeTo: directory)).0
            if let value = layer["rect"] {
                let rect = try topLeftRect(value, within: extent)
                let sx = rect.width / patch.extent.width, sy = rect.height / patch.extent.height
                try require(abs(sx / sy - 1) < 0.005, "Patch aspect ratio mismatch; align/crop explicitly instead of distorting")
                patch = patch.transformed(by: CGAffineTransform(scaleX: sx, y: sy)).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            } else {
                try require(patch.extent.size == extent.size, "Full-canvas patch dimensions differ; provide an explicit rect")
            }
            patch = try filters(patch, objects(layer["filters"], "filters"))
            candidate = patch.composited(over: base).cropped(to: extent)
        } else {
            try require(layer["rect"] == nil, "rect is only valid with a patch image")
            candidate = try filters(base, objects(layer["filters"], "filters"))
        }
        base = candidate.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base, kCIInputMaskImageKey: m]).cropped(to: extent)
    }
    if let crop = spec["crop"] { base = normalized(base.cropped(to: try topLeftRect(crop, within: extent))) }
    try save(base, to: output, spec: spec)
    let record: Object = ["renderer_version": rendererVersion, "macos": ProcessInfo.processInfo.operatingSystemVersionString, "recipe": recipeURL.path, "source": info, "output": try metadata(output)]
    try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: receipt, options: .atomic)
    try emit(["output": output.path, "receipt": receipt.path, "width": base.extent.width, "height": base.extent.height])
}

func makeMask(_ spec: Object, directory: URL) throws {
    try keys(spec, ["width", "height", "polygons", "invert", "feather", "output"])
    let w = try number(spec["width"] ?? 0, "width"), h = try number(spec["height"] ?? 0, "height")
    try require(w > 0 && h > 0 && w.rounded() == w && h.rounded() == h, "Positive integer mask dimensions required")
    guard let canvas = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: Int(w), space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        throw Failure(description: "Cannot allocate mask canvas")
    }
    canvas.setFillColor(gray: 0, alpha: 1)
    canvas.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for polygon in try objects(spec["polygons"], "polygons") {
        try keys(polygon, ["points", "value"])
        guard let points = polygon["points"] as? [Any], points.count >= 3 else { throw Failure(description: "Polygon requires at least three points") }
        let intensity = try number(polygon["value"] ?? 1, "value")
        try require((0...1).contains(intensity), "Mask value must be 0...1")
        canvas.beginPath()
        for (index, p) in points.enumerated() {
            let v = try vector(p, count: 2, label: "point")
            try require((0...w).contains(v[0]) && (0...h).contains(v[1]), "Polygon point outside mask")
            let point = CGPoint(x: v[0], y: h - v[1])
            if index == 0 { canvas.move(to: point) } else { canvas.addLine(to: point) }
        }
        canvas.closePath()
        canvas.setFillColor(gray: intensity, alpha: 1)
        canvas.fillPath()
    }
    guard let cg = canvas.makeImage() else { throw Failure(description: "Cannot render mask") }
    var image = CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
    if let value = spec["invert"] { try require(value is Bool, "invert must be boolean") }
    if spec["invert"] as? Bool == true { image = image.applyingFilter("CIColorInvert") }
    let radius = try number(spec["feather"] ?? 0, "feather")
    try require(radius >= 0, "feather must be nonnegative")
    if radius > 0 { image = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: image.extent) }
    let output = path(try string(spec, "output"), relativeTo: directory)
    try saveMask(image, to: output)
    try emit(["output": output.path, "width": w, "height": h])
}
func saveMask(_ image: CIImage, to url: URL) throws {
    try require(url.pathExtension.lowercased() == "png", "Masks must be saved as PNG")
    try newFile(url)
    // Numeric coverage, not a photograph: avoid an sRGB gamma transformation.
    try context.writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: linear)
}

func overlay(_ spec: Object, directory: URL) throws {
    try keys(spec, ["source", "mask", "protect", "output", "opacity"])
    var base = try load(path(string(spec, "source"), relativeTo: directory)).0
    let extent = base.extent
    let m = try effectiveMask(spec, directory: directory, extent: extent)
    let opacity = try number(spec["opacity"] ?? 0.4, "opacity")
    try require((0...1).contains(opacity), "opacity must be 0...1")
    func tint(_ color: CIColor, using mask: CIImage) {
        let colored = CIImage(color: color).cropped(to: extent).composited(over: base)
        base = colored.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base, kCIInputMaskImageKey: mask]).cropped(to: extent)
    }
    tint(CIColor(red: 1, green: 0.1, blue: 0.1, alpha: opacity), using: m)
    if let p = try optionalString(spec, "protect") {
        tint(CIColor(red: 0.1, green: 1, blue: 0.2, alpha: opacity), using: try mask(path(p, relativeTo: directory), extent: extent))
    }
    let low = m.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.01])
    let high = m.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.99])
    let transition = low.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: high])
    tint(CIColor(red: 1, green: 0.85, blue: 0, alpha: opacity), using: transition)
    let output = path(try string(spec, "output"), relativeTo: directory)
    try save(base, to: output)
    try emit(["output": output.path, "legend": ["green": "protected", "red": "editable", "yellow": "transition"]])
}

func foreground(_ spec: Object, directory: URL) throws {
    try keys(spec, ["source", "instances", "output"])
    if #available(macOS 14.0, *) {
        let input = try load(path(string(spec, "source"), relativeTo: directory)).0
        guard let cg = context.createCGImage(input, from: input.extent) else { throw Failure(description: "Cannot render Vision input") }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw Failure(description: "Vision found no foreground; draw/refine a mask instead")
        }
        var selected = observation.allInstances
        if let value = spec["instances"] {
            guard let list = value as? [Int], !list.isEmpty else { throw Failure(description: "instances must be nonempty integer array") }
            selected = IndexSet(list)
            try require(selected.isSubset(of: observation.allInstances), "Requested foreground instance is unavailable")
        }
        let buffer = try observation.generateScaledMaskForImage(forInstances: selected, from: handler)
        let output = path(try string(spec, "output"), relativeTo: directory)
        try saveMask(CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()]), to: output)
        try emit(["output": output.path, "available_instances": Array(observation.allInstances), "selected_instances": Array(selected)])
    } else { throw Failure(description: "Automatic foreground masks require macOS 14+; polygon masks remain available") }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty || args == ["--help"] {
        print("""
        retouch-photo native helper
        Requires Xcode or Command Line Tools 15+, Swift 5.9+, and the macOS 14 SDK or later.
        Host macOS 13.5+ (newer toolchains may require a newer host).
        Vision foreground masks require macOS 14+ at runtime.
        Tested on macOS 27.0.1 with Swift 6.4.
        photo.sh inspect IMAGE
        photo.sh render RECIPE.json
        photo.sh mask MASK.json
        photo.sh foreground FOREGROUND.json
        photo.sh overlay OVERLAY.json
        Relative paths resolve beside each JSON specification. Outputs never overwrite.
        See references/native-processing.md for recipes and top-left pixel coordinates.
        """)
    } else {
        try require(args.count == 2, "Expected command and image/specification path; use --help")
        let url = path(args[1], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        if args[0] == "inspect" {
            let (image, info) = try load(url)
            var result = info
            result["oriented_width"] = image.extent.width
            result["oriented_height"] = image.extent.height
            // Force a small render: an extent alone doesn't prove decoding works.
            let scale = min(1, 64 / max(image.extent.width, image.extent.height))
            let tiny = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            try require(context.createCGImage(tiny, from: tiny.extent) != nil, "Core Image could not render a preview. Restricted graphics access can cause this even for valid files; check execution permissions before declaring the format unsupported.")
            try emit(result)
        } else {
            let spec = try object(JSONSerialization.jsonObject(with: Data(contentsOf: url)), "specification")
            let directory = url.deletingLastPathComponent()
            switch args[0] {
            case "render": try render(spec, directory: directory, recipeURL: url)
            case "mask": try makeMask(spec, directory: directory)
            case "overlay": try overlay(spec, directory: directory)
            case "foreground": try foreground(spec, directory: directory)
            default: throw Failure(description: "Unknown command: \(args[0])")
            }
        }
    }
} catch {
    FileHandle.standardError.write(Data("retouch-photo: \(error)\n".utf8))
    exit(1)
}

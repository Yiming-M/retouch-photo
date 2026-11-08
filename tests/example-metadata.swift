import Foundation
import ImageIO

func isSensitive(_ key: String) -> Bool {
    let name = key.lowercased().filter(\.isLetter)
    return ["gps", "serial", "makernote", "makerapple", "makercanon", "makernikon", "makerfuji",
            "makerolympus", "makerpentax", "makerpanasonic", "makersigma", "makersamsung",
            "datetime", "dateoriginal", "datecreated", "createdate", "creationdate", "creationtime",
            "modifydate", "metadatadate", "datestamp", "timestamp", "offsettime", "subsectime",
            "timecreated", "hostcomputer", "imageuniqueid", "compositeimagesourceexposuretimes"].contains {
        name.contains($0)
    }
}

func scanProperties(_ value: Any, at path: String = "") -> [String] {
    if let dict = value as? [String: Any] {
        return dict.flatMap { key, entry in
            let location = path.isEmpty ? key : path + "/" + key
            return (isSensitive(key) ? [location] : []) + scanProperties(entry, at: location)
        }
    }
    if let entries = value as? [Any] {
        return entries.flatMap { scanProperties($0, at: path) }
    }
    return []
}

guard CommandLine.arguments.count == 2 else {
    print("Usage: swift tests/example-metadata.swift EXAMPLES_DIRECTORY")
    exit(1)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let images = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects
    .compactMap { $0 as? URL }.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) } ?? []
guard !images.isEmpty else {
    print("No example images found")
    exit(1)
}
var failures = 0
for file in images.sorted(by: { $0.path < $1.path }) {
    let relative = String(file.path.dropFirst(root.path.count + 1))
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else {
        print("\(relative): could not read image properties")
        failures += 1
        continue
    }
    var found = scanProperties(properties)
    if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
        let options = [kCGImageMetadataEnumerateRecursively: true] as CFDictionary
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, options) { path, _ in
            let key = path as String
            if isSensitive(key) { found.append("XMP/" + key) }
            return true
        }
    }
    if !found.isEmpty {
        print("\(relative): \(Set(found).sorted().joined(separator: ", "))")
        failures += 1
    }
}
print("Scanned \(images.count) example images. Images with sensitive fields: \(failures).")
exit(failures == 0 ? 0 : 1)

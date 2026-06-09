#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO

struct ImageMetrics: Codable {
    var path: String
    var width: Int
    var height: Int
    var sampledPixels: Int
    var opaqueSamples: Int
    var distinctColorBuckets: Int
    var averageLuminance: Double
    var luminanceStandardDeviation: Double
    var alphaCoverage: Double
}

struct VisualReport: Codable {
    var light: ImageMetrics
    var dark: ImageMetrics
    var luminanceDelta: Double
    var failures: [String]
}

enum VisualMetricsError: Error, CustomStringConvertible {
    case usage
    case loadFailed(String)
    case drawFailed(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: scripts/visual-metrics.swift light.png dark.png"
        case let .loadFailed(path):
            return "Could not load image: \(path)"
        case let .drawFailed(path):
            return "Could not draw image into RGBA buffer: \(path)"
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    guard arguments.count == 2 else {
        throw VisualMetricsError.usage
    }

    let light = try metrics(for: arguments[0])
    let dark = try metrics(for: arguments[1])
    let luminanceDelta = light.averageLuminance - dark.averageLuminance
    let failures = visualFailures(light: light, dark: dark, luminanceDelta: luminanceDelta)
    let report = VisualReport(light: light, dark: dark, luminanceDelta: luminanceDelta, failures: failures)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    print(String(decoding: data, as: UTF8.self))

    if !failures.isEmpty {
        exit(1)
    }
} catch {
    fputs("visual-metrics: \(error)\n", stderr)
    exit(2)
}

func metrics(for path: String) throws -> ImageMetrics {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw VisualMetricsError.loadFailed(path)
    }

    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else {
        throw VisualMetricsError.loadFailed(path)
    }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = width * 4
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let baseAddress = buffer.baseAddress,
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
              ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drewImage else {
        throw VisualMetricsError.drawFailed(path)
    }

    let targetSamples = 12_000
    let sampleStep = max(1, Int(sqrt(Double(width * height) / Double(targetSamples))))
    var sampledPixels = 0
    var opaqueSamples = 0
    var luminanceValues: [Double] = []
    var buckets = Set<Int>()

    for y in stride(from: 0, to: height, by: sampleStep) {
        for x in stride(from: 0, to: width, by: sampleStep) {
            sampledPixels += 1
            let offset = (y * width + x) * 4
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            let alpha = pixels[offset + 3]
            guard alpha >= 16 else {
                continue
            }
            opaqueSamples += 1
            let redLuminance = 0.2126 * Double(red)
            let greenLuminance = 0.7152 * Double(green)
            let blueLuminance = 0.0722 * Double(blue)
            let luminance = (redLuminance + greenLuminance + blueLuminance) / 255.0
            luminanceValues.append(luminance)
            let redBucket = (Int(red) / 32) << 6
            let greenBucket = (Int(green) / 32) << 3
            let blueBucket = Int(blue) / 32
            let bucket = redBucket | greenBucket | blueBucket
            buckets.insert(bucket)
        }
    }

    let average = luminanceValues.isEmpty ? 0 : luminanceValues.reduce(0, +) / Double(luminanceValues.count)
    let variance = luminanceValues.isEmpty
        ? 0
        : luminanceValues.reduce(0) { total, value in
            let delta = value - average
            return total + delta * delta
        } / Double(luminanceValues.count)

    return ImageMetrics(
        path: path,
        width: width,
        height: height,
        sampledPixels: sampledPixels,
        opaqueSamples: opaqueSamples,
        distinctColorBuckets: buckets.count,
        averageLuminance: average,
        luminanceStandardDeviation: sqrt(variance),
        alphaCoverage: sampledPixels == 0 ? 0 : Double(opaqueSamples) / Double(sampledPixels)
    )
}

func visualFailures(light: ImageMetrics, dark: ImageMetrics, luminanceDelta: Double) -> [String] {
    var failures: [String] = []
    for (name, metrics) in [("light", light), ("dark", dark)] {
        if metrics.width < 600 || metrics.height < 300 {
            failures.append("\(name) screenshot is too small: \(metrics.width)x\(metrics.height)")
        }
        if metrics.sampledPixels < 1_000 {
            failures.append("\(name) screenshot sampled too few pixels: \(metrics.sampledPixels)")
        }
        if metrics.alphaCoverage < 0.35 {
            failures.append("\(name) screenshot has too little opaque window coverage: \(metrics.alphaCoverage)")
        }
        if metrics.distinctColorBuckets < 8 {
            failures.append("\(name) screenshot has too few color buckets: \(metrics.distinctColorBuckets)")
        }
        if metrics.luminanceStandardDeviation < 0.025 {
            failures.append("\(name) screenshot appears too visually flat: \(metrics.luminanceStandardDeviation)")
        }
    }

    if luminanceDelta < 0.08 {
        failures.append("light and dark appearances are not visually distinct enough: luminance delta \(luminanceDelta)")
    }

    return failures
}

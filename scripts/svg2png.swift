#!/usr/bin/env swift
//
// Minimal SVG -> PNG rasteriser for design/menubaricon.svg.
//
//     swift scripts/svg2png.swift <in.svg> <out.png> <pixels> [group-id]
//
// It exists because the obvious tools are not dependable here: the Homebrew
// inkscape cask on this machine is a broken shim, ImageMagick's built-in SVG
// renderer mangles the sparkles' concave cubics, and qlmanage ignores the
// requested size. Everything below only needs Swift + CoreGraphics, which an
// Xcode project already has.
//
// Deliberately not a general SVG parser: it understands a square viewBox,
// top-level `<g id="…">` groups, and absolute M/C/Z path data — exactly what
// design/menubaricon.svg uses. Everything is filled black; the asset catalog
// marks the results as template images.
//
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 4, let pixels = Int(args[3]) else {
    FileHandle.standardError.write(
        Data("usage: svg2png.swift <in.svg> <out.png> <pixels> [group-id]\n".utf8))
    exit(2)
}
let inputPath = args[1], outputPath = args[2]
let groupID: String? = args.count > 4 ? args[4] : nil

guard let svg = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
    FileHandle.standardError.write(Data("error: cannot read \(inputPath)\n".utf8))
    exit(1)
}

/// The viewBox is assumed square: `viewBox="0 0 N N"`.
func viewBoxSize(_ source: String) -> Double {
    guard let range = source.range(of: #"viewBox="[^"]*""#, options: .regularExpression) else {
        return 36
    }
    let numbers = source[range]
        .split(whereSeparator: { !"0123456789.-".contains($0) })
        .compactMap { Double($0) }
    return numbers.count == 4 ? numbers[3] : 36
}

/// Every `d="…"` in the document, or only those inside `<g id="groupID">`.
func pathData(_ source: String, group: String?) -> [String] {
    var scope = source
    if let group {
        guard let start = source.range(of: "<g id=\"\(group)\"") else {
            FileHandle.standardError.write(Data("error: no group id=\"\(group)\"\n".utf8))
            exit(1)
        }
        let rest = source[start.upperBound...]
        let end = rest.range(of: "</g>")?.lowerBound ?? rest.endIndex
        scope = String(rest[..<end])
    }

    var result: [String] = []
    var cursor = scope.startIndex
    while let open = scope.range(of: "d=\"", range: cursor..<scope.endIndex),
          let close = scope.range(of: "\"", range: open.upperBound..<scope.endIndex) {
        result.append(String(scope[open.upperBound..<close.lowerBound]))
        cursor = close.upperBound
    }
    return result
}

/// Absolute M/C/Z only — the sparkles are a moveto plus four cubics.
func makePath(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var command: Character = " "
    var numbers: [CGFloat] = []

    func flush() {
        switch command {
        case "M" where numbers.count >= 2:
            path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
        case "C":
            for i in stride(from: 0, to: numbers.count - 5, by: 6) {
                path.addCurve(
                    to: CGPoint(x: numbers[i + 4], y: numbers[i + 5]),
                    control1: CGPoint(x: numbers[i], y: numbers[i + 1]),
                    control2: CGPoint(x: numbers[i + 2], y: numbers[i + 3]))
            }
        case "Z", "z":
            path.closeSubpath()
        default:
            break
        }
        numbers.removeAll()
    }

    var token = ""
    func takeNumber() {
        if !token.isEmpty, let value = Double(token) { numbers.append(CGFloat(value)) }
        token = ""
    }

    for character in d {
        if character.isNumber || character == "." || character == "-" {
            // A '-' starts a new number unless it is a leading sign.
            if character == "-", !token.isEmpty { takeNumber() }
            token.append(character)
        } else if character.isLetter {
            takeNumber()
            flush()
            command = character
        } else {
            takeNumber()
        }
    }
    takeNumber()
    flush()
    return path
}

let side = viewBoxSize(svg)
let paths = pathData(svg, group: groupID)

guard let context = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
    FileHandle.standardError.write(Data("error: cannot create bitmap context\n".utf8))
    exit(1)
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
// SVG's origin is top-left with y growing downwards; CoreGraphics' is bottom-left.
let scale = CGFloat(pixels) / CGFloat(side)
context.translateBy(x: 0, y: CGFloat(pixels))
context.scaleBy(x: scale, y: -scale)
context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
for d in paths {
    context.addPath(makePath(d))
}
context.fillPath()

guard let image = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("error: cannot encode PNG\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))

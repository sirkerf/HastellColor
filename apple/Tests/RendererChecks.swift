import Foundation
import MetalKit
import ImageIO
import Darwin

// A failed check is an ordinary command-line failure. Do not turn it into a
// SIGTRAP / macOS crash report; scripts still receive a nonzero exit status.
func failRendererCheck(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Renderer checks failed: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

struct Fixture: Decodable {
    var name: String
    var colors: [[Float]]
    var samples: [[[Float]]]
    var pixels: [Float]
    var strokes: [PaintStroke] {
        zip(colors, samples).map { color, samples in
            PaintStroke(color: InkColor(red: color[0], green: color[1], blue: color[2]), radius: 4.5,
                eraser: false, samples: samples.map {
                    PencilSample(x: $0[0], y: $0[1], pressure: $0[2], altitude: $0[3], azimuth: $0[4])
                })
        }
    }
}

@main struct RendererChecks {
    static func main() {
        do { try run() }
        catch { failRendererCheck(error.localizedDescription) }
    }

    private static func run() throws {
        guard CommandLine.arguments.count == 4 else { failRendererCheck("Provide Metal source and CPU fixtures") }
        guard let device = MTLCreateSystemDefaultDevice() else { failRendererCheck("Metal GPU required; tests cannot be skipped") }
        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        let painter = try MetalPainter(width: 32, height: 24, device: device, library: library)
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else { failRendererCheck(message) }
            checks += 1
        }
        for fixture in fixtures {
            try painter.replay(fixture.strokes)
            let actual = try painter.pixels()
            let maxError = zip(actual, fixture.pixels).map { abs($0 - $1) }.max()!
            check(maxError < 0.003, "CPU/GPU mismatch: \(fixture.name), error \(maxError)")
            print("CPU/GPU \(fixture.name): max error \(maxError)")
        }
        let stroke = fixtures[1].strokes[0]
        try painter.replay([stroke])
        let whole = try painter.pixels()
        try painter.reset()
        try painter.beginStroke()
        for i in stroke.samples.indices {
            try painter.append(Array(stroke.samples[max(0, i - 1)...i]), stroke: stroke)
        }
        check(try painter.pixels() == whole, "Batching changes deposition")
        var document = Drawing(width: 32, height: 24, strokes: [stroke])
        check(try Drawing.decode(document.encoded()) == document, "Lossless archive round trip")
        var malformed = document
        malformed.width = -1
        check((try? malformed.encoded()) == nil, "Invalid dimensions accepted")
        malformed = document
        malformed.strokes[0].samples[0].pressure = 2
        check((try? malformed.encoded()) == nil, "Invalid pressure accepted")
        malformed = document
        malformed.colorSpace = "srgb"
        check((try? malformed.encoded()) == nil, "Unknown color space accepted")
        document.strokes[0].eraser = true
        try painter.beginStroke()
        try painter.append(document.strokes[0].samples, stroke: document.strokes[0])
        let erased = try painter.pixels()
        let alphaIndices = stride(from: 3, to: erased.count, by: 4)
        check(alphaIndices.allSatisfy { erased[$0] <= whole[$0] }, "Eraser adds pigment")
        check(alphaIndices.contains { erased[$0] < whole[$0] }, "Eraser has no effect")
        let png = try painter.png()
        let imageSource = CGImageSourceCreateWithData(png as CFData, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
        check(decoded.bitsPerComponent == 16, "PNG was reduced to 8 bits")
        check(decoded.width == 32 && decoded.height == 24, "PNG dimensions changed")
        check(decoded.colorSpace?.name == CGColorSpace.displayP3, "PNG lost its P3 profile")
        try painter.reset()
        check(try painter.pixels().allSatisfy { $0 == 0 }, "Clear left old pixels")
        for channel in InkColor.Channel.allCases {
            let colors = (0...1023).map { InkColor.vermilion.settingLevel($0, channel: channel) }
            check(colors.enumerated().allSatisfy { $0.element.level(channel) == $0.offset },
                "10-bit P3 levels do not round trip: \(channel)")
            check(colors.allSatisfy(\.valid), "Color picker produced invalid values")
        }
        let black = InkColor(red: 0, green: 0, blue: 0)
        let gray = black.settingLevel(512, channel: .red).settingLevel(512, channel: .green)
            .settingLevel(512, channel: .blue)
        check(abs(gray.red - 0.2144938) < 0.000001, "Picker failed to decode the P3 transfer function")
        let precise = gray.settingLevel(513, channel: .red)
        check(precise.green == gray.green && precise.blue == gray.blue, "Editing red quantized other channels")
        let levels = (0...1023).map { Float16(black.settingLevel($0, channel: .red).red).bitPattern }
        check(Set(levels).count == 1024, "16-bit GPU storage collapses 10-bit picker levels")
        let exact = InkColor(red: 0.1234567, green: 0.7654321, blue: 0.2345678)
        var selection = PaletteSelection(exact)
        check(selection.color == exact, "Opening a traditional palette quantized the colour")
        let samples: [Float] = [0, 0.0012345, 0.01765, 0.1234567, 0.50431, 0.76432, 1]
        check(samples.allSatisfy { r in samples.allSatisfy { g in samples.allSatisfy { b in
            let color = InkColor(red: r, green: g, blue: b), restored = PaletteHSV(color).color
            return abs(restored.red-r) < 0.000001 && abs(restored.green-g) < 0.000001 && abs(restored.blue-b) < 0.000001
        } } }, "P3 HSV round trip changed colour or reduced precision")
        selection.edit(hue: 0, saturation: 1, brightness: 1)
        check(selection.color == InkColor(red: 1, green: 0, blue: 0), "Traditional palette lost the P3 red primary")
        selection.selectClassic(x: 0, y: 0)
        check(selection.color == .white, "Classic white corner")
        selection.selectClassic(x: 1, y: 1)
        check(selection.color == black, "Classic black corner")
        selection.edit(hue: 0.7, saturation: 0.8, brightness: 0)
        selection.setColor(black); selection.edit(brightness: 0.7)
        check(abs(selection.hsv.hue-0.7) < 0.000001 && abs(selection.hsv.saturation-0.8) < 0.000001,
            "Passing through black lost the intended hue or saturation")
        selection.selectCircle(x: 1, y: 0.5)
        check(selection.hsv.hue == 0 && selection.hsv.saturation == 1 && selection.hsv.brightness == 0.7,
            "Circle selection changed brightness or chose the wrong hue")
        selection.selectCircle(x: 0.5, y: 0.5)
        check(selection.hsv.saturation == 0 && selection.color.red == selection.color.green
            && selection.color.green == selection.color.blue, "Circle centre is not neutral")
        selection.edit(hue: 0.2, saturation: 0.501, brightness: 0.7345)
        let subtle = selection.color
        selection.edit(saturation: 0.5011)
        check(selection.color != subtle, "Traditional palette rounded subtle changes to 8-bit levels")
        var preciseDocument = Drawing(width: 32, height: 24, strokes: [stroke])
        preciseDocument.strokes[0].color = precise
        check(try Drawing.decode(preciseDocument.encoded()) == preciseDocument, "Save quantized the chosen color")
        try painter.replay(preciseDocument.strokes)
        let precisePixels = try painter.pixels()
        let painted = stride(from: 3, to: precisePixels.count, by: 4).first { precisePixels[$0] > 0.1 }!
        check(abs(precisePixels[painted - 3] - precise.red) < 0.0002,
            "The selected color did not reach the Metal canvas")
        var draft = PaperDraft()
        check(draft.size == PaperSize(width: 2480, height: 3508, dpi: 300), "A4 / 300 dpi conversion")
        draft.selectUse(.comic)
        check(draft.size == PaperSize(width: 4961, height: 7016, dpi: 600), "Comic A4 / 600 dpi conversion")
        draft.selectPreset(.b5)
        check(draft.size == PaperSize(width: 4299, height: 6071, dpi: 600), "B5 must use JIS dimensions")
        draft.selectPreset(.b4)
        check(draft.size == nil, "Oversized B4 / 600 dpi must be rejected before allocation")
        draft.dpi = 350
        check(draft.size != nil, "B4 / 350 dpi should fit")
        draft.selectUse(.screen)
        check(draft.size == PaperSize(width: 2048, height: 2048, dpi: 72), "Screen preset")
        let originalSize = draft.size
        for _ in 0..<20 { draft.selectUnit(.mm); draft.selectUnit(.px) }
        check(draft.size == originalSize, "Unit switching changed pixel dimensions")
        draft.dpiText = "96.5"
        check(draft.size == PaperSize(width: 2048, height: 2048, dpi: 96.5), "Custom dpi resampled pixel input")
        draft.selectUnit(.mm)
        draft.width = "２５．４"; draft.height = "50.8"; draft.dpiText = "１４５．５"
        check(draft.size == PaperSize(width: 146, height: 291, dpi: 145.5), "Custom fractional mm/dpi conversion")
        check(draft.size!.physicalDescription.contains("145.5 dpi"), "Fractional dpi rounded in the paper label")
        let fractional = Drawing(width: 146, height: 291, dpi: 145.5)
        check(try Drawing.decode(fractional.encoded()) == fractional, "Fractional dpi lost in archive")
        for invalid in ["", "0", "35.9", "1200.1", "NaN", "inf", "300dpi"] {
            draft.dpiText = invalid
            check(draft.size == nil && !draft.validDPI, "Invalid custom dpi accepted: \(invalid)")
        }
        draft.selectPreset(.postcard); draft.dpi = 300
        check(draft.size == PaperSize(width: 1181, height: 1748, dpi: 300), "Postcard conversion")
        draft.swapOrientation()
        check(draft.size?.width == 1748 && draft.size?.height == 1181, "Landscape swap failed")
        for value in ["nan", "inf", "1e99", "-1", "0", "", "abc"] {
            draft.width = value
            check(draft.size == nil, "Invalid size accepted: \(value)")
        }
        preciseDocument.paperColor = PaperPalette.colors[2].1
        preciseDocument.dpi = 600
        preciseDocument.strokes[0].strength = 2
        check(try Drawing.decode(preciseDocument.encoded()) == preciseDocument, "Paper and strength lost on save")
        var legacy = try JSONSerialization.jsonObject(with: preciseDocument.encoded()) as! [String: Any]
        legacy["version"] = 1; legacy.removeValue(forKey: "dpi"); legacy.removeValue(forKey: "paperColor")
        var legacyStrokes = legacy["strokes"] as! [[String: Any]]
        legacyStrokes[0].removeValue(forKey: "strength"); legacy["strokes"] = legacyStrokes
        let migrated = try Drawing.decode(JSONSerialization.data(withJSONObject: legacy))
        check(migrated.version == 3 && migrated.grain == .legacy && migrated.paperColor == .white && migrated.dpi == 300
            && migrated.strokes[0].strength == 1 && migrated.strokes[0].samples == stroke.samples, "Legacy drawing migration")
        for dpi in [0.0, -300, 1201, .infinity] {
            malformed = preciseDocument; malformed.dpi = dpi
            check((try? malformed.encoded()) == nil, "Invalid dpi accepted")
        }
        malformed = preciseDocument; malformed.paperColor.red = -1
        check((try? malformed.encoded()) == nil, "Invalid paper color accepted")
        malformed = preciseDocument; malformed.strokes[0].strength = 3
        check((try? malformed.encoded()) == nil, "Invalid pigment strength accepted")
        var strong = stroke; strong.strength = 2
        try painter.replay([strong])
        let stronger = try painter.pixels()
        check(alphaIndices.allSatisfy { abs(stronger[$0] - min(1, whole[$0] * 2)) < 0.002 },
            "Strength must multiply grain contact without adding pigment in untouched areas")
        check(alphaIndices.contains { stronger[$0] > whole[$0] + 0.01 }, "Strength has no effect")
        try painter.reset(); try painter.beginStroke()
        for i in strong.samples.indices {
            try painter.append(Array(strong.samples[max(0, i - 1)...i]), stroke: strong)
        }
        check(try painter.pixels() == stronger, "Strong pigment depends on batch boundaries")
        check((0...65535).allSatisfy { bits in
            let expected = Float(Float16(bitPattern: UInt16(bits)))
            let actual = MetalPainter.linearHalf(UInt16(bits))
            return expected.isNaN ? actual.isNaN : expected == actual
        }, "Portable binary16 decoding changed pixel values")
        try painter.reset()
        painter.paperColor = PaperPalette.colors[2].1; painter.dpi = 254.5
        let paperPNG = try painter.png()
        let paperSource = CGImageSourceCreateWithData(paperPNG as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(paperSource, 0, nil)! as NSDictionary
        check(abs((properties[kCGImagePropertyDPIWidth] as! Double) - 254.5) < 0.1
            && abs((properties[kCGImagePropertyDPIHeight] as! Double) - 254.5) < 0.1, "PNG lost fractional print resolution")
        let paperImage = CGImageSourceCreateImageAtIndex(paperSource, 0, nil)!
        var decodedPaper = [Float](repeating: 0, count: 32 * 24 * 4)
        decodedPaper.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 32, height: 24, bitsPerComponent: 32,
                bytesPerRow: 32 * 16, space: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.draw(paperImage, in: CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let paper = painter.paperColor
        check(abs(decodedPaper[0] - paper.red) < 0.0002 && abs(decodedPaper[1] - paper.green) < 0.0002
            && abs(decodedPaper[2] - paper.blue) < 0.0002 && decodedPaper[3] == 1, "PNG paper tint differs from linear P3 background")
        // Exercise the actual memory/readback path at a useful comic resolution.
        do {
            let comic = try MetalPainter(width: 4961, height: 7016, device: device, library: library)
            comic.dpi = 600; comic.paperColor = paper
            try comic.replay([strong])
            let largePNG = try comic.png()
            let largeSource = CGImageSourceCreateWithData(largePNG as CFData, nil)!
            let info = CGImageSourceCopyPropertiesAtIndex(largeSource, 0, nil)! as NSDictionary
            check(info[kCGImagePropertyPixelWidth] as? Int == 4961 && info[kCGImagePropertyPixelHeight] as? Int == 7016,
                "A4 / 600 dpi GPU canvas or export failed")
        }
        checks += try checkMaterials(device: device, library: library, fixturePath: CommandLine.arguments[3])
        print("Passed \(checks) Apple renderer/document checks on \(device.name).")
    }
}

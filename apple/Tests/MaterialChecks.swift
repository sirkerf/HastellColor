import Foundation
import MetalKit

private struct MaterialFixture: Decodable {
    var name: String
    var grain: UInt32
    var tool: UInt32
    var initial: [Float]
    var pixels: [Float]
}

func checkMaterials(device: MTLDevice, library: MTLLibrary, fixturePath: String) throws -> Int {
    var checks = 0
    func check(_ condition: Bool, _ message: String) {
        guard condition else { failRendererCheck(message) }
        checks += 1
    }
    func point(_ x: Float, _ y: Float, _ pressure: Float = 0.8) -> PencilSample {
        .init(x: x, y: y, pressure: pressure, altitude: .pi / 2, azimuth: 0)
    }
    func mass(_ pixels: [Float], channel: Int = 3) -> Double {
        stride(from: 0, to: pixels.count, by: 4).reduce(0) {
            $0 + Double(channel == 3 ? pixels[$1 + 3] : pixels[$1 + channel] * pixels[$1 + 3])
        }
    }
    let paint = [
        PaintStroke(color: .vermilion, radius: 4.5, eraser: false, samples: [point(8,4), point(8,20)]),
        PaintStroke(color: .init(red: 0.035, green: 0.07, blue: 0.65), radius: 4.5, eraser: false,
            samples: [point(17,4), point(17,20)])
    ]
    let painter = try MetalPainter(width: 32, height: 24, device: device, library: library)
    let fixtures = try JSONDecoder().decode([MaterialFixture].self, from: Data(contentsOf: URL(fileURLWithPath: fixturePath)))
    var toolResults: [[Float]] = []
    for fixture in fixtures {
        painter.grain = PaperGrain.allCases.first { $0.metalIndex == fixture.grain }!
        try painter.replay(paint)
        let beforeRubbing = try painter.pixels()
        if fixture.tool != 0 {
            let tool = RubbingTool.allCases.first { $0.metalIndex == fixture.tool }!
            let samples = tool == .kneaded ? [point(12,12)] : [point(5,12), point(25,12)]
            let rub = PaintStroke(color: .white, radius: 6, eraser: false, samples: samples, rubbing: tool)
            try painter.beginStroke(rubbing: tool)
            try painter.append(samples, stroke: rub)
        }
        let actual = try painter.pixels()
        // Compare pigment amount and premultiplied colour. Colour in a vanishing
        // trace is ill-conditioned and may underflow in half-float storage.
        let maximum = stride(from: 0, to: actual.count, by: 4).map { i -> Float in
            var error = abs(actual[i+3] - fixture.pixels[i+3])
            for channel in 0..<3 { error = max(error,
                abs(actual[i+channel]*actual[i+3] - fixture.pixels[i+channel]*fixture.pixels[i+3])) }
            return error
        }.max()!
        print("Material CPU/GPU \(fixture.name): max error \(maximum)")
        check(maximum < 0.004, "Material reference mismatch: \(fixture.name), error \(maximum)")
        if fixture.tool > 0 && fixture.tool < 4 {
            let massErrors = (0..<4).map { mass(actual, channel: $0) - mass(beforeRubbing, channel: $0) }
            print("Material mass error \(fixture.name): \(massErrors)")
            check(massErrors.allSatisfy { abs($0) < 0.15 },
                "Rubbing loses pigment or changes colour mass: \(fixture.name), errors \(massErrors)")
            toolResults.append(actual)
        }
    }
    check(toolResults[0] != toolResults[1] && toolResults[1] != toolResults[2], "Rubbing tools have identical behaviour")
    painter.grain = .medium
    for tool in RubbingTool.allCases {
        var rub = PaintStroke(color: .white, radius: 6, eraser: false,
            samples: [point(5,12), point(25,12)], rubbing: tool)
        try painter.replay([rub])
        check(try painter.pixels().allSatisfy { $0 == 0 }, "Rubbing creates pigment on blank paper")
        try painter.replay(paint + [rub])
        let together = try painter.pixels()
        rub.color = .vermilion
        try painter.replay(paint + [rub])
        check(try painter.pixels() == together, "Rubbing adds the selected ink colour")
        try painter.replay(paint)
        try painter.beginStroke(rubbing: tool)
        for x in 5...25 {
            try painter.append([point(Float(max(5,x-1)),12), point(Float(x),12)], stroke: rub)
        }
        check(try painter.pixels() == together, "Rubbing depends on input batching: \(tool)")
        check(together.allSatisfy { $0.isFinite && (0...1).contains($0) }, "Rubbing produces invalid pigment")
        try painter.replay(paint)
        let before = try painter.pixels()
        rub.samples = [point(5,12,0), point(25,12,0)]
        try painter.beginStroke(rubbing: tool); try painter.append(rub.samples, stroke: rub)
        check(try painter.pixels() == before, "Zero-pressure rubbing changes paint")
        if tool == .kneaded {
            check(mass(together) < mass(before), "Kneaded eraser fails to lift pigment")
        } else {
            // Repeated passes across the boundary must not discard pigment.
            rub.samples = [point(-8,0), point(40,24)]
            for _ in 0..<3 {
                try painter.beginStroke(rubbing: tool); try painter.append(rub.samples, stroke: rub)
            }
            check(abs(mass(try painter.pixels()) - mass(before)) < 0.2, "Rubbing loses pigment at paper edges")
        }
        let document = Drawing(width: 32, height: 24, strokes: paint + [rub], grain: .coarse)
        check(try Drawing.decode(document.encoded()) == document, "Material settings lost in archive")
    }
    var version2 = try JSONSerialization.jsonObject(with: Drawing(width: 32, height: 24, strokes: paint).encoded()) as! [String: Any]
    version2["version"] = 2; version2.removeValue(forKey: "grain")
    let old = try Drawing.decode(JSONSerialization.data(withJSONObject: version2))
    check(old.grain == .legacy && old.strokes == paint, "Version 2 changed old paper or strokes")
    version2["version"] = 3; version2["grain"] = "unknown"
    check((try? Drawing.decode(JSONSerialization.data(withJSONObject: version2))) == nil, "Unknown paper accepted")
    var malformed = Drawing(width: 32, height: 24, strokes: paint)
    malformed.strokes[0].eraser = true; malformed.strokes[0].rubbing = .finger
    check((try? malformed.encoded()) == nil, "Conflicting material tool accepted")

    // Shareable visual samples, produced by the real GPU renderer.
    let preview = try MetalPainter(width: 256, height: 160, device: device, library: library)
    let directory = URL(fileURLWithPath: fixturePath).deletingLastPathComponent()
    let marks = [
        PaintStroke(color: .vermilion, radius: 20, eraser: false, samples: [point(75,25), point(75,135)]),
        PaintStroke(color: paint[1].color, radius: 20, eraser: false, samples: [point(113,25), point(113,135)])
    ]
    for grain in [PaperGrain.coarse, .medium, .fine] {
        preview.grain = grain
        try preview.replay(marks)
        try preview.png().write(to: directory.appendingPathComponent("grain-\(grain.rawValue).png"))
    }
    preview.grain = .medium
    for tool in RubbingTool.allCases {
        let rub = PaintStroke(color: .white, radius: 24, eraser: false,
            samples: [point(65,80), point(190,80)], strength: 1.5, rubbing: tool)
        try preview.replay(marks + [rub])
        try preview.png().write(to: directory.appendingPathComponent("rub-\(tool.rawValue).png"))
    }
    return checks
}

import Foundation

struct InkColor: Codable, Equatable {
    enum Channel: String, CaseIterable { case red, green, blue }
    var red: Float
    var green: Float
    var blue: Float
    // Linear-light Display P3. Encoding/decoding never quantizes to 8 bits.
    static let vermilion = InkColor(red: 0.85, green: 0.045, blue: 0.018)
    static let white = InkColor(red: 1, green: 1, blue: 1)
    var valid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }

    // The picker uses encoded Display P3 levels, while Metal blends linear
    // light. Convert at the UI boundary without an intermediate 8-bit color.
    func level(_ channel: Channel) -> Int {
        let linear: Double
        switch channel {
        case .red: linear = Double(red)
        case .green: linear = Double(green)
        case .blue: linear = Double(blue)
        }
        let v = max(0, min(1, linear))
        let encoded = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        return Int((encoded * 1023).rounded())
    }

    func settingLevel(_ level: Int, channel: Channel) -> InkColor {
        let encoded = Double(max(0, min(1023, level))) / 1023
        let linear = Float(encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4))
        var result = self
        switch channel {
        case .red: result.red = linear
        case .green: result.green = linear
        case .blue: result.blue = linear
        }
        return result
    }

    var levelDescription: String { "R \(level(.red))、G \(level(.green))、B \(level(.blue))" }
}

struct PencilSample: Codable, Equatable {
    var x: Float
    var y: Float
    var pressure: Float
    var altitude: Float
    var azimuth: Float
    var valid: Bool {
        [x, y, pressure, altitude, azimuth].allSatisfy(\.isFinite)
            && abs(x) <= 100_000 && abs(y) <= 100_000
            && (0...1).contains(pressure) && (0...(Float.pi / 2 + 0.000001)).contains(altitude)
    }
}

struct PaintStroke: Codable, Identifiable, Equatable {
    var id = UUID()
    var color: InkColor
    var radius: Float
    var eraser: Bool
    var samples: [PencilSample]
    var strength: Float = 1
}

extension PaintStroke {
    enum CodingKeys: String, CodingKey { case id, color, radius, eraser, samples, strength }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        color = try c.decode(InkColor.self, forKey: .color)
        radius = try c.decode(Float.self, forKey: .radius)
        eraser = try c.decode(Bool.self, forKey: .eraser)
        samples = try c.decode([PencilSample].self, forKey: .samples)
        strength = try c.decodeIfPresent(Float.self, forKey: .strength) ?? 1
    }
}

struct Drawing: Codable, Equatable {
    var version = 2
    var colorSpace = "linear-display-p3"
    var width = 1536
    var height = 2048
    var strokes: [PaintStroke] = []
    var dpi: Double = 300
    var paperColor: InkColor = .white
    var size: PaperSize { PaperSize(width: width, height: height, dpi: dpi) }

    func validated() throws -> Drawing {
        guard version == 2, colorSpace == "linear-display-p3", size.valid, paperColor.valid,
              strokes.count <= 10_000, Set(strokes.map(\.id)).count == strokes.count,
              strokes.reduce(0, { $0 + $1.samples.count }) <= 500_000,
              strokes.allSatisfy({ stroke in
                  stroke.color.valid && stroke.radius.isFinite && (1...100).contains(stroke.radius)
                      && stroke.strength.isFinite && (0.25...2.5).contains(stroke.strength)
                      && !stroke.samples.isEmpty && stroke.samples.allSatisfy(\.valid)
              }) else { throw DrawingError.invalidDocument }
        return self
    }

    static func decode(_ data: Data) throws -> Drawing {
        guard data.count <= 80_000_000 else { throw DrawingError.invalidDocument }
        return try JSONDecoder().decode(Drawing.self, from: data).validated()
    }

    func encoded() throws -> Data {
        _ = try validated()
        return try JSONEncoder().encode(self)
    }
}

extension Drawing {
    enum CodingKeys: String, CodingKey { case version, colorSpace, width, height, strokes, dpi, paperColor }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let format = try c.decode(Int.self, forKey: .version)
        guard format == 1 || format == 2 else { throw DrawingError.invalidDocument }
        version = 2
        colorSpace = try c.decode(String.self, forKey: .colorSpace)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        strokes = try c.decode([PaintStroke].self, forKey: .strokes)
        // Old drawings were white and had no physical resolution metadata.
        dpi = format == 1 ? 300 : try c.decode(Double.self, forKey: .dpi)
        paperColor = format == 1 ? .white : try c.decode(InkColor.self, forKey: .paperColor)
    }
}

enum DrawingError: LocalizedError {
    case invalidDocument, metalUnavailable, resource(String)
    var errorDescription: String? {
        switch self {
        case .invalidDocument: return "対応していない、または壊れた描画ファイルです。"
        case .metalUnavailable: return "この環境ではMetalを利用できません。"
        case .resource(let message): return message
        }
    }
}

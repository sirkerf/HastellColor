import Foundation

enum PaperGrain: String, Codable, CaseIterable {
    case legacy, coarse, medium, fine
    var label: String {
        switch self { case .legacy: return "従来の紙目"; case .coarse: return "粗"; case .medium: return "中"; case .fine: return "細" }
    }
    var metalIndex: UInt32 {
        switch self { case .legacy: return 0; case .coarse: return 1; case .medium: return 2; case .fine: return 3 }
    }
}

struct PaperSize: Equatable {
    let width: Int
    let height: Int
    let dpi: Double
    // A4 / 600 dpi fits. The limit bounds the three working GPU textures to
    // 800 MB; export and the OS require additional memory.
    static let maxPixels = 40_000_000
    var valid: Bool {
        (1...8192).contains(width) && (1...8192).contains(height)
            && width * height <= Self.maxPixels && dpi.isFinite && (36...1200).contains(dpi)
    }
    var widthMM: Double { Double(width) * 25.4 / dpi }
    var heightMM: Double { Double(height) * 25.4 / dpi }
    var pixelDescription: String { "\(width) × \(height) px" }
    var physicalDescription: String {
        String(format: "%.1f × %.1f mm", widthMM, heightMM) + " · \(PaperDraft.number(dpi)) dpi"
    }
}

enum PaperUse: String, CaseIterable {
    case print = "印刷用イラスト", screen = "画面用イラスト", comic = "漫画・同人誌"
}
enum PaperUnit: String, CaseIterable { case mm, px }
enum PaperPreset: String, CaseIterable {
    case a4 = "A4", a5 = "A5", b5 = "B5（JIS）", b4 = "B4（JIS）"
    case postcard = "はがき", square = "正方形（2048 px）", fullHD = "横長（1920 × 1080 px）", custom = "カスタム"
    var dimensions: (Double, Double, PaperUnit)? {
        switch self {
        case .a4: return (210, 297, .mm)
        case .a5: return (148, 210, .mm)
        case .b5: return (182, 257, .mm)
        case .b4: return (257, 364, .mm)
        case .postcard: return (100, 148, .mm)
        case .square: return (2048, 2048, .px)
        case .fullHD: return (1920, 1080, .px)
        case .custom: return nil
        }
    }
}

struct PaperDraft {
    var use: PaperUse = .print
    var preset: PaperPreset = .a4
    var unit: PaperUnit = .mm
    var width = "210"
    var height = "297"
    var dpiText = "300"
    var dpi: Double {
        get { Self.parse(dpiText) ?? .nan }
        set { dpiText = Self.number(newValue) }
    }
    var validDPI: Bool { dpi.isFinite && (36...1200).contains(dpi) }

    mutating func selectUse(_ value: PaperUse) {
        use = value
        dpi = value == .comic ? 600 : value == .screen ? 72 : 300
        selectPreset(value == .screen ? .square : .a4)
    }
    mutating func selectPreset(_ value: PaperPreset) {
        preset = value
        if let (w, h, u) = value.dimensions {
            width = Self.number(w); height = Self.number(h); unit = u
        }
    }
    mutating func selectUnit(_ value: PaperUnit) {
        guard value != unit else { return }
        guard validDPI else { return }
        if let w = Self.parse(width), let h = Self.parse(height), w.isFinite, h.isFinite {
            let factor = value == .px ? dpi / 25.4 : 25.4 / dpi
            width = Self.number(value == .px ? (w * factor).rounded() : w * factor)
            height = Self.number(value == .px ? (h * factor).rounded() : h * factor)
        }
        unit = value
    }
    mutating func swapOrientation() { swap(&width, &height) }
    static func number(_ n: Double) -> String {
        // Keep enough precision that changing units never changes a pixel.
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), n)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
    private static func parse(_ text: String) -> Double? {
        Double((text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var size: PaperSize? {
        guard let w = Self.parse(width), let h = Self.parse(height),
              w.isFinite, h.isFinite, w > 0, h > 0, validDPI else { return nil }
        let factor = unit == .mm ? dpi / 25.4 : 1
        let x = (w * factor).rounded(), y = (h * factor).rounded()
        // Check before conversion to Int, including malicious or pasted input.
        guard x >= 1, y >= 1, x <= 8192, y <= 8192 else { return nil }
        let result = PaperSize(width: Int(x), height: Int(y), dpi: dpi)
        return result.valid ? result : nil
    }
    var validationMessage: String {
        validDPI ? Self.limitMessage : "解像度は36〜1200 dpiで入力してください。小数も使えます。"
    }
    static let limitMessage = "幅・高さは1〜8192 px、合計4000万画素までです。サイズか解像度を下げてください。"
}

enum PaperPalette {
    static let colors: [(String, InkColor)] = [
        ("白", .white), ("アイボリー", .init(red: 0.94, green: 0.89, blue: 0.76)),
        ("砂色", .init(red: 0.64, green: 0.51, blue: 0.34)),
        ("灰色", .init(red: 0.42, green: 0.42, blue: 0.42)),
        ("青灰色", .init(red: 0.22, green: 0.29, blue: 0.34)),
        ("墨色", .init(red: 0.035, green: 0.04, blue: 0.045))
    ]
}

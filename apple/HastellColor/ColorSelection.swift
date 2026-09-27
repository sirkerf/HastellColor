import Foundation

// HSV is an editing coordinate system over encoded Display P3, not sRGB.
// Only an actual edit converts it back to the linear P3 drawing colour.
struct PaletteHSV {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue; self.saturation = saturation; self.brightness = brightness
    }

    init(_ color: InkColor, preserving previous: PaletteHSV? = nil) {
        let r = InkColor.encodeComponent(Double(color.red))
        let g = InkColor.encodeComponent(Double(color.green))
        let b = InkColor.encodeComponent(Double(color.blue))
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        brightness = high
        saturation = high > 0 ? delta / high : previous?.saturation ?? 0
        if delta == 0 { hue = previous?.hue ?? 0 }
        else {
            let sector = high == r ? (g - b) / delta : high == g ? (b - r) / delta + 2 : (r - g) / delta + 4
            hue = (sector / 6 + 1).truncatingRemainder(dividingBy: 1)
        }
    }

    var encodedComponents: (Double, Double, Double) {
        let h = ((hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)) * 6
        let s = min(1, max(0, saturation)), v = min(1, max(0, brightness))
        let f = h - floor(h), p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch Int(h) {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    var color: InkColor {
        let (r, g, b) = encodedComponents
        return InkColor(red: Float(InkColor.decodeComponent(r)),
            green: Float(InkColor.decodeComponent(g)), blue: Float(InkColor.decodeComponent(b)))
    }
}

struct PaletteSelection {
    private(set) var color: InkColor
    private(set) var hsv: PaletteHSV

    init(_ color: InkColor) { self.color = color; hsv = PaletteHSV(color) }

    mutating func setColor(_ value: InkColor) {
        color = value; hsv = PaletteHSV(value, preserving: hsv)
    }

    mutating func edit(hue: Double? = nil, saturation: Double? = nil, brightness: Double? = nil) {
        if let hue { hsv.hue = min(1, max(0, hue)) }
        if let saturation { hsv.saturation = min(1, max(0, saturation)) }
        if let brightness { hsv.brightness = min(1, max(0, brightness)) }
        color = hsv.color
    }

    mutating func selectClassic(x: Double, y: Double) {
        edit(saturation: x, brightness: 1 - y)
    }

    mutating func selectCircle(x: Double, y: Double) {
        let dx = 2 * x - 1, dy = 2 * y - 1, radius = hypot(dx, dy)
        let hue = radius < 0.000001 ? hsv.hue : (atan2(dy, dx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
        edit(hue: hue, saturation: min(1, radius))
    }
}

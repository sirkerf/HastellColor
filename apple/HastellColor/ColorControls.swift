import SwiftUI

private enum PaletteLayout: String, CaseIterable {
    case classic, circle, precise
    var title: String {
        switch self { case .classic: return "クラシック"; case .circle: return "サークル"; case .precise: return "RGB 10bit" }
    }
}

struct InkColorSheet: View {
    @Binding var color: InkColor
    @State private var selection: PaletteSelection
    @State private var original: InkColor
    @AppStorage("colorPickerLayout") private var layout = PaletteLayout.classic.rawValue
    @Environment(\.dismiss) private var dismiss

    init(color: Binding<InkColor>) {
        _color = color; _original = State(initialValue: color.wrappedValue)
        _selection = State(initialValue: PaletteSelection(color.wrappedValue))
    }

    private var style: PaletteLayout { PaletteLayout(rawValue: layout) ?? .classic }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Button { update { $0.setColor(original) } } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 8).fill(displayColor(original)).frame(height: 42)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.4)))
                                Text("元の色に戻す").font(.caption)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("restoreOriginalColor")
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8).fill(displayColor(color)).frame(height: 42)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.4)))
                            Text("選択中の色").font(.caption)
                        }.accessibilityElement(children: .ignore).accessibilityLabel("選択中の色")
                            .accessibilityValue(color.levelDescription)
                    }
                    Picker("色の選び方", selection: $layout) {
                        ForEach(PaletteLayout.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("paletteLayout")
                }
                if style == .precise {
                    Section {
                        channel(.red, title: "赤（R）", tint: .red)
                        channel(.green, title: "緑（G）", tint: .green)
                        channel(.blue, title: "青（B）", tint: .blue)
                    } header: { Text("Display P3・数値で調整") } footer: {
                        Text("RGB各色を0〜1023で調整します。＋と−で1段階ずつ変更できます。組み合わせは約10.7億通りです。")
                    }
                    Section {
                        ColorPicker("端末のカラーパレット", selection: colorSelection(Binding(get: { color },
                            set: { value in update { $0.setColor(value) } })), supportsOpacity: false)
                    }
                } else {
                    Section {
                        let field = PaletteField(circle: style == .circle,
                            selection: Binding(get: { selection }, set: { selection = $0; color = $0.color }))
                        if style == .circle {
                            HStack { Spacer(minLength: 0); field.aspectRatio(1, contentMode: .fit).frame(maxWidth: 230); Spacer(minLength: 0) }
                        } else { field.frame(height: 215) }
                        VStack(spacing: 8) {
                            if style == .circle { brightnessSlider }
                            hsvSlider("色相", value: selection.hsv.hue, scale: 360, suffix: "°", id: "hueSlider") { value in
                                update { $0.edit(hue: value) }
                            }
                            hsvSlider("鮮やかさ", value: selection.hsv.saturation, scale: 100, suffix: "%", id: "saturationSlider") { value in
                                update { $0.edit(saturation: value) }
                            }
                            if style == .classic { brightnessSlider }
                        }
                    } footer: {
                        Text(style == .circle ? "円周で色相、中心からの距離で鮮やかさを選びます。明るさは下のスライダーで調整します。"
                            : "色相を決め、四角の中で鮮やかさと明るさを選びます。")
                    }
                }
                Section {
                    Text("どの選び方もDisplay P3の広色域を使います。表示方法を切り替えても選択中の色は変わりません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("色を選ぶ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("完了") { dismiss() }.accessibilityIdentifier("finishChoosingColor")
            } }
        }
    }

    private func update(_ action: (inout PaletteSelection) -> Void) {
        action(&selection); color = selection.color
    }

    private var brightnessSlider: some View {
        hsvSlider("明るさ", value: selection.hsv.brightness, scale: 100, suffix: "%", id: "brightnessSlider") { value in
            update { $0.edit(brightness: value) }
        }
    }

    private func hsvSlider(_ title: String, value: Double, scale: Double, suffix: String, id: String,
                           set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 3) {
            HStack { Text(title); Spacer(); Text("\(Int((value * scale).rounded()))\(suffix)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: Binding(get: { value }, set: set), in: 0...1)
                .accessibilityLabel(title).accessibilityIdentifier(id)
        }
    }

    private func channel(_ channel: InkColor.Channel, title: String, tint: Color) -> some View {
        let level = Binding<Int>(get: { color.level(channel) }, set: { value in
            update { $0.setColor(color.settingLevel(value, channel: channel)) }
        })
        return VStack(spacing: 8) {
            HStack {
                Text(title); Spacer()
                Text("\(level.wrappedValue) / 1023").monospacedDigit().accessibilityIdentifier("\(channel.rawValue)Level")
                Stepper(title, value: level, in: 0...1023).labelsHidden().fixedSize()
                    .accessibilityIdentifier("\(channel.rawValue)Stepper")
            }
            Slider(value: Binding(get: { Double(level.wrappedValue) }, set: { level.wrappedValue = Int($0.rounded()) }),
                in: 0...1023, step: 1).tint(tint).accessibilityLabel(title).accessibilityIdentifier("\(channel.rawValue)Slider")
        }.padding(.vertical, 4)
    }
}

private struct PaletteField: View {
    let circle: Bool
    @Binding var selection: PaletteSelection
    @State private var image: CGImage?
    // Only the axis that changes the field needs a new raster. Moving the
    // selection marker keeps the cached image and the full-precision colour.
    private struct FieldKey: Hashable { var circle: Bool; var value: Double }
    private var key: FieldKey { FieldKey(circle: circle, value: circle ? selection.hsv.brightness : selection.hsv.hue) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high)
                        .accessibilityHidden(true)
                }
                Circle().fill(displayColor(selection.color)).frame(width: 17, height: 17)
                    .overlay(Circle().stroke(.black, lineWidth: 4)).overlay(Circle().stroke(.white, lineWidth: 2))
                    .position(marker(in: geometry.size)).allowsHitTesting(false)
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    let x = Double(event.location.x / max(1, geometry.size.width))
                    let y = Double(event.location.y / max(1, geometry.size.height))
                    if circle {
                        let sx = Double(event.startLocation.x / max(1, geometry.size.width)) * 2 - 1
                        let sy = Double(event.startLocation.y / max(1, geometry.size.height)) * 2 - 1
                        guard hypot(sx, sy) <= 1 else { return }
                        selection.selectCircle(x: x, y: y)
                    } else { selection.selectClassic(x: x, y: y) }
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(circle ? "サークルの色選択" : "クラシックの色選択")
                .accessibilityValue(selection.color.levelDescription)
                .accessibilityIdentifier(circle ? "circleColorField" : "classicColorField")
                .accessibilityHint("色相・鮮やかさ・明るさのスライダーでも調整できます。")
        }.padding(10)
            .task(id: key) { image = Self.makeImage(key) }
    }

    private func marker(in size: CGSize) -> CGPoint {
        let hsv = selection.hsv
        if circle {
            let angle = hsv.hue * 2 * .pi
            return CGPoint(x: (1 + hsv.saturation * cos(angle)) * size.width / 2,
                y: (1 + hsv.saturation * sin(angle)) * size.height / 2)
        }
        return CGPoint(x: hsv.saturation * size.width, y: (1 - hsv.brightness) * size.height)
    }

    private static func makeImage(_ key: FieldKey) -> CGImage? {
        let side = 384
        var components = [UInt16](repeating: 0, count: side * side * 4)
        for y in 0..<side { for x in 0..<side {
            let u = Double(x) / Double(side - 1), v = Double(y) / Double(side - 1)
            let dx = 2 * u - 1, dy = 2 * v - 1, radius = hypot(dx, dy)
            if key.circle && radius > 1 { continue }
            let hsv = key.circle
                ? PaletteHSV(hue: (atan2(dy, dx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1), saturation: radius, brightness: key.value)
                : PaletteHSV(hue: key.value, saturation: u, brightness: 1 - v)
            let (r, g, b) = hsv.encodedComponents
            let i = (y * side + x) * 4
            components[i] = UInt16((r * 65535).rounded()).bigEndian
            components[i + 1] = UInt16((g * 65535).rounded()).bigEndian
            components[i + 2] = UInt16((b * 65535).rounded()).bigEndian
            components[i + 3] = UInt16.max
        } }
        let data = components.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData), let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: side * 8,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder16Big),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

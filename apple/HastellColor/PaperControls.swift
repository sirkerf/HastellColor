import SwiftUI

struct PaperColorControls: View {
    @Binding var color: InkColor
    var body: some View {
        Section("紙の色") {
            RoundedRectangle(cornerRadius: 10).fill(displayColor(color)).frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.4)))
                .accessibilityLabel("選択中の紙色").accessibilityValue(color.levelDescription)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(PaperPalette.colors.indices, id: \.self) { i in
                        let item = PaperPalette.colors[i]
                        Button { color = item.1 } label: {
                            VStack {
                                Circle().fill(displayColor(item.1)).frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(color == item.1 ? Color.primary : .gray.opacity(0.3), lineWidth: 2))
                                Text(item.0).font(.caption)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("paperColor\(i)")
                    }
                }.padding(3)
            }
            ColorPicker("紙色を自由に選ぶ", selection: colorSelection($color), supportsOpacity: false)
            Text("紙色は描いた部分の透け方にも反映され、PNGにも含まれます。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct NewPaperSheet: View {
    @ObservedObject var store: DrawingStore
    @State private var draft = PaperDraft()
    @State private var color = InkColor.white
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("用途と規格") {
                    Picker("用途", selection: Binding(get: { draft.use }, set: { draft.selectUse($0) })) {
                        ForEach(PaperUse.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("paperUse")
                    Picker("規格", selection: Binding(get: { draft.preset }, set: { draft.selectPreset($0) })) {
                        ForEach(PaperPreset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("paperPreset")
                    if draft.use == .comic {
                        Text("漫画用は600 dpiを初期値にしています。現在はカラーの単一ページです。トンボ・塗り足し・コマ枠・網点・複数ページの管理はまだありません。入稿先の指定に合わせて寸法を設定してください。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("寸法と解像度") {
                    Picker("入力単位", selection: Binding(get: { draft.unit }, set: { draft.selectUnit($0) })) {
                        ForEach(PaperUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    dimension("幅", value: $draft.width, id: "paperWidth")
                    dimension("高さ", value: $draft.height, id: "paperHeight")
                    Button("縦横を入れ替える", systemImage: "arrow.triangle.2.circlepath") { draft.swapOrientation() }
                    Picker("解像度", selection: $draft.dpi) {
                        ForEach([72.0, 150, 300, 350, 600, 1200], id: \.self) { Text("\(Int($0)) dpi").tag($0) }
                    }.accessibilityIdentifier("paperDPI")
                    if let size = draft.size {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(size.pixelDescription).monospacedDigit()
                            Text(size.physicalDescription).monospacedDigit().foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("newPaperDimensions")
                    } else {
                        Text(PaperDraft.limitMessage).foregroundStyle(.red)
                    }
                    Text("mmからpxへの換算では端数を丸めます。mm表示は実際の画素数とdpiから計算した値です。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                PaperColorControls(color: $color)
                Section {
                    Text("今の作品に線がある場合は、自動保存と同じ場所に控えを残してから新しい用紙に切り替えます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新しい用紙").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        if let size = draft.size {
                            store.newDrawing(size: size, paperColor: color)
                            dismiss()
                        }
                    }.disabled(draft.size == nil).accessibilityIdentifier("createPaper")
                }
            }
        }
    }
    private func dimension(_ title: String, value: Binding<String>, id: String) -> some View {
        HStack {
            Text(title)
            TextField(title, text: Binding(get: { value.wrappedValue }, set: {
                value.wrappedValue = $0; draft.preset = .custom
            })).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
            Text(draft.unit.rawValue).foregroundStyle(.secondary)
        }
    }
}

struct PaperSettingsSheet: View {
    @ObservedObject var store: DrawingStore
    @State private var color: InkColor
    @Environment(\.dismiss) private var dismiss
    init(store: DrawingStore) {
        self.store = store
        _color = State(initialValue: store.drawing.paperColor)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("用紙の寸法") {
                    Text(store.drawing.size.pixelDescription)
                    Text(store.drawing.size.physicalDescription)
                    Text("別のサイズで描くには、ファイルから「新しい用紙」を選んでください。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                PaperColorControls(color: $color)
            }
            .navigationTitle("用紙の設定").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") { store.setPaperColor(color); dismiss() }.accessibilityIdentifier("applyPaperColor")
                }
            }
        }
    }
}

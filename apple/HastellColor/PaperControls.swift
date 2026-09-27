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

struct PaperGrainControls: View {
    @Binding var grain: PaperGrain
    var includeLegacy = false
    var body: some View {
        Section("紙目") {
            Picker("紙目", selection: $grain) {
                ForEach(PaperGrain.allCases.filter { includeLegacy || $0 != .legacy }, id: \.self) {
                    Text($0.label).tag($0)
                }
            }.pickerStyle(.segmented).accessibilityIdentifier("paperGrain")
            Text("粗は凹凸が大きく深く、細は滑らかに色が付きます。変更は描いた線にも反映され、取り消せます。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct NewPaperSheet: View {
    @ObservedObject var store: DrawingStore
    @State private var draft = PaperDraft()
    @State private var color = InkColor.white
    @State private var grain: PaperGrain = .medium
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
                    }.pickerStyle(.segmented).disabled(!draft.validDPI).accessibilityIdentifier("paperUnit")
                    dimension("幅", value: $draft.width, id: "paperWidth")
                    dimension("高さ", value: $draft.height, id: "paperHeight")
                    Button("縦横を入れ替える", systemImage: "arrow.triangle.2.circlepath") { draft.swapOrientation() }
                    HStack {
                        Text("解像度")
                        TextField("dpi", text: $draft.dpiText).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).accessibilityIdentifier("paperDPI")
                        Text("dpi").foregroundStyle(.secondary)
                        Menu {
                            ForEach([72.0, 150, 300, 350, 600, 1200], id: \.self) { dpi in
                                Button("\(Int(dpi)) dpi") { draft.dpi = dpi }
                            }
                        } label: { Image(systemName: "list.bullet") }
                            .accessibilityLabel("よく使う解像度")
                    }
                    if let size = draft.size {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(size.pixelDescription).monospacedDigit()
                            Text(size.physicalDescription).monospacedDigit().foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("newPaperDimensions")
                    } else {
                        Text(draft.validationMessage).foregroundStyle(.red).accessibilityIdentifier("paperValidation")
                    }
                    Text("解像度は36〜1200 dpiで自由入力できます。mm入力では解像度に応じて画素数が変わり、px入力では画素数を保って実寸が変わります。画素数の端数は丸めます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                PaperGrainControls(grain: $grain)
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
                            store.newDrawing(size: size, paperColor: color, grain: grain)
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
    @State private var grain: PaperGrain
    @Environment(\.dismiss) private var dismiss
    init(store: DrawingStore) {
        self.store = store
        _color = State(initialValue: store.drawing.paperColor)
        _grain = State(initialValue: store.drawing.grain)
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
                PaperGrainControls(grain: $grain, includeLegacy: store.drawing.grain == .legacy)
                PaperColorControls(color: $color)
            }
            .navigationTitle("用紙の設定").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") { store.setPaper(color: color, grain: grain); dismiss() }.accessibilityIdentifier("applyPaperColor")
                }
            }
        }
    }
}

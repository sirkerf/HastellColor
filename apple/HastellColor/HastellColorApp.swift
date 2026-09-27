import SwiftUI
import UniformTypeIdentifiers

@main
struct HastellColorApp: App {
    @StateObject private var store = DrawingStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup { StudioView(store: store) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { store.saveNow() }
            }
    }
}

struct StudioView: View {
    @ObservedObject var store: DrawingStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmingClear = false
    @State private var choosingColor = false
    @State private var newPaper = false
    @State private var paperSettings = false
    @State private var exportFile = DrawingFile(data: Data())
    @State private var exportType = UTType.hastellDrawing
    private let palette: [InkColor] = [
        .init(red: 0.012, green: 0.016, blue: 0.022), .vermilion,
        .init(red: 1, green: 0.3, blue: 0.015), .init(red: 1, green: 0.76, blue: 0.04),
        .init(red: 0.035, green: 0.36, blue: 0.14), .init(red: 0.015, green: 0.28, blue: 0.58),
        .init(red: 0.035, green: 0.07, blue: 0.65), .init(red: 0.34, green: 0.055, blue: 0.48),
        .init(red: 0.42, green: 0.15, blue: 0.055), .init(red: 1, green: 1, blue: 1)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Picker("画材", selection: $store.tool) {
                        ForEach(DrawingTool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).frame(width: 160, alignment: .leading)
                        .accessibilityIdentifier("drawingTool")
                    Image(systemName: "circle.fill").font(.system(size: 9))
                    Slider(value: $store.radius, in: 1...60).frame(maxWidth: 180).accessibilityLabel("ブラシの半径")
                    Text("\(Int(store.radius)) px").monospacedDigit().frame(width: 52, alignment: .trailing)
                    Spacer()
                    Text(store.saveStatus).font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.vertical, 12)
                HStack(spacing: 12) {
                    Text(store.tool.rubbing == nil ? "塗りの強さ" : "こする強さ").font(.caption)
                    Slider(value: $store.strength, in: 0.25...2.5, step: 0.05)
                        .frame(maxWidth: 160).disabled(store.eraser)
                        .accessibilityLabel(store.tool.rubbing == nil ? "塗りの強さ" : "こする強さ").accessibilityIdentifier("pigmentStrength")
                    Text("\(Int((store.strength * 100).rounded())) %").font(.caption).monospacedDigit()
                    Spacer(minLength: 8)
                    Button { paperSettings = true } label: {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(store.drawing.size.pixelDescription) · 紙目 \(store.drawing.grain.label)")
                            Text(store.drawing.size.physicalDescription)
                        }.font(.caption).monospacedDigit()
                    }.disabled(store.isDrawing).accessibilityIdentifier("paperSettings")
                        .accessibilityValue(store.drawing.paperColor.levelDescription)
                }.padding(.horizontal, 24).padding(.bottom, 10)
                GeometryReader { geometry in
                    PencilCanvas(store: store)
                        .aspectRatio(CGFloat(store.drawing.width) / CGFloat(store.drawing.height), contentMode: .fit)
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
                        .padding(24)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }.background(Color(red: 0.87, green: 0.86, blue: 0.83))
                HStack(spacing: 16) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(palette.indices, id: \.self) { i in
                                Button {
                                    store.color = palette[i]
                                    store.eraser = false
                                } label: {
                                    Circle().fill(displayColor(palette[i])).frame(width: 30, height: 30)
                                        .overlay(Circle().stroke(.gray.opacity(0.3), lineWidth: 1))
                                        .padding(4)
                                        .overlay(Circle().stroke(store.color == palette[i] ? Color.primary : .clear, lineWidth: 2))
                                }.accessibilityLabel(["墨", "朱", "橙", "黄", "緑", "水色", "青", "紫", "茶", "白"][i])
                            }
                        }.padding(3)
                    }.frame(maxWidth: 560)
                    Button { choosingColor = true } label: {
                        HStack(spacing: 8) {
                            Circle().fill(displayColor(store.color)).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.gray.opacity(0.4), lineWidth: 1))
                            Text("色を選ぶ")
                        }
                    }.buttonStyle(.bordered).fixedSize()
                        .accessibilityIdentifier("chooseColor")
                        .accessibilityValue(store.color.levelDescription)
                }.padding(16)
            }
            .navigationTitle("HastellColor")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $choosingColor) {
                InkColorSheet(color: Binding(get: { store.color }, set: {
                    store.color = $0
                    store.eraser = false
                }))
            }
            .sheet(isPresented: $newPaper) { NewPaperSheet(store: store) }
            .sheet(isPresented: $paperSettings) { PaperSettingsSheet(store: store) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("取り消す", systemImage: "arrow.uturn.backward") { store.undo() }
                        .disabled(!store.canUndo || store.isDrawing).keyboardShortcut("z", modifiers: .command)
                    Button("やり直す", systemImage: "arrow.uturn.forward") { store.redo() }
                        .disabled(!store.canRedo || store.isDrawing).keyboardShortcut("z", modifiers: [.command, .shift])
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        #if !targetEnvironment(macCatalyst)
                        Toggle("指でも描く", isOn: $store.fingerDrawing)
                        Toggle("指でこする", isOn: $store.fingerSmudging)
                        #endif
                        Toggle("筆圧を固定（USB-C Pencil用）", isOn: $store.fixedPressure)
                    } label: { Label("入力設定", systemImage: "pencil.tip.crop.circle") }
                    Menu {
                        Button("新しい用紙", systemImage: "doc.badge.plus") { newPaper = true }
                            .keyboardShortcut("n", modifiers: .command)
                        Button("用紙の設定", systemImage: "rectangle.portrait") { paperSettings = true }
                        Divider()
                        Button("作品を保存", systemImage: "square.and.arrow.up") { export(png: false) }
                        Button("PNGを書き出す（16 bit / P3）", systemImage: "photo") { export(png: true) }
                        Button("作品を開く", systemImage: "folder") { importing = true }
                        Button("キャンバスを空にする", systemImage: "trash", role: .destructive) { confirmingClear = true }
                    } label: { Label("ファイル", systemImage: "ellipsis.circle") }
                    .disabled(store.isDrawing)
                }
            }
            .fileExporter(isPresented: $exporting, document: exportFile, contentType: exportType,
                defaultFilename: exportType == .png ? "HastellColor.png" : "HastellColor.hastell") { result in
                    if case .failure(let error) = result { store.error = error.localizedDescription }
                }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.hastellDrawing, .json]) { result in
                switch result {
                case .success(let url): store.open(url)
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .confirmationDialog("キャンバスを空にしますか？", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("空にする（取り消し可能）", role: .destructive) { store.clear() }
            }
            .alert("処理を完了できませんでした", isPresented: Binding(get: { store.error != nil },
                set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }.tint(colorScheme == .dark ? Color(red: 0.65, green: 0.83, blue: 0.77)
            : Color(red: 0.22, green: 0.31, blue: 0.29))
    }

    private func export(png: Bool) {
        do {
            exportFile = try png ? store.exportPNG() : store.exportDrawing()
            exportType = png ? .png : .hastellDrawing
            exporting = true
        } catch { store.error = error.localizedDescription }
    }
}

func displayColor(_ ink: InkColor) -> Color {
    let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    let color = CGColor(colorSpace: space, components: [CGFloat(ink.red), CGFloat(ink.green), CGFloat(ink.blue), 1])!
    return Color(cgColor: color)
}

func colorSelection(_ color: Binding<InkColor>) -> Binding<Color> {
    Binding(get: { displayColor(color.wrappedValue) }, set: { selected in
        let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        if let converted = UIColor(selected).cgColor.converted(to: space, intent: .defaultIntent, options: nil),
           let c = converted.components, c.count >= 3 {
            color.wrappedValue = InkColor(red: Float(max(0, min(1, c[0]))),
                green: Float(max(0, min(1, c[1]))), blue: Float(max(0, min(1, c[2]))))
        }
    })
}

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let hastellDrawing = UTType(exportedAs: "org.hastellcolor.drawing", conformingTo: .json)
}

struct DrawingFile: FileDocument {
    static var readableContentTypes: [UTType] { [.hastellDrawing, .json, .png] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw DrawingError.invalidDocument }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
final class DrawingStore: ObservableObject {
    @Published private(set) var drawing = Drawing()
    @Published private(set) var revision = 0
    private(set) var documentID = UUID()
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var color = InkColor.vermilion
    @Published var radius: Double = 14
    @Published var strength: Double = 1
    @Published var tool: DrawingTool = .pastel
    var eraser: Bool {
        get { tool == .eraser }
        set { tool = newValue ? .eraser : .pastel }
    }
    @Published var fingerSmudging = false
    @Published var fingerDrawing = false
    @Published var fixedPressure = false
    @Published var isDrawing = false
    @Published var error: String?
    @Published var saveStatus = "自動保存"
    var painter: MetalPainter?
    var finishInput: (() -> Void)?
    private var undoStack: [Drawing] = []
    private var redoStack: [Drawing] = []
    private let saveQueue = DispatchQueue(label: "org.hastellcolor.autosave", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private let autosave: URL
    private var saveGeneration = 0
    private var preserveUnreadableAutosave = false

    init() {
        #if targetEnvironment(macCatalyst)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HastellColor", isDirectory: true)
        #else
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        autosave = directory.appendingPathComponent("Autosave.hastell")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { self.error = error.localizedDescription }
        if FileManager.default.fileExists(atPath: autosave.path) {
            do { drawing = try Drawing.decode(Data(contentsOf: autosave)) }
            catch {
                preserveUnreadableAutosave = true
                self.error = "自動保存を復元できませんでした。\n\(error.localizedDescription)"
            }
        }
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        fingerDrawing = true
        #endif
    }

    private func remember() {
        undoStack.append(drawing)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func changed() {
        revision += 1
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        scheduleSave()
    }

    func commit(_ stroke: PaintStroke) {
        guard !stroke.samples.isEmpty else { return }
        remember()
        drawing.strokes.append(stroke)
        changed()
    }

    func correct(strokeID: UUID, index: Int, sample: PencilSample) {
        guard let i = drawing.strokes.firstIndex(where: { $0.id == strokeID }),
              drawing.strokes[i].samples.indices.contains(index) else { return }
        drawing.strokes[i].samples[index] = sample
        // Undo snapshots may include this stroke too. Keep late Pencil estimates
        // consistent when the user subsequently redoes a corrected stroke.
        for stackIndex in undoStack.indices {
            if let s = undoStack[stackIndex].strokes.firstIndex(where: { $0.id == strokeID }),
               undoStack[stackIndex].strokes[s].samples.indices.contains(index) {
                undoStack[stackIndex].strokes[s].samples[index] = sample
            }
        }
        changed()
    }

    func undo() {
        finishInput?()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(drawing)
        drawing = previous
        changed()
    }

    func redo() {
        finishInput?()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(drawing)
        drawing = next
        changed()
    }

    func clear() {
        finishInput?()
        guard !drawing.strokes.isEmpty else { return }
        remember()
        drawing.strokes = []
        changed()
    }

    func open(_ url: URL) {
        finishInput?()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let replacement = try Drawing.decode(Data(contentsOf: url))
            try backupCurrent()
            documentID = UUID()
            drawing = replacement
            undoStack = []
            redoStack = []
            changed()
        } catch { self.error = error.localizedDescription }
    }

    private func backupCurrent() throws {
        guard !drawing.strokes.isEmpty else { return }
        let backup = autosave.deletingLastPathComponent()
            .appendingPathComponent("BeforeReplace-\(UUID().uuidString).hastell")
        try drawing.encoded().write(to: backup, options: .atomic)
    }

    func newDrawing(size: PaperSize, paperColor: InkColor, grain: PaperGrain = .medium) {
        finishInput?()
        do {
            let replacement = try Drawing(width: size.width, height: size.height,
                dpi: size.dpi, paperColor: paperColor, grain: grain).validated()
            try backupCurrent()
            drawing = replacement
            documentID = UUID()
            undoStack = []; redoStack = []
            changed()
        } catch { self.error = error.localizedDescription }
    }

    func setPaper(color: InkColor, grain: PaperGrain) {
        finishInput?()
        guard color.valid, drawing.paperColor != color || drawing.grain != grain else { return }
        remember()
        drawing.paperColor = color
        drawing.grain = grain
        changed()
    }

    func saveNow() {
        finishInput?()
        pendingSave?.cancel()
        saveGeneration += 1
        guard prepareAutosave() else { return }
        let snapshot = drawing
        let url = autosave
        // Finish an atomic save before the scene can be suspended. This serial
        // queue also prevents an older save from overwriting a newer one.
        do {
            try saveQueue.sync { try snapshot.encoded().write(to: url, options: .atomic) }
            saveStatus = "保存済み"
        } catch {
            saveStatus = "保存できませんでした"
            self.error = error.localizedDescription
        }
    }

    private func prepareAutosave() -> Bool {
        guard preserveUnreadableAutosave else { return true }
        do {
            let backup = autosave.deletingLastPathComponent()
                .appendingPathComponent("Unreadable-\(UUID().uuidString).hastell")
            try FileManager.default.copyItem(at: autosave, to: backup)
            preserveUnreadableAutosave = false
            return true
        } catch {
            saveStatus = "保存できませんでした"
            self.error = error.localizedDescription
            return false
        }
    }

    private func scheduleSave(delay: TimeInterval = 0.3) {
        pendingSave?.cancel()
        guard prepareAutosave() else { return }
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = drawing
        let url = autosave
        saveStatus = "保存中…"
        let work = DispatchWorkItem { [weak self] in
            do {
                try snapshot.encoded().write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    guard let self, self.saveGeneration == generation else { return }
                    self.saveStatus = "保存済み"
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    guard let self, self.saveGeneration == generation else { return }
                    self.saveStatus = "保存できませんでした"
                    self.error = message
                }
            }
        }
        pendingSave = work
        saveQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func exportDrawing() throws -> DrawingFile {
        finishInput?()
        return DrawingFile(data: try drawing.encoded())
    }

    func exportPNG() throws -> DrawingFile {
        finishInput?()
        guard let painter else { throw DrawingError.metalUnavailable }
        guard painter.width == drawing.width, painter.height == drawing.height else {
            throw DrawingError.resource("用紙を準備しています。少し待ってから書き出してください。")
        }
        painter.paperColor = drawing.paperColor
        painter.dpi = drawing.dpi
        painter.grain = drawing.grain
        try painter.replay(drawing.strokes)
        return DrawingFile(data: try painter.png())
    }
}

import SwiftUI
import MetalKit

struct PencilCanvas: UIViewRepresentable {
    @ObservedObject var store: DrawingStore
    func makeUIView(context: Context) -> PencilMetalView { PencilMetalView(store: store) }
    func updateUIView(_ view: PencilMetalView, context: Context) {
        view.synchronizeDocument()
    }
}

final class PencilMetalView: MTKView, MTKViewDelegate {
    private let store: DrawingStore
    private var painter: MetalPainter?
    private var screenPipeline: MTLRenderPipelineState?
    private var activeTouch: UITouch?
    private var active: PaintStroke?
    private var renderedCount = 0
    private var revision = -1
    private var rebuild = true
    private var documentID: UUID?
    private struct Estimate {
        var strokeID: UUID
        var sampleIndex: Int
        var properties: UITouch.Properties
        var sample: PencilSample
        var size: CGSize
        var fixedPressure: Bool
    }
    private var estimates: [NSNumber: Estimate] = [:]

    init(store: DrawingStore) {
        self.store = store
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = .white
        // Both the drawable and working canvas carry linear Display P3 values.
        // Color matching is performed by Core Animation for the actual display.
        colorPixelFormat = .rgba16Float
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        clearColor = MTLClearColorMake(1, 1, 1, 1)
        isPaused = true
        enableSetNeedsDisplay = true
        preferredFramesPerSecond = 120
        delegate = self
        isAccessibilityElement = true
        accessibilityLabel = "お絵描きキャンバス"
        accessibilityIdentifier = "drawingCanvas"
        store.finishInput = { [weak self] in self?.finishStroke() }
        synchronizeDocument()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func synchronizeDocument() {
        accessibilityValue = "\(store.drawing.strokes.count)本の線"
        guard let device else {
            report(DrawingError.metalUnavailable)
            return
        }
        if documentID != store.documentID {
            estimates.removeAll()
            documentID = store.documentID
        }
        if painter?.width != store.drawing.width || painter?.height != store.drawing.height {
            active = nil
            activeTouch = nil
            estimates.removeAll()
            // Release the old paper before allocating a print-resolution one.
            self.painter = nil
            store.painter = nil
            screenPipeline = nil
            do {
                guard let library = device.makeDefaultLibrary() else { throw DrawingError.metalUnavailable }
                let painter = try MetalPainter(width: store.drawing.width, height: store.drawing.height,
                    device: device, library: library)
                painter.onError = { [weak store] message in store?.error = message }
                self.painter = painter
                store.painter = painter
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "canvasVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "canvasFragment")
                descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
                screenPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                rebuild = true
            } catch { report(error) }
        }
        painter?.paperColor = store.drawing.paperColor
        painter?.dpi = store.drawing.dpi
        if revision != store.revision { rebuild = true }
        setNeedsDisplay()
    }

    private func report(_ error: Error) {
        let message = error.localizedDescription
        DispatchQueue.main.async { [weak store] in store?.error = message }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { setNeedsDisplay() }

    func draw(in view: MTKView) {
        guard let painter, let screenPipeline else { return }
        do {
            try updatePaint()
            guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
                  let command = painter.queue.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.setRenderPipelineState(screenPipeline)
            encoder.setFragmentTexture(painter.image, index: 0)
            let paper = store.drawing.paperColor
            var background = SIMD4<Float>(paper.red, paper.green, paper.blue, 1)
            encoder.setFragmentBytes(&background, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        } catch { report(error) }
    }

    private func updatePaint() throws {
        guard let painter else { throw DrawingError.metalUnavailable }
        if rebuild || revision != store.revision {
            try painter.replay(store.drawing.strokes)
            renderedCount = 0
            rebuild = false
            revision = store.revision
        }
        if let active, active.samples.count > renderedCount {
            if renderedCount == 0 { try painter.beginStroke() }
            for start in stride(from: renderedCount, to: active.samples.count, by: 64) {
                let end = min(active.samples.count, start + 64)
                try painter.append(Array(active.samples[max(0, start - 1)..<end]), stroke: active)
            }
            renderedCount = active.samples.count
        }
    }

    private func sample(_ touch: UITouch, size: CGSize, fixed: Bool) -> PencilSample {
        let point = touch.preciseLocation(in: self)
        let pencil = touch.type == .pencil
        let pressure = pencil && !fixed && touch.maximumPossibleForce > 0
            ? touch.force / touch.maximumPossibleForce : 0.7
        return PencilSample(x: Float(point.x / max(1, size.width)) * Float(store.drawing.width),
            y: Float(point.y / max(1, size.height)) * Float(store.drawing.height),
            pressure: Float(max(0, min(1, pressure))),
            altitude: pencil ? min(Float.pi / 2, Float(touch.altitudeAngle)) : .pi / 2,
            azimuth: pencil ? Float(touch.azimuthAngle(in: self)) : 0)
    }

    private func append(_ touch: UITouch, event: UIEvent?) {
        guard var stroke = active else { return }
        for item in event?.coalescedTouches(for: touch) ?? [touch] {
            let point = sample(item, size: bounds.size, fixed: store.fixedPressure)
            guard point.valid else { continue }
            // Coalesced arrays include the event's touch. Do not append it twice.
            let index = stroke.samples.count
            stroke.samples.append(point)
            if let key = item.estimationUpdateIndex, !item.estimatedPropertiesExpectingUpdates.isEmpty {
                estimates[key] = Estimate(strokeID: stroke.id, sampleIndex: index,
                    properties: item.estimatedPropertiesExpectingUpdates, sample: point,
                    size: bounds.size, fixedPressure: store.fixedPressure)
            }
        }
        active = stroke
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Prefer Pencil and ignore palm/finger touches in the default mode.
        if let pencil = touches.first(where: { $0.type == .pencil }), activeTouch?.type != .pencil {
            if active != nil { cancelStroke() }
            start(pencil, event: event)
        } else if activeTouch == nil, store.fingerDrawing, let touch = touches.first {
            start(touch, event: event)
        }
    }

    private func start(_ touch: UITouch, event: UIEvent?) {
        activeTouch = touch
        active = PaintStroke(color: store.color, radius: Float(store.radius), eraser: store.eraser, samples: [], strength: Float(store.strength))
        renderedCount = 0
        store.isDrawing = true
        append(touch, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        append(activeTouch, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        append(activeTouch, event: event)
        finishStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        cancelStroke()
    }

    private func finishStroke() {
        guard let stroke = active else { return }
        // Flush the final touch even if no display frame arrived yet. Retain the
        // finished GPU image; ordinary pen lifts must not replay the document.
        do { try updatePaint() } catch { report(error); rebuild = true }
        active = nil
        activeTouch = nil
        store.isDrawing = false
        store.commit(stroke)
        revision = store.revision
        setNeedsDisplay()
    }

    private func cancelStroke() {
        if let id = active?.id { estimates = estimates.filter { $0.value.strokeID != id } }
        active = nil
        activeTouch = nil
        store.isDrawing = false
        rebuild = true
        setNeedsDisplay()
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let key = touch.estimationUpdateIndex, var entry = estimates[key] else { continue }
            let update = sample(touch, size: entry.size, fixed: entry.fixedPressure)
            // Update only properties originally marked as estimated. Other
            // fields of a delayed UITouch can belong to a newer event.
            if entry.properties.contains(.location) { entry.sample.x = update.x; entry.sample.y = update.y }
            if entry.properties.contains(.force) { entry.sample.pressure = update.pressure }
            if entry.properties.contains(.altitude) { entry.sample.altitude = update.altitude }
            if entry.properties.contains(.azimuth) { entry.sample.azimuth = update.azimuth }
            guard entry.sample.valid else { continue }
            if active?.id == entry.strokeID, active!.samples.indices.contains(entry.sampleIndex) {
                active!.samples[entry.sampleIndex] = entry.sample
                rebuild = true
            } else {
                store.correct(strokeID: entry.strokeID, index: entry.sampleIndex, sample: entry.sample)
            }
            entry.properties = touch.estimatedPropertiesExpectingUpdates
            estimates[key] = entry.properties.isEmpty ? nil : entry
        }
        setNeedsDisplay()
    }
}

import Foundation
import MetalKit
import ImageIO
import UniformTypeIdentifiers

// Serialized by the main thread in the app. The command queue orders all GPU
// writes, including replay, export, and screen presentation.
final class MetalPainter {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let width: Int
    let height: Int
    let image: MTLTexture
    private let base: MTLTexture
    private let contact: MTLTexture
    private let paintPipeline: MTLComputePipelineState
    private let clearPipeline: MTLComputePipelineState
    var paperColor: InkColor = .white
    var dpi: Double = 300
    var onError: ((String) -> Void)?

    init(width: Int, height: Int, device: MTLDevice, library: MTLLibrary) throws {
        self.device = device
        self.library = library
        self.width = width
        self.height = height
        guard let queue = device.makeCommandQueue(),
              let paint = library.makeFunction(name: "paint"),
              let clear = library.makeFunction(name: "clearCanvas") else {
            throw DrawingError.resource("Metalの描画プログラムを読み込めませんでした。")
        }
        self.queue = queue
        paintPipeline = try device.makeComputePipelineState(function: paint)
        clearPipeline = try device.makeComputePipelineState(function: clear)
        func texture(_ format: MTLPixelFormat) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .shaderWrite]
            guard let result = device.makeTexture(descriptor: descriptor) else {
                throw DrawingError.resource("キャンバス用のメモリを確保できませんでした。")
            }
            return result
        }
        image = try texture(.rgba16Float)
        base = try texture(.rgba16Float)
        contact = try texture(.r32Float)
        try reset()
    }

    private func command() throws -> MTLCommandBuffer {
        guard let command = queue.makeCommandBuffer() else { throw DrawingError.metalUnavailable }
        command.addCompletedHandler { [weak self] buffer in
            if let error = buffer.error {
                let message = error.localizedDescription
                DispatchQueue.main.async { self?.onError?(message) }
            }
        }
        return command
    }

    private func clear(_ texture: MTLTexture, in command: MTLCommandBuffer) throws {
        guard let encoder = command.makeComputeCommandEncoder() else { throw DrawingError.metalUnavailable }
        encoder.setComputePipelineState(clearPipeline)
        encoder.setTexture(texture, index: 0)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
    }

    func reset() throws {
        let buffer = try command()
        try clear(image, in: buffer)
        buffer.commit()
    }

    func beginStroke() throws {
        let buffer = try command()
        guard let blit = buffer.makeBlitCommandEncoder() else { throw DrawingError.metalUnavailable }
        blit.copy(from: image, to: base)
        blit.endEncoding()
        try clear(contact, in: buffer)
        buffer.commit()
    }

    // Every batch includes its predecessor. Maximum contact is retained for the
    // complete stroke, so coalesced input doesn't darken a stroke by overdraw.
    func append(_ samples: [PencilSample], stroke: PaintStroke) throws {
        guard !samples.isEmpty else { return }
        let points = samples.count == 1 ? [samples[0], samples[0]] : samples
        let margin = stroke.radius * 3 + 2
        let x0 = max(0, min(width, Int(floor(points.map(\.x).min()! - margin))))
        let y0 = max(0, min(height, Int(floor(points.map(\.y).min()! - margin))))
        let x1 = max(0, min(width, Int(ceil(points.map(\.x).max()! + margin))))
        let y1 = max(0, min(height, Int(ceil(points.map(\.y).max()! + margin))))
        guard x1 > x0, y1 > y0 else { return }
        let values: [SIMD4<Float>] = points.flatMap {
            [SIMD4($0.x, $0.y, $0.pressure, $0.altitude), SIMD4($0.azimuth, 0, 0, 0)]
        }
        guard let input = device.makeBuffer(bytes: values, length: values.count * MemoryLayout<SIMD4<Float>>.stride) else {
            throw DrawingError.resource("ペン入力用のメモリを確保できませんでした。")
        }
        struct Parameters {
            var colorRadius: SIMD4<Float>
            var controls: SIMD4<Float>
            var region: SIMD4<UInt32>
            var counts: SIMD4<UInt32>
        }
        var params = Parameters(colorRadius: SIMD4(stroke.color.red, stroke.color.green, stroke.color.blue, stroke.radius),
            controls: SIMD4(stroke.strength, 0, 0, 0),
            region: SIMD4(UInt32(x0), UInt32(y0), UInt32(x1 - x0), UInt32(y1 - y0)),
            counts: SIMD4(UInt32(points.count), UInt32(width), UInt32(height), stroke.eraser ? 1 : 0))
        let buffer = try command()
        guard let encoder = buffer.makeComputeCommandEncoder() else { throw DrawingError.metalUnavailable }
        encoder.setComputePipelineState(paintPipeline)
        encoder.setTexture(base, index: 0)
        encoder.setTexture(image, index: 1)
        encoder.setTexture(contact, index: 2)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<Parameters>.stride, index: 1)
        encoder.dispatchThreads(MTLSize(width: x1 - x0, height: y1 - y0, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        buffer.commit()
    }

    func replay(_ strokes: [PaintStroke]) throws {
        try reset()
        for stroke in strokes {
            try beginStroke()
            // Bound GPU work per dispatch; maintain the predecessor across batches.
            for start in stride(from: 0, to: stroke.samples.count, by: 64) {
                let lower = max(0, start - 1)
                let upper = min(stroke.samples.count, start + 64)
                try append(Array(stroke.samples[lower..<upper]), stroke: stroke)
            }
        }
    }

    private func readback() throws -> (MTLBuffer, Int) {
        let rowBytes = ((width * 8 + 255) / 256) * 256
        let byteCount = rowBytes * height
        guard let staging = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
            throw DrawingError.resource("画像の書き出し用メモリを確保できませんでした。")
        }
        let buffer = try command()
        guard let blit = buffer.makeBlitCommandEncoder() else { throw DrawingError.metalUnavailable }
        blit.copy(from: image, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1), to: staging, destinationOffset: 0,
            destinationBytesPerRow: rowBytes, destinationBytesPerImage: byteCount)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        if let error = buffer.error { throw error }
        return (staging, rowBytes)
    }

    // Float16 is unavailable on some Intel macOS deployment targets. Decode
    // IEEE binary16 explicitly so both Catalyst architectures share readback.
    static func linearHalf(_ bits: UInt16) -> Float {
        let sign: Float = bits & 0x8000 == 0 ? 1 : -1
        let exponent = Int((bits >> 10) & 31), fraction = Float(bits & 1023)
        if exponent == 0 { return sign * fraction * (1 / 16_777_216) }
        if exponent == 31 { return fraction == 0 ? sign * .infinity : .nan }
        return Float(bitPattern: (UInt32(bits & 0x8000) << 16) | (UInt32(exponent + 112) << 23) | (UInt32(bits & 1023) << 13))
    }

    func pixels() throws -> [Float] {
        let (staging, rowBytes) = try readback()
        let halves = staging.contents().bindMemory(to: UInt16.self, capacity: rowBytes * height / 2)
        return (0..<(width * height * 4)).map { (index: Int) -> Float in
            let row = index / (width * 4), column = index % (width * 4)
            return Self.linearHalf(halves[row * rowBytes / 2 + column])
        }
    }

    // 16-bit/channel PNG tagged Display P3. Rows remain top-to-bottom; use an
    // explicit conversion instead of UIKit's default 8-bit image context.
    func png() throws -> Data {
        let (staging, rowBytes) = try readback()
        let source = staging.contents().bindMemory(to: UInt16.self, capacity: rowBytes * height / 2)
        // Convert straight into the output buffer. Avoid a full Float32 canvas
        // plus two additional copies of the 16-bit canvas for print-size papers.
        var data = Data(count: width * height * 8)
        func encode(_ linear: Float) -> UInt16 {
            let v = max(0, min(1, linear))
            let gamma = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
            return UInt16(max(0, min(65535, (gamma * 65535).rounded()))).bigEndian
        }
        data.withUnsafeMutableBytes { bytes in
            let output = bytes.bindMemory(to: UInt16.self)
            for y in 0..<height {
                for x in 0..<width {
                    let input = y * rowBytes / 2 + x * 4, index = (y * width + x) * 4
                    let amount = Self.linearHalf(source[input + 3])
                    output[index] = encode(paperColor.red * (1 - amount) + Self.linearHalf(source[input]) * amount)
                    output[index + 1] = encode(paperColor.green * (1 - amount) + Self.linearHalf(source[input + 1]) * amount)
                    output[index + 2] = encode(paperColor.blue * (1 - amount) + Self.linearHalf(source[input + 2]) * amount)
                    output[index + 3] = UInt16.max
                }
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                bytesPerRow: width * 8, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                    .union(.byteOrder16Big), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw DrawingError.resource("PNG画像を作成できませんでした。") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw DrawingError.resource("PNGの保存先を作成できませんでした。")
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DrawingError.resource("PNGの書き出しに失敗しました。") }
        return output as Data
    }
}

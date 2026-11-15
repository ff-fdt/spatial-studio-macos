import AppKit
import MetalKit
import SwiftUI
import simd

/// Renders the bundled photogrammetry mesh with the same camera as the canvas.
struct Mannequin: NSViewRepresentable {
    var right: SIMD3<Double>
    var up: SIMD3<Double>
    var toward: SIMD3<Double>
    var projection: SIMD4<Float>

    func makeCoordinator() -> HeadRenderer { HeadRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.depthStencilPixelFormat = .depth32Float
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        if context.coordinator.orient(right: right, up: up, toward: toward, projection: projection) {
            view.needsDisplay = true
        }
    }
}

@MainActor
final class HeadRenderer: NSObject, MTKViewDelegate {
    let device = MTLCreateSystemDefaultDevice()
    private var encoder: MTLRenderPipelineState?
    private var queue: MTLCommandQueue?
    private var depth: MTLDepthStencilState?
    private var vertices: MTLBuffer?
    private var indices: MTLBuffer?
    private var indexCount = 0
    private var basis = [SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(0, 0, 1, 0)]

    override init() {
        super.init()
        guard let device,
              let url = Bundle.module.url(forResource: "HeadScan", withExtension: "sdm", subdirectory: "Resources"),
              let model = try? Data(contentsOf: url), model.count >= 12, model.prefix(4) == Data("SDM1".utf8),
              let library = try? device.makeLibrary(source: Self.shader, options: nil) else { return }

        model.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            let vertexBytes = Int(bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian) * 24
            let triangleBytes = Int(bytes.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian) * 12
            guard vertexBytes > 0, triangleBytes > 0, 12 + vertexBytes + triangleBytes == bytes.count else { return }
            vertices = device.makeBuffer(bytes: base + 12, length: vertexBytes)
            indices = device.makeBuffer(bytes: base + 12 + vertexBytes, length: triangleBytes)
            indexCount = triangleBytes / 4
        }

        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.vertexFunction = library.makeFunction(name: "head_vertex")
        pipeline.fragmentFunction = library.makeFunction(name: "head_fragment")
        pipeline.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline.depthAttachmentPixelFormat = .depth32Float
        encoder = try? device.makeRenderPipelineState(descriptor: pipeline)
        let stencil = MTLDepthStencilDescriptor()
        stencil.depthCompareFunction = .less
        stencil.isDepthWriteEnabled = true
        depth = device.makeDepthStencilState(descriptor: stencil)
        queue = device.makeCommandQueue()
    }

    func orient(right: SIMD3<Double>, up: SIMD3<Double>, toward: SIMD3<Double>, projection: SIMD4<Float>) -> Bool {
        // The packaged scan is in right-handed space; the acoustic grid's +Z faces forwards.
        let updated = [right, up, toward].map { SIMD4(Float($0.x), Float($0.y), Float(-$0.z), 0) } + [projection]
        guard updated != basis else { return false }
        basis = updated
        return true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let encoder, let depth, let vertices, let indices, let queue,
              let display = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer(),
              let draw = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        draw.setRenderPipelineState(encoder)
        draw.setDepthStencilState(depth)
        draw.setVertexBuffer(vertices, offset: 0, index: 0)
        basis.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                draw.setVertexBytes(base, length: bytes.count, index: 1)
            }
        }
        draw.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32,
                                   indexBuffer: indices, indexBufferOffset: 0)
        draw.endEncoding()
        command.present(display)
        command.commit()
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Vertex { packed_float3 position; packed_float3 normal; };
    struct Raster {
        float4 position [[position]];
        float3 viewNormal;
    };

    vertex Raster head_vertex(uint index [[vertex_id]],
                              const device Vertex *mesh [[buffer(0)]],
                              constant float4 *basis [[buffer(1)]]) {
        float3 p = mesh[index].position;
        float3 n = mesh[index].normal;
        return {float4(dot(p, basis[0].xyz) * basis[3].x + basis[3].z,
                       dot(p, basis[1].xyz) * basis[3].y + basis[3].w,
                       0.5 - dot(p, basis[2].xyz), 1.0),
                float3(dot(n, basis[0].xyz), dot(n, basis[1].xyz), dot(n, basis[2].xyz))};
    }

    fragment float4 head_fragment(Raster p [[stage_in]]) {
        // Camera-relative studio lights: upper-left key, softer right fill.
        float3 n = normalize(p.viewNormal);
        float3 keyDirection = normalize(float3(-0.52, 0.72, 0.70));
        float3 fillDirection = normalize(float3(0.67, 0.06, 0.74));
        float key = saturate((dot(n, keyDirection) + 0.18) / 1.18);
        float fill = saturate(dot(n, fillDirection));
        float rim = pow(1.0 - saturate(n.z), 2.0);
        float sheen = pow(saturate(dot(n, normalize(keyDirection + float3(0, 0, 1)))), 18.0);
        float tone = 0.16 + 0.28 * key + 0.13 * fill + 0.055 * rim + 0.035 * sheen;
        return float4(float3(tone), 1.0);
    }
    """
}

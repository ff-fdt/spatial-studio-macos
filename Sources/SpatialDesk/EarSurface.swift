import Foundation
import simd

/// Nose and ear geometry are in the same acoustic coordinates as the Canvas.
enum EarSurface {
    private struct Mesh {
        let points: [SIMD3<Double>]
        let indices: [Int]
    }

    private static let mesh: Mesh? = {
        guard let url = Bundle.module.url(forResource: "HeadScan", withExtension: "sdm", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), data.count >= 12 else { return nil }
        return data.withUnsafeBytes { bytes in
            let n = Int(bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            let triangles = Int(bytes.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            guard 12 + n * 24 + triangles * 12 == bytes.count else { return nil }
            let points = (0..<n).map { i -> SIMD3<Double> in
                let base = 12 + i * 24
                return SIMD3(Double(bytes.loadUnaligned(fromByteOffset: base, as: Float.self)),
                             Double(bytes.loadUnaligned(fromByteOffset: base + 4, as: Float.self)),
                             -Double(bytes.loadUnaligned(fromByteOffset: base + 8, as: Float.self)))
            }
            let indices = (0..<(triangles * 3)).map {
                Int(bytes.loadUnaligned(fromByteOffset: 12 + n * 24 + $0 * 4, as: UInt32.self))
            }
            guard indices.allSatisfy({ $0 < n }) else { return nil }
            return Mesh(points: points, indices: indices)
        }
    }()

    /// Intersect a click with the frontmost visible triangle in the ear region.
    static func hit(side: Double, uv: SIMD2<Double>, right: SIMD3<Double>, up: SIMD3<Double>,
                    toward: SIMD3<Double>) -> SIMD3<Double>? {
        guard let mesh else { return nil }
        var nearest = -Double.infinity
        var result: SIMD3<Double>?
        func proj(_ p: SIMD3<Double>) -> SIMD2<Double> { SIMD2(simd_dot(p, right), simd_dot(p, up)) }
        func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.points[mesh.indices[i]], b = mesh.points[mesh.indices[i+1]], c = mesh.points[mesh.indices[i+2]]
            guard max(a.x * side, b.x * side, c.x * side) >= 0.118 else { continue }
            let p = proj(a), ab = proj(b) - p, ac = proj(c) - p, click = uv - p
            let area = cross(ab, ac)
            guard abs(area) > 1e-12 else { continue }
            let t = cross(click, ac) / area, u = cross(ab, click) / area
            guard t >= 0, u >= 0, t + u <= 1 else { continue }
            let xyz = a + (b - a) * t + (c - a) * u
            guard xyz.x * side >= 0.118, (-0.073...0.035).contains(xyz.y),
                  (-0.085...0.06).contains(xyz.z) else { continue }
            let depth = simd_dot(xyz, toward)
            if depth > nearest { nearest = depth; result = xyz }
        }
        return result
    }
}

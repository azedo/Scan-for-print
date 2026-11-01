import Foundation
import ModelIO
import simd

/// A plain triangle mesh in metres, Y-up (the ARKit / RealityKit convention).
/// Kept free of ARKit/RealityKit so the Mac reconstruction tool can compile it too.
struct TriangleMesh: Sendable {
    var vertices: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    var triangleCount: Int { indices.count / 3 }
    var isEmpty: Bool { indices.isEmpty }

    /// Bounds of the vertices referenced by triangles.
    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard let first = indices.first else { return nil }
        var lo = vertices[Int(first)], hi = lo
        for i in indices {
            let v = vertices[Int(i)]
            lo = pointwiseMin(lo, v)
            hi = pointwiseMax(hi, v)
        }
        return (lo, hi)
    }

    /// Size in metres (x = width, y = height, z = depth).
    var size: SIMD3<Float> {
        guard let b = bounds else { return .zero }
        return b.max - b.min
    }

    mutating func append(vertices newVertices: [SIMD3<Float>], indices newIndices: [UInt32]) {
        let base = UInt32(vertices.count)
        vertices.append(contentsOf: newVertices)
        indices.append(contentsOf: newIndices.map { $0 + base })
    }

    /// Keeps only the triangles for which `keep` returns true. Unused vertices stay until `welded`.
    func filteringTriangles(_ keep: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Bool) -> TriangleMesh {
        var out = TriangleMesh(vertices: vertices, indices: [])
        out.indices.reserveCapacity(indices.count)
        for t in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = indices[t], b = indices[t + 1], c = indices[t + 2]
            if keep(vertices[Int(a)], vertices[Int(b)], vertices[Int(c)]) {
                out.indices.append(contentsOf: [a, b, c])
            }
        }
        return out
    }

    /// Merges vertices closer than `tolerance` (metres), drops unused vertices and degenerate
    /// triangles. Photogrammetry meshes duplicate vertices along texture seams, and LiDAR meshes
    /// along chunk borders, so this must run before checking for holes.
    func welded(tolerance: Float) -> TriangleMesh {
        struct Key: Hashable { let x, y, z: Int32 }
        let unprocessed: Int32 = -1, invalid: Int32 = -2
        var remap = [Int32](repeating: unprocessed, count: vertices.count)
        var lookup: [Key: Int32] = [:]
        lookup.reserveCapacity(vertices.count)
        var out = TriangleMesh()
        out.vertices.reserveCapacity(vertices.count)
        out.indices.reserveCapacity(indices.count)
        let inverse = 1 / tolerance
        let limit = SIMD3<Float>(repeating: 1e9)

        func resolve(_ index: UInt32) -> Int32 {
            let i = Int(index)
            if remap[i] != unprocessed { return remap[i] }
            let v = vertices[i]
            guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { remap[i] = invalid; return invalid }
            let q = (v * inverse).rounded(.toNearestOrAwayFromZero).clamped(lowerBound: -limit, upperBound: limit)
            let key = Key(x: Int32(clamping: Int(q.x)), y: Int32(clamping: Int(q.y)), z: Int32(clamping: Int(q.z)))
            if let existing = lookup[key] {
                remap[i] = existing
            } else {
                let new = Int32(out.vertices.count)
                out.vertices.append(v)
                lookup[key] = new
                remap[i] = new
            }
            return remap[i]
        }

        for t in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = resolve(indices[t]), b = resolve(indices[t + 1]), c = resolve(indices[t + 2])
            guard a >= 0, b >= 0, c >= 0, a != b, b != c, a != c else { continue }
            out.indices.append(contentsOf: [UInt32(a), UInt32(b), UInt32(c)])
        }
        return out
    }

    struct EdgeReport: Sendable {
        /// Edges used by only one triangle: holes in the surface.
        var openEdges: Int
        /// Edges shared by more than two triangles: self-intersecting or doubled geometry.
        var nonManifoldEdges: Int
        var isWatertight: Bool { openEdges == 0 && nonManifoldEdges == 0 }
    }

    /// Counts how many triangles share each edge. Run on a welded mesh.
    func edgeReport() -> EdgeReport {
        var counts: [UInt64: UInt32] = [:]
        counts.reserveCapacity(indices.count)
        func add(_ u: UInt32, _ v: UInt32) {
            let key = u < v ? (UInt64(u) << 32 | UInt64(v)) : (UInt64(v) << 32 | UInt64(u))
            counts[key, default: 0] += 1
        }
        for t in stride(from: 0, to: indices.count - 2, by: 3) {
            add(indices[t], indices[t + 1])
            add(indices[t + 1], indices[t + 2])
            add(indices[t + 2], indices[t])
        }
        var open = 0, nonManifold = 0
        for count in counts.values {
            if count == 1 { open += 1 } else if count > 2 { nonManifold += 1 }
        }
        return EdgeReport(openEdges: open, nonManifoldEdges: nonManifold)
    }

    enum MeshError: LocalizedError {
        case empty
        case unsupportedFormat(String)
        var errorDescription: String? {
            switch self {
            case .empty: "The scan didn't produce any geometry."
            case .unsupportedFormat(let ext): "Can't read .\(ext) files on this device."
            }
        }
    }

    /// Writes a binary STL in millimetres, Z-up (what slicers expect), centred on X/Y and
    /// resting on z = 0. `scale` multiplies the real-world size.
    func writeBinarySTL(to url: URL, scale: Float = 1) throws {
        guard let b = bounds else { throw MeshError.empty }
        let origin = SIMD3<Float>((b.min.x + b.max.x) / 2, b.min.y, (b.min.z + b.max.z) / 2)
        let factor = 1000 * scale

        // Metres Y-up → millimetres Z-up: a +90° rotation about X, so triangle winding is kept.
        func convert(_ v: SIMD3<Float>) -> SIMD3<Float> {
            let p = (v - origin) * factor
            return SIMD3(p.x, -p.z, p.y)
        }

        var data = Data(capacity: 84 + triangleCount * 50)
        var header = [UInt8](repeating: 0, count: 80)
        let tag = Array("ScanForPrint binary STL, units: mm".utf8)
        header.replaceSubrange(0..<tag.count, with: tag)
        data.append(contentsOf: header)
        data.appendLittleEndian(UInt32(triangleCount))

        for t in 0..<triangleCount {
            let a = convert(vertices[Int(indices[t * 3])])
            let b = convert(vertices[Int(indices[t * 3 + 1])])
            let c = convert(vertices[Int(indices[t * 3 + 2])])
            let n = simd_cross(b - a, c - a)
            let length = simd_length(n)
            data.appendLittleEndian(length > 0 ? n / length : .zero)
            data.appendLittleEndian(a)
            data.appendLittleEndian(b)
            data.appendLittleEndian(c)
            data.appendLittleEndian(UInt16(0))
        }
        try data.write(to: url, options: .atomic)
    }

    /// Loads every triangle in a model file (USDZ, OBJ…) via ModelIO, applying node transforms.
    static func load(from url: URL) throws -> TriangleMesh {
        guard MDLAsset.canImportFileExtension(url.pathExtension) else {
            throw MeshError.unsupportedFormat(url.pathExtension)
        }
        let asset = MDLAsset(url: url)
        var mesh = TriangleMesh()
        for i in 0..<asset.count {
            collect(asset.object(at: i), parent: matrix_identity_float4x4, into: &mesh)
        }
        guard !mesh.isEmpty else { throw MeshError.empty }
        return mesh
    }

    private static func collect(_ object: MDLObject, parent: simd_float4x4, into mesh: inout TriangleMesh) {
        let world = parent * (object.transform?.matrix ?? matrix_identity_float4x4)
        if let modelMesh = object as? MDLMesh {
            append(modelMesh, transform: world, into: &mesh)
        }
        for child in object.children.objects {
            collect(child, parent: world, into: &mesh)
        }
    }

    private static func append(_ source: MDLMesh, transform: simd_float4x4, into mesh: inout TriangleMesh) {
        guard let positions = source.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3)
        else { return }
        let base = UInt32(mesh.vertices.count)
        mesh.vertices.reserveCapacity(mesh.vertices.count + source.vertexCount)
        for i in 0..<source.vertexCount {
            let p = positions.dataStart.advanced(by: i * positions.stride).assumingMemoryBound(to: Float.self)
            let w = transform * SIMD4<Float>(p[0], p[1], p[2], 1)
            mesh.vertices.append(SIMD3(w.x, w.y, w.z))
        }
        let submeshes = (source.submeshes as? [MDLSubmesh]) ?? []
        for submesh in submeshes where submesh.geometryType == .triangles {
            let map = submesh.indexBuffer(asIndexType: .uInt32).map()
            let index = map.bytes.assumingMemoryBound(to: UInt32.self)
            for j in 0..<submesh.indexCount {
                mesh.indices.append(base + index[j])
            }
        }
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func appendLittleEndian(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func appendLittleEndian(_ v: SIMD3<Float>) {
        appendLittleEndian(v.x.bitPattern)
        appendLittleEndian(v.y.bitPattern)
        appendLittleEndian(v.z.bitPattern)
    }
}

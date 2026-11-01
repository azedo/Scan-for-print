import ARKit
import Metal
import Observation
import RealityKit
import UIKit

/// Live LiDAR scene reconstruction for things too big for Object Capture.
/// The user marks a centre point and a radius; everything outside it is cropped away.
@MainActor
@Observable
final class MeshScanModel {
    enum Phase {
        case scanning
        case processing
        case done(ScanResult)
        case failed(String)
    }

    private(set) var phase: Phase = .scanning
    private(set) var center: SIMD3<Float>?
    private(set) var meshChunks = 0
    var radius: Float = 0.6
    var removeFloor = true
    var message: String?

    @ObservationIgnored let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    @ObservationIgnored private var cropSphere: ModelEntity?
    @ObservationIgnored private var cropAnchor: AnchorEntity?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    private var hasClassification: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    func start() {
        guard Self.isSupported else {
            phase = .failed("Large scans need a device with a LiDAR sensor.")
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = hasClassification ? .meshWithClassification : .mesh
        configuration.environmentTexturing = .none
        arView.debugOptions.insert(.showSceneUnderstanding)
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.meshChunks = self.currentMeshAnchors().count
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        arView.session.pause()
    }

    /// Uses the surface under the crosshair as the centre of the crop sphere.
    func setCenter() {
        let point = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let hit = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first else {
            message = "Couldn't find a surface. Aim at the object and try again."
            return
        }
        let t = hit.worldTransform.columns.3
        let position = SIMD3<Float>(t.x, t.y, t.z)
        center = position
        message = nil

        cropAnchor?.removeFromParent()
        var material = UnlitMaterial(color: .systemBlue)
        material.blending = .transparent(opacity: 0.18)
        let sphere = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
        sphere.scale = SIMD3(repeating: radius)
        let anchor = AnchorEntity(world: position)
        anchor.addChild(sphere)
        arView.scene.addAnchor(anchor)
        cropSphere = sphere
        cropAnchor = anchor
    }

    func radiusChanged() {
        cropSphere?.scale = SIMD3(repeating: radius)
    }

    func finish() async {
        let anchors = currentMeshAnchors()
        guard !anchors.isEmpty else {
            message = "No mesh yet. Move the phone around the object first."
            return
        }
        phase = .processing
        stop()

        var raw = Self.extract(anchors, dropFloor: removeFloor && hasClassification)
        if let center {
            let r2 = radius * radius
            raw = raw.filteringTriangles { a, b, c in
                simd_distance_squared(a, center) <= r2 &&
                simd_distance_squared(b, center) <= r2 &&
                simd_distance_squared(c, center) <= r2
            }
        }
        let snapshot = raw
        // 2 mm weld joins the separate mesh chunks ARKit produces.
        let mesh = await Task.detached(priority: .userInitiated) { snapshot.welded(tolerance: 0.002) }.value

        guard !mesh.isEmpty else {
            phase = .failed("Nothing left inside the crop sphere. Try a larger radius.")
            return
        }
        do {
            let folder = try ScanStorage.newFolder(kind: "Large", withImages: false)
            phase = .done(ScanResult(kind: .large, folder: folder, mesh: mesh, texturedModel: nil))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func currentMeshAnchors() -> [ARMeshAnchor] {
        arView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
    }

    /// Copies ARKit mesh chunks into world-space triangles.
    private static func extract(_ anchors: [ARMeshAnchor], dropFloor: Bool) -> TriangleMesh {
        var mesh = TriangleMesh()
        for anchor in anchors {
            let geometry = anchor.geometry

            let vertexSource = geometry.vertices
            let vertexBase = vertexSource.buffer.contents().advanced(by: vertexSource.offset)
            var vertices = [SIMD3<Float>]()
            vertices.reserveCapacity(vertexSource.count)
            for i in 0..<vertexSource.count {
                let p = vertexBase.advanced(by: i * vertexSource.stride).assumingMemoryBound(to: Float.self)
                let w = anchor.transform * SIMD4<Float>(p[0], p[1], p[2], 1)
                vertices.append(SIMD3(w.x, w.y, w.z))
            }

            let faces = geometry.faces
            let faceBase = faces.buffer.contents()
            let classification = dropFloor ? geometry.classification : nil
            var indices = [UInt32]()
            indices.reserveCapacity(faces.count * 3)

            for face in 0..<faces.count {
                if let classification {
                    let raw = classification.buffer.contents()
                        .advanced(by: classification.offset + face * classification.stride)
                        .load(as: UInt8.self)
                    if ARMeshClassification(rawValue: Int(raw)) == .floor { continue }
                }
                for k in 0..<3 {
                    let offset = (face * faces.indexCountPerPrimitive + k) * faces.bytesPerIndex
                    let index: UInt32 = faces.bytesPerIndex == 4
                        ? faceBase.load(fromByteOffset: offset, as: UInt32.self)
                        : UInt32(faceBase.load(fromByteOffset: offset, as: UInt16.self))
                    indices.append(index)
                }
            }
            mesh.append(vertices: vertices, indices: indices)
        }
        return mesh
    }
}

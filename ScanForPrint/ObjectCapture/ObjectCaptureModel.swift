import Foundation
import Observation
import RealityKit

/// Drives guided capture (ObjectCaptureSession) and then on-device reconstruction
/// (PhotogrammetrySession), producing a textured USDZ plus a mesh for STL export.
@MainActor
@Observable
final class ObjectCaptureModel {
    enum Phase {
        case intro
        case capturing
        case reconstructing(Double)
        case done(ScanResult)
        case failed(String)
    }

    private(set) var phase: Phase = .intro
    private(set) var session: ObjectCaptureSession?

    @ObservationIgnored private var folder: ScanFolder?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var photogrammetry: PhotogrammetrySession?
    @ObservationIgnored private var isCancelling = false

    static var isSupported: Bool {
        ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported
    }

    func start() {
        guard Self.isSupported else {
            phase = .failed("Object scans need an iPhone or iPad with a LiDAR sensor (iPhone 12 Pro or later).")
            return
        }
        do {
            let folder = try ScanStorage.newFolder(kind: "Object", withImages: true)
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = folder.checkpoints

            let session = ObjectCaptureSession()
            session.start(imagesDirectory: folder.images, configuration: configuration)

            self.folder = folder
            self.session = session
            isCancelling = false
            phase = .capturing

            stateTask = Task { [weak self] in
                for await state in session.stateUpdates {
                    switch state {
                    case .completed:
                        await self?.reconstruct()
                        return
                    case .failed(let error):
                        self?.captureFailed(error)
                        return
                    default:
                        break
                    }
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        isCancelling = true
        switch phase {
        case .capturing: session?.cancel()
        case .reconstructing: photogrammetry?.cancel()
        default: break
        }
        stateTask?.cancel()
    }

    private func captureFailed(_ error: Error) {
        guard !isCancelling else { return }
        session = nil
        phase = .failed(error.localizedDescription)
    }

    private func reconstruct() async {
        guard let folder, !isCancelling else { return }
        // Release the capture session first: Apple recommends freeing its memory
        // before running reconstruction on device.
        session = nil
        phase = .reconstructing(0)

        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = folder.checkpoints
            let photogrammetry = try PhotogrammetrySession(input: folder.images, configuration: configuration)
            self.photogrammetry = photogrammetry

            // Start listening before submitting the request.
            let outputs = Task { [weak self] () throws -> Bool in
                for try await output in photogrammetry.outputs {
                    switch output {
                    case .requestProgress(_, let fraction):
                        self?.phase = .reconstructing(fraction)
                    case .requestError(_, let error):
                        throw error
                    case .processingCancelled:
                        return false
                    case .processingComplete:
                        return true
                    default:
                        break
                    }
                }
                return false
            }

            // iOS only supports the .reduced detail level (< 50k triangles).
            try photogrammetry.process(requests: [.modelFile(url: folder.texturedModel, detail: .reduced)])
            let completed = try await outputs.value
            self.photogrammetry = nil
            guard completed, !isCancelling else { return }

            let modelURL = folder.texturedModel
            let mesh = try await Task.detached(priority: .userInitiated) {
                try TriangleMesh.load(from: modelURL).welded(tolerance: 0.00001)
            }.value

            phase = .done(ScanResult(kind: .object, folder: folder, mesh: mesh, texturedModel: modelURL))
            try? FileManager.default.removeItem(at: folder.checkpoints)
        } catch {
            self.photogrammetry = nil
            if !isCancelling {
                phase = .failed("Reconstruction failed: \(error.localizedDescription)")
            }
        }
    }
}

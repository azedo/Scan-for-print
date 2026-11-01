// Full-detail reconstruction on a Mac from an object scan's Images folder.
//
// Build (from the ScanForPrint folder):
//   swiftc -O mac/main.swift ScanForPrint/Shared/TriangleMesh.swift -o reconstruct
// Run:
//   ./reconstruct "path/to/Images" "my-part" [preview|reduced|medium|full|raw]
// Writes my-part.usdz (textured) and my-part.stl (mm, Z-up). Default detail: full.
// Needs macOS 12+ on Apple silicon, or an Intel Mac with a 4 GB+ AMD GPU.

import Foundation
import RealityKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: reconstruct <ImagesFolder> <output-name> [preview|reduced|medium|full|raw]")
    exit(1)
}

let input = URL(fileURLWithPath: args[1], isDirectory: true)
let outputBase = URL(fileURLWithPath: args[2]).deletingPathExtension()
let usdzURL = outputBase.appendingPathExtension("usdz")
let stlURL = outputBase.appendingPathExtension("stl")

let detailName = args.count > 3 ? args[3] : "full"
let detail: PhotogrammetrySession.Request.Detail
switch detailName {
case "preview": detail = .preview
case "reduced": detail = .reduced
case "medium": detail = .medium
case "full": detail = .full
case "raw": detail = .raw
default:
    print("Unknown detail level '\(detailName)'")
    exit(1)
}

let session = try PhotogrammetrySession(input: input, configuration: PhotogrammetrySession.Configuration())

Task {
    do {
        for try await output in session.outputs {
            switch output {
            case .requestProgress(_, let fraction):
                print(String(format: "\rReconstructing… %3.0f%%", fraction * 100), terminator: "")
                fflush(stdout)
            case .requestError(_, let error):
                print("\nError: \(error)")
                exit(1)
            case .processingCancelled:
                print("\nCancelled")
                exit(1)
            case .processingComplete:
                print("\nSaved \(usdzURL.path)")
                let mesh = try TriangleMesh.load(from: usdzURL).welded(tolerance: 0.00001)
                try mesh.writeBinarySTL(to: stlURL)
                let report = mesh.edgeReport()
                let size = mesh.size * 1000
                print(String(format: "Saved %@ — %d triangles, %.1f × %.1f × %.1f mm",
                             stlURL.path, mesh.triangleCount, size.x, size.z, size.y))
                print(report.isWatertight
                      ? "Mesh is watertight."
                      : "Mesh has \(report.openEdges) open and \(report.nonManifoldEdges) non-manifold edges; let your slicer repair it.")
                exit(0)
            default:
                break
            }
        }
    } catch {
        print("\nError: \(error)")
        exit(1)
    }
}

try session.process(requests: [.modelFile(url: usdzURL, detail: detail)])
dispatchMain()

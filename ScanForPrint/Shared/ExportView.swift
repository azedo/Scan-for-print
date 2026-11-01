import QuickLook
import SwiftUI
import UIKit

/// Shown after either scan mode: size, scale, hole check and STL export.
struct ExportView: View {
    let result: ScanResult

    @State private var report: TriangleMesh.EdgeReport?
    @State private var longestSideMM: Double
    @State private var shareItem: ShareItem?
    @State private var previewURL: URL?
    @State private var isExporting = false
    @State private var errorMessage: String?

    private let realLongestSideMM: Double

    init(result: ScanResult) {
        self.result = result
        let real = Double(result.mesh.size.max()) * 1000
        realLongestSideMM = real
        _longestSideMM = State(initialValue: (real * 10).rounded() / 10)
    }

    private var scale: Float {
        guard realLongestSideMM > 0, longestSideMM > 0 else { return 1 }
        return Float(longestSideMM / realLongestSideMM)
    }

    /// Width × depth × height in mm, matching the Z-up STL.
    private var dimensions: String {
        let s = result.mesh.size * 1000 * scale
        let f = FloatingPointFormatStyle<Float>.number.precision(.fractionLength(1))
        return "\(s.x.formatted(f)) × \(s.z.formatted(f)) × \(s.y.formatted(f)) mm"
    }

    var body: some View {
        Form {
            Section("Model") {
                LabeledContent("Triangles", value: result.mesh.triangleCount.formatted())
                LabeledContent("Size (W × D × H)", value: dimensions)
                meshCheck
            }

            Section {
                HStack {
                    Text("Longest side")
                    Spacer()
                    TextField("mm", value: $longestSideMM, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                    Text("mm").foregroundStyle(.secondary)
                }
                Button("Reset to real size") {
                    longestSideMM = (realLongestSideMM * 10).rounded() / 10
                }
            } header: {
                Text("Print size")
            } footer: {
                Text("Scans are captured at real-world scale. Measure the real object to sanity-check it, or change the size to print smaller or larger.")
            }

            Section {
                Button {
                    exportSTL()
                } label: {
                    HStack {
                        Label("Export STL", systemImage: "square.and.arrow.up")
                        if isExporting { Spacer(); ProgressView() }
                    }
                }
                .disabled(isExporting || longestSideMM <= 0)

                if let model = result.texturedModel {
                    Button {
                        previewURL = model
                    } label: {
                        Label("Preview in 3D", systemImage: "arkit")
                    }
                    ShareLink(item: model) {
                        Label("Share textured USDZ", systemImage: "cube")
                    }
                }
            } footer: {
                Text("The STL opens directly in PrusaSlicer, OrcaSlicer, Bambu Studio and Cura.")
            }

            if result.kind == .object {
                Section("Want more detail?") {
                    Text("On iPhone, Apple limits models to about 50,000 triangles. For fine detail, copy this scan's Images folder from Files (On My iPhone › Scan for Print › Scans › \(result.folder.name)) to a Mac and run the reconstruct tool from the project's mac folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Scan ready")
        .task {
            let mesh = result.mesh
            report = await Task.detached(priority: .userInitiated) { mesh.edgeReport() }.value
        }
        .quickLookPreview($previewURL)
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .alert("Export failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder private var meshCheck: some View {
        if let report {
            if report.isWatertight {
                Label("Watertight, ready to slice", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(report.openEdges.formatted()) open edges, \(report.nonManifoldEdges.formatted()) non-manifold",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Small holes are normal, especially for large scans. Most slicers offer to repair the model on import; for bigger gaps use Blender's 3D-Print Toolbox.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            LabeledContent("Checking for holes") { ProgressView() }
        }
    }

    private func exportSTL() {
        isExporting = true
        let mesh = result.mesh
        let url = result.folder.stl
        let scale = scale
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try mesh.writeBinarySTL(to: url, scale: scale)
                }.value
                shareItem = ShareItem(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

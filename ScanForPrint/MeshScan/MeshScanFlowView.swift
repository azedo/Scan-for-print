import RealityKit
import SwiftUI

struct MeshScanFlowView: View {
    @State private var model = MeshScanModel()

    var body: some View {
        ZStack {
            switch model.phase {
            case .scanning:
                ScanningView(model: model)
            case .processing:
                ProgressView("Building mesh…")
            case .done(let result):
                ExportView(result: result)
            case .failed(let message):
                ContentUnavailableView("Scan failed", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
        .navigationTitle("Large scan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

private struct ScanningView: View {
    @Bindable var model: MeshScanModel

    var body: some View {
        ARViewContainer(arView: model.arView)
            .ignoresSafeArea()
            .overlay {
                Image(systemName: "plus")
                    .font(.title2.weight(.light))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .overlay(alignment: .bottom) {
                panel.padding()
            }
    }

    private var panel: some View {
        VStack(spacing: 12) {
            Text(model.message ?? instructions)
                .font(.callout)
                .multilineTextAlignment(.center)

            if model.center != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crop radius: \(model.radius.formatted(.number.precision(.fractionLength(2)))) m")
                        .font(.caption)
                    Slider(value: $model.radius, in: 0.1...3)
                        .onChange(of: model.radius) { model.radiusChanged() }
                }
            }

            Toggle("Remove floor", isOn: $model.removeFloor)
                .font(.callout)

            HStack {
                Button {
                    model.setCenter()
                } label: {
                    Text(model.center == nil ? "Set center" : "Move center").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await model.finish() }
                } label: {
                    Text("Finish").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.meshChunks == 0)
            }
            .controlSize(.large)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var instructions: String {
        if model.center == nil {
            return "Walk around slowly until the mesh covers the object, then aim at its middle and tap Set center."
        }
        return "Size the blue sphere so it just encloses the object. Everything outside is cropped."
    }
}

private struct ARViewContainer: UIViewRepresentable {
    let arView: ARView
    func makeUIView(context: Context) -> ARView { arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

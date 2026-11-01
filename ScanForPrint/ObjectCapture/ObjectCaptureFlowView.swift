import RealityKit
import SwiftUI

struct ObjectCaptureFlowView: View {
    @State private var model = ObjectCaptureModel()

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro:
                IntroView { model.start() }
            case .capturing:
                if let session = model.session {
                    CaptureView(session: session)
                }
            case .reconstructing(let progress):
                ReconstructionView(progress: progress)
            case .done(let result):
                ExportView(result: result)
            case .failed(let message):
                ContentUnavailableView("Scan failed", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
        .navigationTitle("Object scan")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.cancel() }
    }
}

private struct IntroView: View {
    let start: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 12) {
                tip("lightbulb", "Bright, even light without hard shadows.")
                tip("square.dashed", "A plain, non-reflective surface with some texture around the object.")
                tip("sparkles", "Shiny or see-through objects scan badly. A light dusting of matte spray helps.")
                tip("arrow.triangle.2.circlepath", "Walk slowly all the way around. Flip the object for a second pass to capture the underside.")
            }
            Spacer()
            Button(action: start) {
                Text("Start scanning").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
    }
}

private struct CaptureView: View {
    let session: ObjectCaptureSession

    var body: some View {
        ObjectCaptureView(session: session)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if case .capturing = session.state {
                    Text("\(session.numberOfShotsTaken) photos")
                        .font(.footnote.monospacedDigit())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                }
            }
            .overlay(alignment: .bottom) {
                controls.padding()
            }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            switch session.state {
            case .ready:
                hint("Point at the object, then tap Continue.")
                primary("Continue") { _ = session.startDetecting() }
            case .detecting:
                hint("Drag the box edges so it fits the object snugly.")
                HStack {
                    secondary("Reset") { _ = session.resetDetection() }
                    primary("Start capture") { session.startCapturing() }
                }
            case .capturing:
                if session.userCompletedScanPass {
                    hint("Pass complete. Flip the object to capture the underside, or finish.")
                    primary("Flip object & scan again") { session.beginNewScanPassAfterFlip() }
                    HStack {
                        secondary("Another pass") { session.beginNewScanPass() }
                        secondary("Finish") { session.finish() }
                    }
                } else {
                    hint("Move slowly around the object until the dial is full.")
                    secondary("Finish early") { session.finish() }
                }
            case .finishing:
                ProgressView("Saving photos…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            default:
                EmptyView()
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ReconstructionView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress) {
                Text("Building your model")
            } currentValueLabel: {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
            }
            Text("This runs on the phone and takes a few minutes. Keep the app open.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

import SwiftUI

@main
struct ScanForPrintApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ObjectCaptureFlowView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Object scan").font(.headline)
                                Text("Photos + LiDAR depth. Best detail, for things that fit on a table.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "cube.transparent") }
                    }

                    NavigationLink {
                        MeshScanFlowView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Large scan").font(.headline)
                                Text("Live LiDAR mesh. For furniture, people and spaces — lower detail.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "dot.radiowaves.left.and.right") }
                    }
                } footer: {
                    Text("Scans are saved in the app's folder in Files, so you can copy the captured photos to a Mac for higher-detail reconstruction.")
                }
            }
            .navigationTitle("Scan for Print")
        }
    }
}

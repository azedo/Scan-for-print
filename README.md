# Scan for Print

An iOS 17+ SwiftUI app that turns LiDAR iPhone/iPad scans into print-ready STL files.

## Modes

**Object scan** uses Apple's Object Capture: guided photos plus LiDAR depth, reconstructed on device. Best for parts, figurines and anything that fits on a table. It keeps texture (USDZ) and real-world scale. On iPhone, Apple caps models at the `.reduced` level (under 50k triangles). For finer detail, run `mac/` on the Images folder.

**Large scan** uses ARKit's live LiDAR mesh for furniture, people and spaces. Set a center point, size the crop sphere and optionally drop the floor. Expect ~1 cm accuracy and some holes; it's meant for rough or big prints, not fine detail.

Both modes then show the size in mm, let you rescale, check the mesh for holes, and export a binary STL (millimetres, Z-up, centred and sitting on the bed).

## Setup

Requires Xcode 15+, a LiDAR device (iPhone 12 Pro or later, or an iPad Pro 2020+), and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd ScanForPrint
xcodegen
open ScanForPrint.xcodeproj
```

Set your team under Signing & Capabilities and change the bundle ID in `project.yml` if needed. Then run it on a device. The simulator has no camera or LiDAR.

## Scans on disk

Each scan is saved to `Files › On My iPhone › Scan for Print › Scans › <scan name>/`:

- `Images/`: the captured photos (object scans)
- `model.usdz`: the textured model (object scans)
- `<scan name>.stl`: written when you export

## Full-detail reconstruction on a Mac

```sh
swiftc -O mac/main.swift ScanForPrint/Shared/TriangleMesh.swift -o reconstruct
./reconstruct ~/Downloads/Images my-part full     # or raw for maximum detail
```

This writes `my-part.usdz` and `my-part.stl`.

## Scanning tips

- Use bright, diffuse light, a matte surface and a textured background.
- Shiny, black or transparent objects scan poorly. Matte scanning spray (or dry shampoo) helps.
- Do one pass at mid height, a higher pass, then flip the object for the underside.
- Measure one dimension of the real object and compare it to the size shown before printing.

## Code map

| File | What it does |
|---|---|
| `ObjectCapture/ObjectCaptureModel.swift` | Capture session state machine and on-device photogrammetry |
| `ObjectCapture/ObjectCaptureFlowView.swift` | Guided capture UI |
| `MeshScan/MeshScanModel.swift` | ARKit mesh reconstruction, crop sphere, floor removal |
| `Shared/TriangleMesh.swift` | USDZ loading, vertex welding, hole check, STL writer (shared with the Mac tool) |
| `Shared/ExportView.swift` | Size and scale, mesh check, STL/USDZ sharing |

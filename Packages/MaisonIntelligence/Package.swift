// swift-tools-version: 6.2
import PackageDescription

/// The intelligence layer: pure Swift on Foundation only, so the same code builds for the iPhone and for the
/// Linux add-on. No SwiftUI, no string catalogs, no on-device model: it computes facts, the app words them.
let package = Package(
    name: "MaisonIntelligence",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "MaisonIntelligence", targets: ["MaisonIntelligence"]),
    ],
    targets: [
        .target(name: "MaisonIntelligence"),
        .testTarget(name: "MaisonIntelligenceTests", dependencies: ["MaisonIntelligence"]),
    ]
)

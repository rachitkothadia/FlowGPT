// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "FlowGpt", platforms: [.macOS(.v14)], products: [
    .library(name: "FlowCore", targets: ["FlowCore"]),
    .executable(name: "FlowGpt", targets: ["FlowApp"]),
    .executable(name: "FlowQA", targets: ["FlowQA"])
], targets: [.target(name: "FlowFormatting", path: "Shared", exclude: ["Tests"], publicHeadersPath: "include"), .target(name: "FlowCore", dependencies: ["FlowFormatting"]), .executableTarget(name: "FlowApp", dependencies: ["FlowCore"]), .executableTarget(name: "FlowQA", dependencies: ["FlowCore"]), .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"], path: "Tests/FlowCoreTests")], cxxLanguageStandard: .cxx17)

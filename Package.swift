// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CodexUsage",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "CodexUsage", targets: ["CodexUsage"])],
    targets: [
        .executableTarget(name: "CodexUsage", dependencies: ["Sparkle"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .binaryTarget(name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606")
    ],
    swiftLanguageModes: [.v5]
)

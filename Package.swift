// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "N1KOState",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        // Vendored, MIT-licensed SMC client (from github.com/beltex/SMCKit).
        // Imported as a local module because upstream ships no Package.swift.
        .target(
            name: "SMCKit",
            path: "Sources/SMCKit",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        // C shim that declares the private IOHIDEventSystem symbols used to read
        // real Apple Silicon temperatures (the legacy SMC keys are empty there).
        .target(
            name: "IOHIDSensorBridge",
            path: "Sources/IOHIDSensorBridge",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        // ObjC shim exposing NSXPCConnection.auditToken (SPI) so the daemon can
        // validate connecting clients by code signature.
        .target(
            name: "XPCAuditShim",
            path: "Sources/XPCAuditShim"
        ),
        // Shared XPC contract (protocol + wire types + paths) used by both the
        // app and the privileged daemon.
        .target(
            name: "FanXPCShared",
            path: "Sources/FanXPCShared"
        ),
        // Privileged helper: a long-running LaunchDaemon that vends the fan
        // control Mach service (run as root, installed once via admin auth).
        .executableTarget(
            name: "FanHelper",
            dependencies: ["SMCKit", "FanXPCShared", "XPCAuditShim"],
            path: "Sources/FanHelper",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "N1KOState",
            dependencies: ["SMCKit", "IOHIDSensorBridge", "FanXPCShared"],
            path: "Sources/N1KOState",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal")
            ]
        )
    ]
)

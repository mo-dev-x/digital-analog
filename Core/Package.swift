// swift-tools-version: 5.9
import PackageDescription
// Apple SDKs provide SQLite. Host pkg-config can inject a macOS Homebrew
// library path into an iOS cross-build, so use it only on Linux.
#if os(Linux)
let sqlite = Target.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])])
#else
let sqlite = Target.systemLibrary(name: "CSQLite")
#endif
let package = Package(name: "DigitalAnalogCore", platforms: [.iOS(.v17), .macOS(.v13)], products: [.library(name: "DigitalAnalogCore", targets: ["DigitalAnalogCore"])], targets: [sqlite, .target(name: "DigitalAnalogCore", dependencies: ["CSQLite"]), .testTarget(name: "DigitalAnalogCoreTests", dependencies: ["DigitalAnalogCore"])])

// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CWMarketing",
    platforms: [.iOS(.v13), .macOS(.v10_13), .tvOS(.v13), .watchOS(.v7)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "CWMarketing",
            targets: ["CWMarketing"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.6.0")),
        .package(url: "https://github.com/Alamofire/AlamofireImage", .upToNextMajor(from: "4.2.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "CWMarketing",
            dependencies: ["Alamofire", "AlamofireImage"]),
        .testTarget(
            name: "CWMarketingTests",
            dependencies: ["CWMarketing", "Alamofire", "AlamofireImage"]),
    ]
)

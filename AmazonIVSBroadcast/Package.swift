// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AmazonIVSBroadcast",
    platforms: [
        .iOS("14.0"),
    ],
    products: [
        .library(
            name: "AmazonIVSBroadcast",
            targets: ["AmazonIVSBroadcast"]
        ),
        .library(
            name: "AmazonIVSBroadcastStages",
            targets: ["AmazonIVSBroadcastStages"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "AmazonIVSBroadcast",
            url: "https://broadcast.live-video.net/1.44.1/AmazonIVSBroadcast.xcframework.zip",
            checksum: "4966634eb9599642e74ebc703103c6a78c2c9a413163cbdda9e3b68815bda5f8"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.44.1/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "ed6439d054377fbb4efdc873d20be88903facdacabb38a5a18c656c1d79d3e28"
        )
    ]
)

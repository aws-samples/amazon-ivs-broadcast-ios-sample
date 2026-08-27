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
            url: "https://broadcast.live-video.net/1.46.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "e5bedc9c49f231c14ab7d2fdb09cc98c77b19c6db21d80e1672484dd91a2a0bf"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.46.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "64e0877516d765f1ad9317b39a292eac191d042dcf1a3b8272361dfeeb41742d"
        )
    ]
)

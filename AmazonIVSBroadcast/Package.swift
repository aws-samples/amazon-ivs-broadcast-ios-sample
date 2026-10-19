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
            url: "https://broadcast.live-video.net/1.47.1/AmazonIVSBroadcast.xcframework.zip",
            checksum: "3392d27c97ec12a8fa7d897d62a906e85adec628898711397d120a7100f3d054"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.47.1/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "7a0c911187474a86f5cfdd60e69c1bae38d859573a3fb827c676b8a406311120"
        )
    ]
)

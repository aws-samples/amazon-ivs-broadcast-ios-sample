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
            url: "https://broadcast.live-video.net/1.44.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "6177344e00ba0b92d69d66e74af716eefc766f6fe9315d17b31d7e65229e3e37"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.44.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "647f51deafd981655643ab1bfc71f03f79eec7704b7e0edafb4207009f3fe4d0"
        )
    ]
)

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
            url: "https://broadcast.live-video.net/1.41.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "5ea9228572e088de824d27263fec503ce9d78a78c053083988098a6809834710"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.41.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "cfea8b1f0312cbdf4f522224e2843e08a8afb79abc7f47348726eb4a8400dbd6"
        )
    ]
)

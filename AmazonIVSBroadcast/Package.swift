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
            url: "https://broadcast.live-video.net/1.47.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "a536120a09a159a1d20675c1f16b6331b892fc33fe252b3f404577acbb01146a"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.47.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "5d0276982a3356c22e2251968da56100ac124ae444aa480487ff4ad9f204c87c"
        )
    ]
)

// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AmazonIVSBroadcast",
    platforms: [
        .iOS("15.0"),
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
            url: "https://broadcast.live-video.net/1.48.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "007a7c1771c4dfc901e206ec379d21a54213cdee5decb4edef9b8259c06c7d8e"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.48.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "d2cc3f996e1581205c4bc61df23b4041a8e31f209c22b1507ddc74b0ef13cdd1"
        )
    ]
)

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
            url: "https://broadcast.live-video.net/1.49.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "6dc36093521437a51a80ca1ed6c40127502bae26aeb68047b2b53e9aa36c04ad"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.49.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "c2f519de3075f905e6712a142e1d25d1925344aea4d2ce91f9eadb3b15396a30"
        )
    ]
)

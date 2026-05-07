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
            url: "https://broadcast.live-video.net/1.42.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "2af2d1808dff65b0aaeee7f59da396841d26dffe4c70f956a30d68e2cc07805d"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.42.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "3399b53b60871bce070ac598d89ed77f7181f05ee9dd6faabd3fffdf19051250"
        )
    ]
)

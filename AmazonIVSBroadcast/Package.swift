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
            url: "https://broadcast.live-video.net/1.43.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "d9f355825e8b5170e82e8fc1f6edd413b3515fe86eca12ae6e3c0814d7c3b7b8"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.43.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "0b7961924971964c518640c561cc2d16751a1c728832a6571553896ceca207a0"
        )
    ]
)

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
            url: "https://broadcast.live-video.net/1.45.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "dd01375294c938bda117baf79fd085f0d0e767c027f305c368c5b246524b5517"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.45.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "c8bb03265bae387fe907e50d7136d90cd133ec8dbddabb39d7531e97d07bd68e"
        )
    ]
)

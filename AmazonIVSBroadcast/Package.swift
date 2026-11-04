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
            url: "https://broadcast.live-video.net/1.48.1/AmazonIVSBroadcast.xcframework.zip",
            checksum: "eb83984c90dc080f7bffcbc4647e035f17119024a700d4299ab6e2715a9760ee"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.48.1/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "9971208134c0ee63e9775001b44f1b879bc991192e47ed600eb9e1a292084b3b"
        )
    ]
)

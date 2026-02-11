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
            url: "https://broadcast.live-video.net/1.38.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "a16c3950d6196c0d212ca690f86d9dfd96339df84372d41c2ee2242d0464e191"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.38.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "e2eca5806bb1837aa3a0c6044ec959ce510dfdb3385d81f2cc0eb60d695f727e"
        )
    ]
)

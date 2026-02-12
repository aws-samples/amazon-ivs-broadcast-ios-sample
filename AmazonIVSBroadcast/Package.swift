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
            url: "https://broadcast.live-video.net/1.39.0/AmazonIVSBroadcast.xcframework.zip",
            checksum: "382a937b1662f1db35fa900b382df20c913b9d6b9e91b4be2e3bfebb2a973ff6"
        ),
        .binaryTarget(
            name: "AmazonIVSBroadcastStages",
            url: "https://broadcast.live-video.net/1.39.0/AmazonIVSBroadcast-Stages.xcframework.zip",
            checksum: "ce4597eb04838a618fa1a68725caa71328324e60ff35b8733be4068e8aac05c8"
        )
    ]
)

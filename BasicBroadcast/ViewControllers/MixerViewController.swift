//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import UIKit
import AmazonIVSBroadcast
import AVFoundation

class MixerViewController: UIViewController {

    private enum MixerGuide {
        static let borderWidth: CGFloat = 10
        static let bigSize = CGSize(width: 1280, height: 720)
        static let smallSize = CGSize(width: 320, height: 180)
        static let bigPosition = CGPoint(x: 0, y: 0)
        static let smallPositionBottomLeft = CGPoint(x: borderWidth, y: bigSize.height - smallSize.height - borderWidth)
        static let smallPositionTopRight = CGPoint(x: bigSize.width - smallSize.width - borderWidth, y: borderWidth)
        static let smallPositionBottomRight = CGPoint(x: bigSize.width - smallSize.width - borderWidth, y: bigSize.height - smallSize.height - borderWidth)
    }

    @IBOutlet private var previewView: UIView!

    // This broadcast session is the main interaction point with the SDK
    private var broadcastSession: IVSBroadcastSession?

    private var cameraIsSmall = true

    private var cameraSlot: IVSMixerSlotConfiguration!
    private var contentSlot: IVSMixerSlotConfiguration!
    private var logoSlot: IVSMixerSlotConfiguration!

    private var playerLink: AVPlayerCustomImageSource?
    private var logoSource: IVSCustomImageSource?

    private func setupSession() {
        do {
            // Create a custom configuration at 720p60, with transparency enabled (higher memory usage, but needed for the logo watermark).
            let config = IVSBroadcastConfiguration()
            try config.video.setSize(MixerGuide.bigSize)
            try config.video.setTargetFramerate(60)
            config.video.enableTransparency = true

            // This slot will hold the camera and start in the bottom left corner of the stream. It will move during the transition.
            cameraSlot = IVSMixerSlotConfiguration()
            cameraSlot.size = MixerGuide.smallSize
            cameraSlot.position = MixerGuide.smallPositionBottomLeft
            cameraSlot.preferredVideoInput = .camera
            cameraSlot.zIndex = 2
            try cameraSlot.setName("camera")

            // This slot will hold custom content (in this example, an mp4 video) and take up the entire stream. It will move during the transition.
            contentSlot = IVSMixerSlotConfiguration()
            contentSlot.size = MixerGuide.bigSize
            contentSlot.position = MixerGuide.bigPosition
            contentSlot.preferredVideoInput = .userImage
            contentSlot.zIndex = 1
            try contentSlot.setName("content")

            // This slot will be a logo-based watermark and sit in the bottom right corner of the stream. It will not move around.
            logoSlot = IVSMixerSlotConfiguration()
            logoSlot.size = CGSize(width: MixerGuide.smallSize.height, height: MixerGuide.smallSize.height) // 1:1 aspect ratio
            logoSlot.position = CGPoint(x: MixerGuide.bigSize.width - MixerGuide.smallSize.height - MixerGuide.borderWidth, y: MixerGuide.smallPositionBottomRight.y)
            logoSlot.preferredVideoInput = .userImage
            logoSlot.zIndex = 3
            try logoSlot.setTransparency(0.7)
            try logoSlot.setName("logo")

            config.mixer.slots = [
                cameraSlot,
                contentSlot,
                logoSlot,
            ]

            let broadcastSession = try IVSBroadcastSession(configuration: config, descriptors: nil, delegate: nil)

            // This creates a preview of the composited output stream, not an individual source. Because of this there is small
            // amount of delay in the preview since it has to go through a render cycle to composite the sources together.
            // It is also important to note that because our configuration is for a landscape stream using the "fit" aspect mode
            // there will be aggressive letterboxing when holding an iPhone in portrait. Rotating to landscape or using an iPad
            // will provide a larger preview, though the only change is the scaling.
            let preview = try broadcastSession.previewView(with: .fit)
            attachCameraPreview(container: previewView, preview: preview)

            // Attach devices to each slot manually based on the slot names

            let frontCamera = IVSBroadcastSession.listAvailableDevices()
                .filter { $0.type == .camera && $0.position == .front }
                .first
            if let camera = frontCamera {
                broadcastSession.attach(camera, toSlotWithName: cameraSlot.name, onComplete: nil)
            }

            let contentSource = broadcastSession.createImageSource(withName: contentSlot.name)
            broadcastSession.attach(contentSource, toSlotWithName: contentSlot.name)
            let url = Bundle.main.url(forResource: "ivs", withExtension: "mp4")!
            playerLink = AVPlayerCustomImageSource(videoURL: url, imageSource: contentSource)

            let logoSource = broadcastSession.createImageSource(withName: logoSlot.name)
            broadcastSession.attach(logoSource, toSlotWithName: logoSlot.name) { [weak self] _ in
                guard let `self` = self else { return }
                sendImageToSource(name: "ivs", width: Int(self.logoSlot.size.width), height: Int(self.logoSlot.size.height), source: logoSource)
            }
            self.logoSource = logoSource

            self.broadcastSession = broadcastSession
        } catch {
            displayErrorAlert(error, "setting up session")
        }
    }

    @objc
    private func swapSlots() {
        // Swap the camera and content slots
        guard let session = broadcastSession else { return }

        // First we are going to change the size, position, and zIndex of our existing slot models
        // so that the camera swaps between the bottom left corner and full screen
        cameraSlot.position = cameraIsSmall ? MixerGuide.bigPosition : MixerGuide.smallPositionBottomLeft
        cameraSlot.size = cameraIsSmall ? MixerGuide.bigSize : MixerGuide.smallSize
        cameraSlot.zIndex = cameraIsSmall ? 1 : 2
        // And the content slot swaps between full screen and the top right corner.
        contentSlot.position = cameraIsSmall ? MixerGuide.smallPositionTopRight : MixerGuide.bigPosition
        contentSlot.size = cameraIsSmall ? MixerGuide.smallSize : MixerGuide.bigSize
        contentSlot.zIndex = cameraIsSmall ? 2 : 1
        cameraIsSmall.toggle()
        // This is the API that actually causes the slots to animate, just changing the properties above will not do anything.
        // We call transitionSlot on both slots at the same time so the animations happen in parallel.
        var success = session.mixer.transitionSlot(withName: cameraSlot.name, toState: cameraSlot, duration: 0.5)
        // This will short-circuit, so if the first transition fails the second won't execute.
        success = success && session.mixer.transitionSlot(withName: contentSlot.name, toState: contentSlot, duration: 0.5)
        if !success {
            print("⚠️⚠️ Something went wrong executing the transitions. Make sure the provided slot names have matching, attached slots ⚠️⚠️")
        }
    }

    // MARK: - Non SDK related code
    // The below code is AV code that powers the slots, but isn't needed for SDK usage. To keep how SDK APIs
    // grouped together and as clean as possible, all the "extra" code is down here.

    private var displayLink: CADisplayLink!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Tapping on the preview image will swap the small and big slots with an animated transition
        let tap = UITapGestureRecognizer(target: self, action: #selector(swapSlots))
        previewView.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The SDK will not handle disabling the idle timer for you because that might
        // interfere with your application's use of this API elsewhere.
        UIApplication.shared.isIdleTimerDisabled = true
        setupDisplayLink()

        checkAVPermissions { [weak self] granted in
            if granted {
                if self?.broadcastSession == nil {
                    self?.setupSession()
                }
            } else {
                self?.displayPermissionError()
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
    }

    private func setupDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkUpdated(link:)))
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: .main, forMode: .common)
    }

    @objc
    private func displayLinkUpdated(link: CADisplayLink) {
        guard let playerLink = playerLink else { return }
        let nextVSync = link.timestamp + link.duration

        let time = playerLink.output.itemTime(forHostTime: nextVSync)
        guard let pixelBuffer = playerLink.output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            return
        }

        var sampleBuffer: CMSampleBuffer? = nil
        var formatDesc: CMFormatDescription? = nil
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDesc)
        guard let format = formatDesc else {
            return
        }
        var info = CMSampleTimingInfo()
        info.presentationTimeStamp = time
        info.duration = .invalid
        info.decodeTimeStamp = .invalid
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescription: format,
                                                 sampleTiming: &info,
                                                 sampleBufferOut: &sampleBuffer)
        if let sampleBuffer = sampleBuffer {
            playerLink.imageSource.onSampleBuffer(sampleBuffer)
        }
    }

}

// This extension handles all the media work that powers the custom sources. This code shouldn't clutter how the SDK APIs are used.
private func sendImageToSource(name: String, width: Int, height: Int, source: IVSCustomImageSource) {
    var pixelBuffer: CVPixelBuffer? = nil
    let attrs = [
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
    ] as CFDictionary

    CVPixelBufferCreate(kCFAllocatorDefault,
                        width,
                        height,
                        kCVPixelFormatType_32BGRA,
                        attrs,
                        &pixelBuffer)

    guard let pb = pixelBuffer else {
        print("⚠️⚠️ Couldn't create pixel buffer ⚠️⚠️")
        return
    }

    let context = CIContext(options: [.workingColorSpace: NSNull()])

    guard let image = UIImage(named: name), let cgImage = image.cgImage else {
        print("⚠️⚠️ Couldn't load bundled image assets ⚠️⚠️")
        return
    }
    let ciImage = CIImage(cgImage: cgImage)
    context.render(ciImage, to: pb)

    guard let sample = sampleBufferFromPixelBuffer(pb) else {
        print("⚠️⚠️ Couldn't create sample buffer ⚠️⚠️")
        return
    }
    source.onSampleBuffer(sample)
}

private func sampleBufferFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    var sampleBuffer: CMSampleBuffer? = nil
    var formatDesc: CMFormatDescription? = nil
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescriptionOut: &formatDesc)
    guard let format = formatDesc else {
        return nil
    }
    // For images, the timing information on CMSampleBuffers is not necessary, the most recently
    // received image per slot will be processed in the next render loop.
    // For audio however, timing is required and is critical to a smooth audio track.
    var info = CMSampleTimingInfo()
    info.presentationTimeStamp = .invalid
    info.duration = .invalid
    info.decodeTimeStamp = .invalid
    CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                             imageBuffer: pixelBuffer,
                                             formatDescription: format,
                                             sampleTiming: &info,
                                             sampleBufferOut: &sampleBuffer)
    return sampleBuffer
}

private class AVPlayerCustomImageSource {

    let player: AVPlayer
    let output: AVPlayerItemVideoOutput
    let imageSource: IVSCustomImageSource

    private var playerItemObserver: NSKeyValueObservation?
    private var playerItemFullObserver: NSKeyValueObservation?
    private var playerItemEmptyObserver: NSKeyValueObservation?
    private var playerItemLikelyObserver: NSKeyValueObservation?

    private var playerObserver: NSKeyValueObservation?
    private var playerRateObserver: NSKeyValueObservation?

    init(videoURL: URL, imageSource: IVSCustomImageSource) {
        self.imageSource = imageSource
        let item = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: item)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        item.add(output)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false

        playerItemObserver = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            self?.playerItemObserver = nil
            self?.player.play()
        }
    }

}

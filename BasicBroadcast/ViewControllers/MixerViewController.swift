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

    private let deviceDiscovery = IVSDeviceDiscovery()
    private var mixedImageDevice: IVSMixedImageDevice?

    private var cameraIsSmall = true

    private var cameraSource: IVSMixedImageDeviceSource?
    private var contentSource: IVSMixedImageDeviceSource?
    private var logoSource: IVSMixedImageDeviceSource?

    private var playerLink: AVPlayerCustomImageSource?

    private func setupMixedDevice() {
        do {
            // Create a custom configuration at 720p60, with transparency enabled (higher memory usage, but needed for the logo watermark).
            let config = IVSMixedImageDeviceConfiguration()
            config.size = MixerGuide.bigSize
            try config.setTargetFramerate(60)
            config.isTransparencyEnabled = true
            let mixedImageDevice = deviceDiscovery.createMixedImageDevice(with: config)

            // This source will hold the camera and start in the bottom left corner of the stream. It will move during the transition.
            let cameraConfig = IVSMixedImageDeviceSourceConfiguration()
            cameraConfig.size = MixerGuide.smallSize
            cameraConfig.position = MixerGuide.smallPositionBottomLeft
            cameraConfig.zIndex = 2
            if let camera = deviceDiscovery.listLocalDevices().compactMap({ $0 as? IVSCamera }).first {
                let cameraSource = IVSMixedImageDeviceSource(configuration: cameraConfig, device: camera)
                mixedImageDevice.add(cameraSource)
                self.cameraSource = cameraSource
            }


            // This source will hold custom content (in this example, an mp4 video) and take up the entire stream. It will move during the transition.
            let contentConfig = IVSMixedImageDeviceSourceConfiguration()
            contentConfig.size = MixerGuide.bigSize
            contentConfig.position = MixerGuide.bigPosition
            contentConfig.zIndex = 1

            let contentDevice = deviceDiscovery.createImageSource(withName: "content")
            let url = Bundle.main.url(forResource: "ivs", withExtension: "mp4")!
            playerLink = AVPlayerCustomImageSource(videoURL: url, imageSource: contentDevice)

            let contentSource = IVSMixedImageDeviceSource(configuration: contentConfig, device: contentDevice)
            mixedImageDevice.add(contentSource)
            self.contentSource = contentSource


            // This source will be a logo-based watermark and sit in the bottom right corner of the stream. It will not move around.
            let logoConfig = IVSMixedImageDeviceSourceConfiguration()
            logoConfig.size = CGSize(width: MixerGuide.smallSize.height, height: MixerGuide.smallSize.height) // 1:1 aspect ratio
            logoConfig.position = CGPoint(x: MixerGuide.bigSize.width - MixerGuide.smallSize.height - MixerGuide.borderWidth, y: MixerGuide.smallPositionBottomRight.y)
            logoConfig.zIndex = 3
            try logoConfig.setAlpha(0.3)

            let logoDevice = deviceDiscovery.createImageSource(withName: "logo")
            sendImageToSource(name: "ivs", width: Int(logoConfig.size.width), height: Int(logoConfig.size.height), source: logoDevice)
            let logoSource = IVSMixedImageDeviceSource(configuration: logoConfig, device: logoDevice)
            mixedImageDevice.add(logoSource)
            self.logoSource = logoSource

            // This creates a preview of the composited output stream, not an individual source. Because of this there is small
            // amount of delay in the preview since it has to go through a render cycle to composite the sources together.
            // It is also important to note that because our configuration is for a landscape stream using the "fit" aspect mode
            // there will be aggressive letterboxing when holding an iPhone in portrait. Rotating to landscape or using an iPad
            // will provide a larger preview, though the only change is the scaling.
            let preview = try mixedImageDevice.previewView(with: .fit)
            attachCameraPreview(container: previewView, preview: preview)

            self.mixedImageDevice = mixedImageDevice
        } catch {
            displayErrorAlert(error, "setting up device")
        }
    }

    @objc
    private func swapSources() {
        // Swap the camera and content sources
        guard let cameraSource = self.cameraSource, let contentSource = self.contentSource else { return }

        // First we are going to change the size, position, and zIndex of our existing source models
        // so that the camera swaps between the bottom left corner and full screen
        let newCameraConfig = cameraSource.configuration
        newCameraConfig.position = cameraIsSmall ? MixerGuide.bigPosition : MixerGuide.smallPositionBottomLeft
        newCameraConfig.size = cameraIsSmall ? MixerGuide.bigSize : MixerGuide.smallSize
        newCameraConfig.zIndex = cameraIsSmall ? 1 : 2

        // And the content source swaps between full screen and the top right corner.
        let newContentConfig = contentSource.configuration
        newContentConfig.position = cameraIsSmall ? MixerGuide.smallPositionTopRight : MixerGuide.bigPosition
        newContentConfig.size = cameraIsSmall ? MixerGuide.smallSize : MixerGuide.bigSize
        newContentConfig.zIndex = cameraIsSmall ? 2 : 1
        cameraIsSmall.toggle()

        // This is the API that actually causes the sources to animate, just changing the properties above will not do anything.
        // We call transition on both sources at the same time so the animations happen in parallel.
        cameraSource.transition(to: newCameraConfig, duration: 0.5)
        contentSource.transition(to: newContentConfig, duration: 0.5)
    }

    // MARK: - Non SDK related code
    // The below code is AV code that powers the sources, but isn't needed for SDK usage. To keep how SDK APIs
    // grouped together and as clean as possible, all the "extra" code is down here.

    private var displayLink: CADisplayLink!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Tapping on the preview image will swap the small and big sources with an animated transition
        let tap = UITapGestureRecognizer(target: self, action: #selector(swapSources))
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
                if self?.mixedImageDevice == nil {
                    self?.setupMixedDevice()
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
    // received image per source will be processed in the next render loop.
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

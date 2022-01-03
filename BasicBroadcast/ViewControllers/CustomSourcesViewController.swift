//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import UIKit
import AmazonIVSBroadcast
import AVFoundation

class CustomSourcesViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    @IBOutlet private var previewView: UIView!
    @IBOutlet private var labelSoundDb: UILabel!

    // This broadcast session is the main interaction point with the SDK
    private var broadcastSession: IVSBroadcastSession?

    private var customAudioSource: IVSCustomAudioSource?
    private var customImageSource: IVSCustomImageSource?

    private var audioOutput: AVCaptureOutput?
    private var videoOutput: AVCaptureOutput?

    private var captureSession: AVCaptureSession?

    private var orientation: AVCaptureVideoOrientation = .portrait

    private let queue = DispatchQueue(label: "media-queue")

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The SDK will not handle disabling the idle timer for you because that might
        // interfere with your application's use of this API elsewhere.
        UIApplication.shared.isIdleTimerDisabled = true

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

    private func setupSession() {
        do {
            // Create a custom configuration at 720p60
            let config = IVSBroadcastConfiguration()
            try config.video.setSize(CGSize(width: 1280, height: 720))
            try config.video.setTargetFramerate(60)

            // This slot will eventually bind to a custom image and audio source. This will be done manually after the creation
            // of the IVSBroadcastSession. In order to bind custom sources, make sure the `preferredAudioInput` and `preferredVideoInput`
            // properties of the slot are set to `userAudio` and `userImage` respectively. This will allow both of our custom
            // sources to bind to the same slot.
            let customSlot = IVSMixerSlotConfiguration()
            customSlot.size = config.video.size
            customSlot.position = CGPoint(x: 0, y: 0)
            customSlot.preferredAudioInput = .userAudio
            customSlot.preferredVideoInput = .userImage
            try customSlot.setName("custom-slot")

            config.mixer.slots = [customSlot]

            // Our AVCaptureSession will be managing the AVAudioSession independently
            IVSBroadcastSession.applicationAudioSessionStrategy = .noAction
            let broadcastSession = try IVSBroadcastSession(configuration: config,
                                                           descriptors: nil,
                                                           delegate: self)

            // Create custom audio and image sources by requesting them from the IVSBroadcastSession.
            // These can be given any name, but will both be attached to the slot that was configured above.
            // Custom sources are useful because they allow the host application to provide any type of image
            // and audio data directly to the SDK. In this example, we provide camera and microphone input
            // managed by a local AVCaptureSession, instead of letting the SDK control those devices.
            // However you can also provide MP4 video data or static image data as seen in `MixerViewController`.
            let customAudioSource = broadcastSession.createAudioSource(withName: "custom-audio")
            broadcastSession.attach(customAudioSource, toSlotWithName: "custom-slot")
            self.customAudioSource = customAudioSource

            let customImageSource = broadcastSession.createImageSource(withName: "custom-image")
            broadcastSession.attach(customImageSource, toSlotWithName: "custom-slot")
            self.customImageSource = customImageSource

            // We can still preview custom sources. This will act similar to a direct camera preview, just using the SDK as the GPU layer.
            attachCameraPreview(container: previewView, preview: try customImageSource.previewView(with: .fit))
            
            self.broadcastSession = broadcastSession

            setupCaptureSession()
        } catch {
            displayErrorAlert(error, "setting up session")
        }
    }

    private func setupCaptureSession() {
        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()

        if
            let videoDevice = AVCaptureDevice.default(for: .video),
            let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
            captureSession.canAddInput(videoInput)
        {
            captureSession.addInput(videoInput)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                self.videoOutput = videoOutput
            }
        }

        if
            let audioDevice = AVCaptureDevice.default(for: .audio),
            let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
            captureSession.canAddInput(audioInput)
        {
            captureSession.addInput(audioInput)

            let audioOutput = AVCaptureAudioDataOutput()
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            if captureSession.canAddOutput(audioOutput) {
                captureSession.addOutput(audioOutput)
                self.audioOutput = audioOutput
            }
        }

        captureSession.commitConfiguration()
        captureSession.startRunning()

        self.captureSession = captureSession
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoOutput {
            // This keeps the images coming in with the correct orientation.
            connection.videoOrientation = orientation
            // A host application can do further processing of this sample by applying a CIFilter, custom Metal shader, or
            // by using a more complex pipeline that provides services like a beauty filter.
            // It is important that the processing finishes before the next frame arrives, otherwise frames will start to backup.
            // If a new video sample does not arrive to the SDK in time, the previous sample will be repeated in the broadcast
            // until a new frame arrives.
            customImageSource?.onSampleBuffer(sampleBuffer)
        } else if output == audioOutput {
            // A host application can do further processing of this sample here. It is required for processing to happen before
            // the next sample arrives, otherwise audio may be dropped (it will be replaced with silence).
            customAudioSource?.onSampleBuffer(sampleBuffer)
        }
    }

    override func viewDidLayoutSubviews() {
        orientation = AVCaptureVideoOrientation(rawValue: UIApplication.shared.statusBarOrientation.rawValue)!
    }
}


extension CustomSourcesViewController: IVSBroadcastSession.Delegate {
    func broadcastSession(_ session: IVSBroadcastSession, didChange state: IVSBroadcastSession.State) {}
    func broadcastSession(_ session: IVSBroadcastSession, didEmitError error: Error) {}
    func broadcastSession(_ session: IVSBroadcastSession, audioStatsUpdatedWithPeak peak: Double, rms: Double) {
        labelSoundDb.text = "db: \(rms)"
    }
}

//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import UIKit
import AmazonIVSBroadcast
import AVFoundation

class CustomSourcesViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    @IBOutlet private var endpointField: UITextField!
    @IBOutlet private var streamKeyField: UITextField!
    @IBOutlet private var startButton: UIButton!
    
    @IBOutlet private var previewView: UIView!
    @IBOutlet private var connectionView: UIView!
    @IBOutlet private var labelSoundDb: UILabel!
    
    @IBOutlet private var applyFilterButton: UIButton!
    
    // State management
    private var isRunning = false {
        didSet {
            startButton.setTitle(isRunning ? "Stop" : "Start", for: .normal)
        }
    }
    
    private var filterHelper: FilterHelper?
    
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Tapping on the preview image will dismiss the keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(previewTapped))
        previewView.addGestureRecognizer(tap)
        
        // Auto complete the last used endpoint/key pair.
        let lastAuth = UserDefaultsAuthDao.shared.lastUsedAuth()
        endpointField.text = lastAuth?.endpoint
        streamKeyField.text = lastAuth?.streamKey
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.broadcastSession?.stop()
    }
    
    @objc
    private func previewTapped() {
        // This allows the user to tap on the preview view to dismiss the keyboard when
        // entering the endpoint and stream key.
        view.endEditing(false)
    }

    private func setupSession() {
        do {
            // Create a custom configuration at 720p60
            let config = IVSBroadcastConfiguration()
            try config.video.setSize(CGSize(width: 720, height: 1280))
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
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
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
            
            connection.videoOrientation = orientation
            
            // This keeps the images coming in with the correct orientation.
            // connection.videoOrientation = orientation
            // A host application can do further processing of this sample by applying a CIFilter, custom Metal shader, or
            // by using a more complex pipeline that provides services like a beauty filter.
            
            // As an example using CIFilter
            let finalBuffer = filterHelper?.process(inputBuffer: sampleBuffer) ?? sampleBuffer
            
            // It is important that the processing finishes before the next frame arrives, otherwise frames will start to backup.
            // If a new video sample does not arrive to the SDK in time, the previous sample will be repeated in the broadcast
            // until a new frame arrives.
            customImageSource?.onSampleBuffer(finalBuffer)
        } else if output == audioOutput {
            // A host application can do further processing of this sample here. It is required for processing to happen before
            // the next sample arrives, otherwise audio may be dropped (it will be replaced with silence).
            customAudioSource?.onSampleBuffer(sampleBuffer)
        }
    }

    
    @IBAction private func startTapped(_ sender: UIButton) {
        if isRunning {
            // Stop the session if we're running
            broadcastSession?.stop()
            isRunning = false
        } else {
            // Start the session if we're not running.
            guard let endpointPath = endpointField.text, let url = URL(string: endpointPath), let key = streamKeyField.text else {
                let alert = UIAlertController(title: "Invalid Endpoint",
                                              message: "The endpoint or streamkey you provided is invalid",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
            do {
                // store this endpoint/key pair to share with the screen capture extension
                // and to auto-complete the next time this app is launched
                let authItem = AuthItem(endpoint: endpointPath, streamKey: key)
                UserDefaultsAuthDao.shared.insert(authItem)
                try broadcastSession?.start(with: url, streamKey: key)
                isRunning = true
            } catch {
                displayErrorAlert(error, "starting session")
            }
        }
    }
    
    @IBAction private func applyFilterTapped(_ sender: UIButton) {
        if filterHelper == nil {
            filterHelper = FilterHelper()
        } else {
            filterHelper = nil
        }
    }
    
    override func viewDidLayoutSubviews() {
        orientation = AVCaptureVideoOrientation(rawValue: UIApplication.shared.statusBarOrientation.rawValue)!
    }
}


extension CustomSourcesViewController: IVSBroadcastSession.Delegate {
    func broadcastSession(_ session: IVSBroadcastSession, didChange state: IVSBroadcastSession.State) {
        print("IVSBroadcastSession state did change to \(state.rawValue)")
        DispatchQueue.main.async {
            switch state {
            case .invalid: self.connectionView.backgroundColor = .darkGray
            case .connecting: self.connectionView.backgroundColor = .yellow
            case .connected: self.connectionView.backgroundColor = .green
            case .disconnected:
                self.connectionView.backgroundColor = .darkGray
                self.isRunning = false
            case .error:
                self.connectionView.backgroundColor = .red
                self.isRunning = false
            @unknown default: self.connectionView.backgroundColor = .darkGray
            }
        }
    }
    func broadcastSession(_ session: IVSBroadcastSession, didEmitError error: Error) {}
    func broadcastSession(_ session: IVSBroadcastSession, audioStatsUpdatedWithPeak peak: Double, rms: Double) {
        labelSoundDb.text = "db: \(rms)"
    }
}

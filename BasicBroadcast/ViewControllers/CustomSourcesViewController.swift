//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import UIKit
import AmazonIVSBroadcast
import AVFoundation

@available(iOS 13.0, *)
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
    private var broadcastConfig: IVSBroadcastConfiguration?

    private var customAudioSource: IVSCustomAudioSource?
    private var customImageSource: IVSCustomImageSource?
    private var secondaryImageSource: IVSCustomImageSource?

    private var audioOutput: AVCaptureOutput?
    private var videoOutput: AVCaptureOutput?
    private var secondaryVideoOutput: AVCaptureOutput?

    private var captureSession: AVCaptureSession?
    private var multiCamSession: AVCaptureMultiCamSession?

    private var orientation: AVCaptureVideoOrientation = .portrait

    private let queue = DispatchQueue(label: "media-queue")
    private let secondaryQueue = DispatchQueue(label: "secondary-media-queue")

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

            // Primary slot for back camera (full screen)
            let customSlot = IVSMixerSlotConfiguration()
            customSlot.size = config.video.size
            customSlot.position = CGPoint(x: 0, y: 0)
            customSlot.preferredAudioInput = .userAudio
            customSlot.preferredVideoInput = .userImage
            try customSlot.setName("custom-slot")

            // Secondary slot for front camera (picture-in-picture style)
            // Position it in the top-right corner at 1/4 size
            let secondarySlot = IVSMixerSlotConfiguration()
            let pipSize = CGSize(width: 180, height: 320) // 1/4 of 720x1280
            secondarySlot.size = pipSize
            secondarySlot.position = CGPoint(x: config.video.size.width - pipSize.width - 20, y: 20)
            secondarySlot.preferredVideoInput = .userImage
            secondarySlot.zIndex = 1 // Place on top of primary camera
            try secondarySlot.setName("secondary-slot")

            config.mixer.slots = [customSlot, secondarySlot]

            // Store configuration for later reference
            self.broadcastConfig = config

            // Our AVCaptureSession will be managing the AVAudioSession independently
            IVSBroadcastSession.applicationAudioSessionStrategy = .noAction
            let broadcastSession = try IVSBroadcastSession(configuration: config,
                                                           descriptors: nil,
                                                           delegate: self)

            // Create custom audio source for microphone
            let customAudioSource = broadcastSession.createAudioSource(withName: "custom-audio")
            broadcastSession.attach(customAudioSource, toSlotWithName: "custom-slot")
            self.customAudioSource = customAudioSource

            // Create primary image source for back camera
            let customImageSource = broadcastSession.createImageSource(withName: "custom-image")
            broadcastSession.attach(customImageSource, toSlotWithName: "custom-slot")
            self.customImageSource = customImageSource

            // Create secondary image source for front camera
            let secondaryImageSource = broadcastSession.createImageSource(withName: "secondary-image")
            broadcastSession.attach(secondaryImageSource, toSlotWithName: "secondary-slot")
            self.secondaryImageSource = secondaryImageSource

            // Preview shows the primary camera
            attachCameraPreview(container: previewView, preview: try customImageSource.previewView(with: .fit))
            
            self.broadcastSession = broadcastSession

            setupCaptureSession()
        } catch {
            displayErrorAlert(error, "setting up session")
        }
    }

    private func setupCaptureSession() {
        // Check if multi-cam is supported on this device
        if AVCaptureMultiCamSession.isMultiCamSupported {
            setupMultiCamSession()
        } else {
            setupSingleCamSession()
        }
    }
    
    private func setupMultiCamSession() {
        let multiCamSession = AVCaptureMultiCamSession()
        multiCamSession.beginConfiguration()

        // Setup primary camera (back camera)
        if let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let backCameraInput = try? AVCaptureDeviceInput(device: backCamera),
           multiCamSession.canAddInput(backCameraInput) {
            
            multiCamSession.addInputWithNoConnections(backCameraInput)
            
            let backVideoOutput = AVCaptureVideoDataOutput()
            backVideoOutput.setSampleBufferDelegate(self, queue: queue)
            backVideoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            
            if multiCamSession.canAddOutput(backVideoOutput) {
                multiCamSession.addOutputWithNoConnections(backVideoOutput)
                
                // Create connection for back camera
                if let backVideoPort = backCameraInput.ports(for: .video, sourceDeviceType: backCamera.deviceType, sourceDevicePosition: backCamera.position).first {
                    let backConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backVideoOutput)
                    if multiCamSession.canAddConnection(backConnection) {
                        multiCamSession.addConnection(backConnection)
                        self.videoOutput = backVideoOutput
                    }
                }
            }
        }

        // Setup secondary camera (front camera) - fully functional
        if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let frontCameraInput = try? AVCaptureDeviceInput(device: frontCamera),
           multiCamSession.canAddInput(frontCameraInput) {
            
            multiCamSession.addInputWithNoConnections(frontCameraInput)
            
            let frontVideoOutput = AVCaptureVideoDataOutput()
            frontVideoOutput.setSampleBufferDelegate(self, queue: secondaryQueue)
            frontVideoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            
            if multiCamSession.canAddOutput(frontVideoOutput) {
                multiCamSession.addOutputWithNoConnections(frontVideoOutput)
                
                // Create connection for front camera
                if let frontVideoPort = frontCameraInput.ports(for: .video, sourceDeviceType: frontCamera.deviceType, sourceDevicePosition: frontCamera.position).first {
                    let frontConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontVideoOutput)
                    if multiCamSession.canAddConnection(frontConnection) {
                        multiCamSession.addConnection(frontConnection)
                        self.secondaryVideoOutput = frontVideoOutput
                    }
                }
            }
        }

        // Setup audio
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           multiCamSession.canAddInput(audioInput) {
            
            multiCamSession.addInput(audioInput)
            
            let audioOutput = AVCaptureAudioDataOutput()
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            if multiCamSession.canAddOutput(audioOutput) {
                multiCamSession.addOutput(audioOutput)
                self.audioOutput = audioOutput
            }
        }

        multiCamSession.commitConfiguration()
        multiCamSession.startRunning()

        self.multiCamSession = multiCamSession
        self.captureSession = multiCamSession
    }
    
    private func setupSingleCamSession() {
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
            // Primary camera (back camera)
            connection.videoOrientation = orientation
            
            // Apply filter if enabled
            let finalBuffer = filterHelper?.process(inputBuffer: sampleBuffer) ?? sampleBuffer
            
            // Send to primary image source for broadcasting
            customImageSource?.onSampleBuffer(finalBuffer)
            
        } else if output == secondaryVideoOutput {
            // Secondary camera (front camera)
            connection.videoOrientation = orientation
            
            // You can apply different filters or processing to the secondary camera
            // For now, we'll send it directly to the secondary image source
            secondaryImageSource?.onSampleBuffer(sampleBuffer)
            
        } else if output == audioOutput {
            // Audio processing
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
    
    // MARK: - Multi-Cam Helper Methods
    
    /// Toggle secondary camera visibility
    private func toggleSecondaryCamera(enabled: Bool) {
        guard let broadcastSession = broadcastSession,
              let secondaryImageSource = secondaryImageSource else { return }
        
        if enabled {
            // Attach secondary camera to its slot
            broadcastSession.attach(secondaryImageSource, toSlotWithName: "secondary-slot")
        } else {
            // Detach secondary camera from its slot
            broadcastSession.detach(secondaryImageSource)
        }
    }
    
    /// Swap primary and secondary cameras
    private func swapCameras() {
        // Swap the outputs
        let temp = videoOutput
        videoOutput = secondaryVideoOutput
        secondaryVideoOutput = temp
        
        // Swap the image sources
        let tempSource = customImageSource
        customImageSource = secondaryImageSource
        secondaryImageSource = tempSource
    }
    
    /// Switch the active camera between front and back
    private func switchCamera(to position: AVCaptureDevice.Position) {
        guard let multiCamSession = multiCamSession else { return }
        
        multiCamSession.beginConfiguration()
        
        // Find and remove existing video connections
        if let existingOutput = videoOutput as? AVCaptureVideoDataOutput {
            existingOutput.connections.forEach { connection in
                if connection.isVideoOrientationSupported {
                    multiCamSession.removeConnection(connection)
                }
            }
        }
        
        // Add new camera
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let cameraInput = try? AVCaptureDeviceInput(device: camera) {
            
            if !multiCamSession.inputs.contains(cameraInput) {
                if multiCamSession.canAddInput(cameraInput) {
                    multiCamSession.addInputWithNoConnections(cameraInput)
                }
            }
            
            if let videoOutput = videoOutput as? AVCaptureVideoDataOutput,
               let videoPort = cameraInput.ports(for: .video, sourceDeviceType: camera.deviceType, sourceDevicePosition: camera.position).first {
                let connection = AVCaptureConnection(inputPorts: [videoPort], output: videoOutput)
                if multiCamSession.canAddConnection(connection) {
                    multiCamSession.addConnection(connection)
                }
            }
        }
        
        multiCamSession.commitConfiguration()
    }
    
    /// Get all available cameras for multi-cam
    private func getAvailableCameras() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discoverySession.devices
    }
    
    /// Adjust secondary camera position and size
    private func updateSecondarySlot(position: CGPoint, size: CGSize) {
        guard let config = broadcastConfig else { return }
        
        // Find and update the secondary slot
        if let secondarySlot = config.mixer.slots.first(where: { $0.name == "secondary-slot" }) {
            secondarySlot.position = position
            secondarySlot.size = size
        }
    }
}


@available(iOS 13.0, *)
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

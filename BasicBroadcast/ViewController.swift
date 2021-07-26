//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import UIKit
import AmazonIVSBroadcast
import AVFoundation

class ViewController: UIViewController {

    // MARK: - Properties

    // UI Outlets
    @IBOutlet private var endpointField: UITextField!
    @IBOutlet private var streamkeyField: UITextField!
    @IBOutlet private var startButton: UIButton!

    @IBOutlet private var previewView: UIView!
    @IBOutlet private var connectionView: UIView!

    @IBOutlet private var cameraButton: UIButton!
    @IBOutlet private var microphoneButton: UIButton!

    // State management
    private var isRunning = false {
        didSet {
            startButton.setTitle(isRunning ? "Stop" : "Start", for: .normal)
        }
    }
    private var attachedCamera: IVSDevice? {
        didSet {
            cameraButton.setTitle(attachedCamera?.descriptor().friendlyName ?? "None", for: .normal)

            if let preview = try? (attachedCamera as? IVSImageDevice)?.previewView(with: .fill) {
                attachCameraPreview(preview)
            } else {
                previewView.subviews.forEach { $0.removeFromSuperview() }
            }
        }
    }
    private var attachedMicrophone: IVSDevice? {
        didSet {
            microphoneButton.setTitle(attachedMicrophone?.descriptor().friendlyName ?? "None", for: .normal)
        }
    }

    // This broadcast session is the main interaction point with the SDK
    private var broadcastSession: IVSBroadcastSession?

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Tapping on the preview image will dismiss the keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(previewTapped))
        previewView.addGestureRecognizer(tap)

        // Auto complete the last used endpoint/key pair.
        let lastAuth = UserDefaultsAuthDao.shared.lastUsedAuth()
        endpointField.text = lastAuth?.endpoint
        streamkeyField.text = lastAuth?.streamKey
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The SDK will not handle disabling the idle timer for you because that might
        // interfere with your application's use of this API elsewhere.
        UIApplication.shared.isIdleTimerDisabled = true
        checkPermissionsThenSetup()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - User Interaction

    @IBAction private func startTapped(_ sender: UIButton) {
        if isRunning {
            // Stop the session if we're running
            broadcastSession?.stop()
            isRunning = false
        } else {
            // Start the session if we're not running.
            guard let endpointPath = endpointField.text, let url = URL(string: endpointPath), let key = streamkeyField.text else {
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

    @IBAction private func cameraTapped(_ sender: UIButton) {
        chooseDevice(sender, type: .camera, deviceName: "Camera", deviceSelected: setCamera(_:))
    }

    @IBAction private func microphoneTapped(_ sender: UIButton) {
        chooseDevice(sender, type: .microphone, deviceName: "Microphone", deviceSelected: setMicrophone(_:))
    }

    private func chooseDevice(_ sender: UIButton, type: IVSDeviceType, deviceName: String, deviceSelected: @escaping (IVSDeviceDescriptor) -> Void) {
        let alert = UIAlertController(title: "Choose a \(deviceName)", message: nil, preferredStyle: .actionSheet)
        IVSBroadcastSession.listAvailableDevices()
            .filter { $0.type == type }
            .forEach { device in
                alert.addAction(UIAlertAction(title: device.friendlyName, style: .default, handler: { _ in
                    deviceSelected(device)
                }))
            }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = sender
        alert.popoverPresentationController?.sourceRect = sender.bounds
        present(alert, animated: true)
    }

    @objc
    private func previewTapped() {
        // This allows the user to tap on the preview view to dismiss the keyboard when
        // entering the endpoint and stream key.
        view.endEditing(false)
    }

    // MARK: - AV Permissions

    private func checkPermissionsThenSetup() {
        // Make sure we have both audio and video permissions before setting up the broadcast session.
        checkOrGetPermission(for: .video) { [weak self] (granted) in
            guard granted else {
                self?.displayPermissionError()
                return
            }
            self?.checkOrGetPermission(for: .audio) { [weak self] (granted) in
                guard granted else {
                    self?.displayPermissionError()
                    return
                }
                if (self?.broadcastSession == nil) {
                    self?.setupSession()
                }
            }
        }
    }

    private func checkOrGetPermission(for mediaType: AVMediaType, _ result: @escaping (Bool) -> Void) {
        func mainThreadResult(_ success: Bool) {
            DispatchQueue.main.async { result(success) }
        }
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: mainThreadResult(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: mediaType) { mainThreadResult($0) }
        case .denied, .restricted: mainThreadResult(false)
        @unknown default: mainThreadResult(false)
        }
    }

    private func displayPermissionError() {
        let alert = UIAlertController(title: "Permission Error",
                                      message: "This app does not have access to either the microphone or camera permissions. Please go into system settings and enable thees permissions for this app.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Utility Functions

    private func setupSession() {
        do {
            // Create the session with a preset config and camera/microphone combination.
            let broadcastSession = try IVSBroadcastSession(configuration: IVSPresets.configurations().standardPortrait(),
                                                           descriptors: IVSPresets.devices().frontCamera(),
                                                           delegate: self)
            broadcastSession.awaitDeviceChanges { [weak self] in
                let devices = broadcastSession.listAttachedDevices()
                let cameras = devices
                    .filter { $0.descriptor().type == .camera }
                    .compactMap { $0 as? IVSImageDevice }

                self?.attachedCamera = cameras.first
                self?.attachedMicrophone = devices.first(where: { $0.descriptor().type == .microphone })
            }
            self.broadcastSession = broadcastSession
        } catch {
            displayErrorAlert(error, "setting up session")
        }
    }

    private func displayErrorAlert(_ error: Error, _ msg: String) {
        // Display the error if something went wrong.
        // This is mainly for debugging. Human-readable error descriptions are provided for
        // `IVSBroadcastError`s, but they may not be especially useful for the end user.
        let alert = UIAlertController(title: "Error \(msg) (Code: \((error as NSError).code))",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func setCamera(_ device: IVSDeviceDescriptor) {
        guard let broadcastSession = self.broadcastSession else { return }

        // either attach or exchange based on current state.
        if attachedCamera == nil {
            broadcastSession.attach(device, toSlotWithName: nil) { newDevice, _ in
                self.attachedCamera = newDevice
            }
        } else if let currentCamera = self.attachedCamera, currentCamera.descriptor().urn != device.urn {
            broadcastSession.exchangeOldDevice(currentCamera, withNewDevice: device) { newDevice, _ in
                self.attachedCamera = newDevice
            }
        }
    }

    func setMicrophone(_ device: IVSDeviceDescriptor) {
        guard let broadcastSession = self.broadcastSession else { return }

        // either attach or exchange based on current state.
        if attachedMicrophone == nil {
            broadcastSession.attach(device, toSlotWithName: nil) { newDevice, _ in
                self.attachedMicrophone = newDevice
            }
        } else if let currentMic = self.attachedMicrophone, currentMic.descriptor().urn != device.urn {
            broadcastSession.exchangeOldDevice(currentMic, withNewDevice: device) { newDevice, _ in
                self.attachedMicrophone = newDevice
            }
        }
    }

    private func refreshAttachedDevices() {
        guard let session = broadcastSession else { return }
        let attachedDevices = session.listAttachedDevices()
        let cameras = attachedDevices.filter { $0.descriptor().type == .camera }
        let microphones = attachedDevices.filter { $0.descriptor().type == .microphone }
        attachedCamera = cameras.first
        attachedMicrophone = microphones.first
    }

    private func attachCameraPreview(_ cameraView: UIView) {
        // Clear current view, and then attach the new view.
        previewView.subviews.forEach { $0.removeFromSuperview() }
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(cameraView)
        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: previewView.topAnchor, constant: 0),
            cameraView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 0),
            cameraView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 0),
            cameraView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 0),
        ])
    }

}

// MARK: - IVS Broadcast SDK Delegate

extension ViewController : IVSBroadcastSession.Delegate {

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

    func broadcastSession(_ session: IVSBroadcastSession, didEmitError error: Error) {
        displayErrorAlert(error, "in SDK")
    }

    func broadcastSession(_ session: IVSBroadcastSession, didAddDevice descriptor: IVSDeviceDescriptor) {
        print("IVSBroadcastSession did discover device \(descriptor)")
        // When audio routes change (like a Bluetooth headset turning off),
        // Apple will automatically switch the current route. Wait for the
        // IVS SDK to catch up and then refresh the current connected devices.
        session.awaitDeviceChanges {
            self.refreshAttachedDevices()
        }
    }

    func broadcastSession(_ session: IVSBroadcastSession, didRemoveDevice descriptor: IVSDeviceDescriptor) {
        print("IVSBroadcastSession did lose device \(descriptor)")
        // Same comment as didAddDevice above.
        session.awaitDeviceChanges {
            self.refreshAttachedDevices()
        }
    }

    func broadcastSession(_ session: IVSBroadcastSession, audioStatsUpdatedWithPeak peak: Double, rms: Double) {
        // This fires frequently, so we don't log it here.
    }

}

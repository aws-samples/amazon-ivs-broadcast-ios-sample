//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import AVFoundation
import Foundation
import UIKit

func checkAVPermissions(_ result: @escaping (Bool) -> Void) {
    // Make sure we have both audio and video permissions before setting up the broadcast session.
    checkOrGetPermission(for: .video) { granted in
        guard granted else {
            result(false)
            return
        }
        checkOrGetPermission(for: .audio) { granted in
            guard granted else {
                result(false)
                return
            }
            result(true)
        }
    }
}

func checkOrGetPermission(for mediaType: AVMediaType, _ result: @escaping (Bool) -> Void) {
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

func attachCameraPreview(container: UIView, preview: UIView) {
    // Clear current view, and then attach the new view.
    container.subviews.forEach { $0.removeFromSuperview() }
    preview.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(preview)
    NSLayoutConstraint.activate([
        preview.topAnchor.constraint(equalTo: container.topAnchor, constant: 0),
        preview.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 0),
        preview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
        preview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0),
    ])
}

extension UIViewController {
    func displayPermissionError() {
        let alert = UIAlertController(title: "Permission Error",
                                      message: "This app does not have access to either the microphone or camera permissions. Please go into system settings and enable thees permissions for this app.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func displayErrorAlert(_ error: Error, _ msg: String) {
        // Display the error if something went wrong.
        // This is mainly for debugging. Human-readable error descriptions are provided for
        // `IVSBroadcastError`s, but they may not be especially useful for the end user.
        let alert = UIAlertController(title: "Error \(msg) (Code: \((error as NSError).code))",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

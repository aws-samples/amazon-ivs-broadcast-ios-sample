//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import AmazonIVSBroadcast
import ReplayKit

private enum IVSReplayKitError: Error {
    case setupError(_ error: Error)
    case authError
    case invalidEndpoint
}

extension IVSReplayKitError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? {
        switch self {
        case .setupError(let error):
            return "Error setting up the IVS SDK - \(error.localizedDescription)"
        case .authError:
            return "No Endpoint and Stream Key pair were found. You must broadcasting with the main app first."
        case .invalidEndpoint:
            return "The stored Endpoint and Stream Key pair was invalid."
        }
    }
    public var localizedFailureReason: String? {
        return errorDescription
    }
    public var failureReason: String? {
        return errorDescription
    }
    public var localizedDescription: String? {
        return errorDescription
    }
    public var description: String {
        return errorDescription ?? "Unknown"
    }
}

class SampleHandler: RPBroadcastSampleHandler {

    private let authDao = UserDefaultsAuthDao.shared
    private var authItem: AuthItem?

    private var session: IVSReplayKitBroadcastSession?

    override init() {
        super.init()

        // Since there is no UI in this extension, load the last used endpoint/key pair from
        // the main app.
        guard let auth = authDao.lastUsedAuth() else {
            finishBroadcastWithError(IVSReplayKitError.authError)
            return
        }
        authItem = auth

        do {
            let config = IVSPresets.configurations().standardLandscape()
            try config.video.setSize(CGSize(width: 1280, height: 720))
            try config.video.setMaxBitrate(4_000_000)
            try config.video.setInitialBitrate(2_000_000)
            try config.video.setMinBitrate(500_000)
            try config.video.setTargetFramerate(60)

            self.session = try IVSReplayKitBroadcastSession(videoConfiguration: config.video,
                                                            audioConfig: config.audio,
                                                            delegate: self)
        } catch {
            finishBroadcastWithError(IVSReplayKitError.setupError(error))
            return
        }
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        do {
            guard let session = session, let authItem = authItem, let url = URL(string: authItem.endpoint) else {
                throw IVSReplayKitError.invalidEndpoint
            }
            try session.start(with: url, streamKey: authItem.streamKey)
        } catch {
            finishBroadcastWithError(error)
        }
    }

    override func broadcastFinished() {
        session?.stop()
        session = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard let session = session else { return }
        switch sampleBufferType {
        case RPSampleBufferType.video:
            let imageSource = session.systemImageSource;
            if let orientationAttachment =  CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
               let orientation = CGImagePropertyOrientation(rawValue: orientationAttachment.uint32Value) {
                switch orientation {
                case .up, .upMirrored:
                    imageSource.setHandsetRotation(0)
                case .down, .downMirrored:
                    imageSource.setHandsetRotation(Float.pi)
                case .right, .rightMirrored:
                    imageSource.setHandsetRotation(-(Float.pi / 2))
                case .left, .leftMirrored:
                    imageSource.setHandsetRotation((Float.pi / 2))
                }
            }
            imageSource.onSampleBuffer(sampleBuffer)
        case RPSampleBufferType.audioApp:
            session.systemAudioSource.onSampleBuffer(sampleBuffer)
        case RPSampleBufferType.audioMic:
            session.microphoneSource.onSampleBuffer(sampleBuffer)
        @unknown default:
            fatalError("Unknown type of sample buffer")
        }
    }
}

extension SampleHandler: IVSBroadcastSession.Delegate {

    func broadcastSession(_ session: IVSBroadcastSession, didChange state: IVSBroadcastSession.State) {
        print("IVSBroadcastSession state did change - \(state.rawValue)")
    }

    func broadcastSession(_ session: IVSBroadcastSession, didEmitError error: Error) {
        let nsError = error as NSError
        if nsError.userInfo[IVSBroadcastErrorIsFatalKey] as? Bool == true {
            finishBroadcastWithError(error)
        } else {
            print("IVSBroadcastSession did emit error - \(error)")
        }
    }

}

//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import AmazonIVSBroadcast
import UIKit

protocol ParticipantCollectionViewCellDelegate: AnyObject {
    func toggleAudioOnlySubscribe(forParticipant participantId: String)
    func toggleEnableStats(forParticipant participantId: String)
}

class ParticipantCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet private var previewView: UIView!
    @IBOutlet private var participantIdWrapperView: UIView!
    @IBOutlet private var participantIdLabel: UILabel!
    @IBOutlet private var audioStateWrapperView: UIView!
    @IBOutlet private var VideoStateLabel: UILabel!
    @IBOutlet private var stateSummaryView: UIView!
    @IBOutlet private var publishStateImageView: UIImageView!
    @IBOutlet private var subscribeStateImageView: UIImageView!
    @IBOutlet private var audioOnlyButton: UIButton!
    @IBOutlet private var statsButton: UIButton!
    @IBOutlet private var commonStatsTextView: UITextView!
    @IBOutlet private var videoStatsTextView: UITextView!
    @IBOutlet private var audioStatsTextView: UITextView!
    
    weak var delegate: ParticipantCollectionViewCellDelegate?
    
    private var imageDevice: IVSImageDevice? {
        return registeredStreams.lazy.compactMap { $0.device as? IVSImageDevice }.first
    }
    
    private var audioDevice: IVSAudioDevice? {
        return registeredStreams.lazy.compactMap { $0.device as? IVSAudioDevice }.first
    }
    
    private var isLocal: Bool = false {
        didSet {
            audioOnlyButton.isHidden = isLocal
        }
    }
    
    private var participantId: String? {
        didSet {
            participantIdLabel.text = isLocal ? "You (\(participantId ?? "Disconnected"))" : participantId
        }
    }
    
    private var isPublishing: Bool = false {
        didSet {
            publishStateImageView.image = UIImage(named: isPublishing ? "publish" : "publish_slash")
        }
    }
    
    private var isSubscribing: Bool = false {
        didSet {
            subscribeStateImageView.image = UIImage(named: isSubscribing ? "subscribe" : "subscribe_slash")
        }
    }
    
    private var volumeLevel: Int = 0 {
        didSet { updateAudioImageView() }
    }
    
    private var isAudioMuted: Bool = false {
        didSet { updateAudioImageView() }
    }
    
    private var isVideoMuted: Bool = false {
        didSet {
            VideoStateLabel.isHidden = !isVideoMuted
            previewView.isHidden = isVideoMuted
        }
    }
    
    private var isAudioOnly: Bool = false {
        didSet { audioOnlyButton.setTitle("Audio Only:\n\(isAudioOnly ? "YES" : "NO")", for: .normal) }
    }
    
    private var isStatsEnabled: Bool = false {
        didSet { statsButton.setTitle("Stats: \(isStatsEnabled ? "ON" : "OFF")", for: .normal) }
    }
    
    private var registeredStreams: Set<IVSStageStream> = []
    
    private let videoStatsBuilder: StatsBuilder = .init()
    private let audioStatsBuilder: StatsBuilder = .init()

    override func awakeFromNib() {
        super.awakeFromNib()
        
        participantIdWrapperView.layer.cornerRadius = 5
        audioStateWrapperView.layer.cornerRadius = 25
        stateSummaryView.layer.cornerRadius = 5
        audioOnlyButton.layer.cornerRadius = 5
        statsButton.layer.cornerRadius = 5
        contentView.layer.cornerRadius = 10
        contentView.layer.borderColor = UIColor.green.cgColor
        contentView.layer.borderWidth = 1
    }
    
    // MARK: - Public
    
    func set(participant: ParticipantData) {
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

        isLocal = participant.isLocal

        participantId = participant.participantId
        isPublishing = participant.publishState == .published
        isSubscribing = participant.subscribeState == .subscribed
        isAudioOnly = participant.wantsAudioOnly

        // Get current image stream and audio stream on cell
        // At the moment our UI only allows for a single stream of each type to exist per participant
        let existingAudioStream = registeredStreams.first { $0.device is IVSAudioDevice }
        let existingImageStream = registeredStreams.first { $0.device is IVSImageDevice }

        // Update registered streams, preparing for UI updates
        registeredStreams = Set(participant.streams)
        
        // Get image stream and audio stream from target participant
        let newAudioStream = participant.streams.first { $0.device is IVSAudioDevice }
        let newImageStream = participant.streams.first { $0.device is IVSImageDevice }

        if existingImageStream !== newImageStream {
            // The image stream has changed. Maybe from nil to real, real to nil, or real to real (but different).
            newImageStream?.delegate = self
            updatePreview()
        }
        // Regardless of any diff, the avatar placeholder should be hidden only if a current image stream exists and the muted state is false
        isVideoMuted = newImageStream?.isMuted != false

        if existingAudioStream !== newAudioStream {
            // The audio stream has changed. Maybe from nil to real, real to nil, or real to real (but different).
            // Unregister self for receivering old audio device callback
            (existingAudioStream?.device as? IVSAudioDevice)?.setStatsCallback(nil)
            newAudioStream?.delegate = self
            // Register self for receivering new audio device callback to update volume level
            audioDevice?.setStatsCallback( { [weak self] stats in
                dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
                self?.setAudioStat(peak: stats.peak, rms: stats.rms)
            })
            volumeLevel = 0 // until we start getting new samples
        }
        // Even if it's the same audio stream as last time, it is possible the muted flag has changed.
        isAudioMuted = newAudioStream?.isMuted ?? false
        
        isStatsEnabled = participant.isStatsEnabled
        videoStatsBuilder.isLocal = isLocal
        audioStatsBuilder.isLocal = isLocal
        commonStatsTextView.isHidden = !participant.isStatsEnabled
        videoStatsTextView.isHidden = !participant.isStatsEnabled
        audioStatsTextView.isHidden = !participant.isStatsEnabled
    }
    
    func toggleEditMode() {
        statsButton.isHidden.toggle()
        guard isLocal == false else { return }
        audioOnlyButton.isHidden.toggle()
    }
    
    // MARK: - Private
    
    private func updatePreview() {
        previewView.subviews.forEach { $0.removeFromSuperview() }
        // Check if there's an image device in registered streams
        if let imageDevice = self.imageDevice {
            // Try to create a preview from the image device and attach the preview to the cell
            if let preview = try? imageDevice.previewView(with: .fit) {
                preview.translatesAutoresizingMaskIntoConstraints = false
                previewView.addSubview(preview)
                NSLayoutConstraint.activate([
                    preview.topAnchor.constraint(equalTo: previewView.topAnchor, constant: 0),
                    preview.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 0),
                    preview.leadingAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 0),
                    preview.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 0),
                ])
            }
        } else {
            isVideoMuted = true
        }
    }
    
    private func updateAudioImageView() {
        if isAudioMuted {
            contentView.layer.borderWidth = 1
            audioStateWrapperView.isHidden = false
        } else {
            audioStateWrapperView.isHidden = true
            // Volume is 0-9 but we want a border width of 1-8.
            // So volume has a range of 9, border has a range of 7, and gets floored.
            contentView.layer.borderWidth = (CGFloat(volumeLevel) * 7.0 / 9.0) + 1
        }
    }
    
    private func setAudioStat(peak: Float, rms: Float) {
        switch peak {
        case -1000000 ... -50:
            volumeLevel = 0
        case -55 ... -45:
            volumeLevel = 1
        case -45 ... -36:
            volumeLevel = 2
        case -36 ... -28:
            volumeLevel = 3
        case -28 ... -21:
            volumeLevel = 4
        case -21 ... -15:
            volumeLevel = 5
        case -15 ... -10:
            volumeLevel = 6
        case -10 ... -6:
            volumeLevel = 7
        case -6 ... -3:
            volumeLevel = 8
        case -3 ... Float.greatestFiniteMagnitude:
            volumeLevel = 9
        default:
            volumeLevel = 0
        }
    }
    
    // MARK: - Actions
    
    @IBAction private func audioOnlyButtonTapped(_ sender: UIButton!) {
        guard let participantId = participantId else { return }
        delegate?.toggleAudioOnlySubscribe(forParticipant: participantId)
    }

    @IBAction func statsButtonTapped(_ sender: UIButton) {
        guard let participantId = participantId else { return }
        delegate?.toggleEnableStats(forParticipant: participantId)
    }
}

extension ParticipantCollectionViewCell: IVSStageStreamDelegate {
    
    func streamDidChangeIsMuted(_ stream: IVSStageStream) {
        if stream.device is IVSImageDevice {
            isVideoMuted = stream.isMuted
        } else if stream.device is IVSAudioDevice {
            isAudioMuted = stream.isMuted
        }
    }
    
    func stream(_ stream: IVSStageStream, didGenerateRTCStats stats: [String : [String : String]]) {
        // Can receive RTC stats after calling `requestRTCStats()`
        if stream.device is IVSImageDevice {
            guard videoStatsBuilder.isNew(stats) else {
                return
            }
            videoStatsBuilder.stats = stats
            videoStatsTextView.text = "VIDEO\n" + videoStatsBuilder.statsString
            videoStatsTextView.sizeToFit()
        } else if stream.device is IVSAudioDevice {
            guard audioStatsBuilder.isNew(stats) else {
                return
            }
            audioStatsBuilder.stats = stats
            commonStatsTextView.text = audioStatsBuilder.commonStatsString
            commonStatsTextView.sizeToFit()
            audioStatsTextView.text = "AUDIO\n" + audioStatsBuilder.statsString
            audioStatsTextView.sizeToFit()
        }
    }
    
}

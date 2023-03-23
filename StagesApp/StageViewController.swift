//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
import UIKit
import AmazonIVSBroadcast

class StageViewController: UIViewController {
    
    private let viewModel = StageViewModel()
    
    @IBOutlet private var collectionView: UICollectionView!
    
    @IBOutlet private var micButton: UIButton!
    @IBOutlet private var videoCamButton: UIButton!
    @IBOutlet private var broadcastButton: UIButton!
    @IBOutlet private var leaveButton: UIButton!
    
    @IBOutlet private var joinStageContainerView: UIView!
    @IBOutlet private var tokenTextField: UITextField!
    @IBOutlet private var joinButton: UIButton!
    @IBOutlet var versionLabel: UILabel!
    
    @IBOutlet var streamSetupContainerView: UIView!
    @IBOutlet var streamKeyTextField: UITextField!
    @IBOutlet var endpointTextField: UITextField!
    @IBOutlet var startStreamButton: UIButton!
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        versionLabel.text = "IVS SDK v" + IVSBroadcastSession.sdkVersion
        
        if let token = UserDefaults.standard.string(forKey: "joinToken")  {
            tokenTextField.text = token
        }
        
        if let endpoint = UserDefaults.standard.string(forKey: "endpointPath") {
            endpointTextField.text = endpoint
        }
        
        if let streamKey = UserDefaults.standard.string(forKey: "streamKey") {
            streamKeyTextField.text = streamKey
        }
        
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(UINib(nibName: "ParticipantCollectionViewCell", bundle: .main), forCellWithReuseIdentifier: "ParticipantCollectionViewCell")
        collectionView.isScrollEnabled = false
        
        viewModel.participantUpdates.add { [weak collectionView] (index, changeType, participant) in
            // UICollectionView automatically clears itself out when it gets detached from it's
            // superview it seems (which for us happens when the VC is dismissed).
            // So even though our update/insert/reload calls are in sync, the UICollectionView
            // thinks it has 0 items if this is invoked async after the VC is dismissed.
            guard collectionView?.superview != nil else { return }
            switch changeType {
            case .inserted:
                collectionView?.insertItems(at: [IndexPath(item: index, section: 0)])
            case .updated:
                // Instead of doing reloadItems, just grab the cell and update it ourselves. It saves a create/destroy of a cell
                // and more importantly fixes some UI glitches. We don't support scrolling at all so the index path per cell
                // never changes.
                guard let participant = participant else { return }
                if let cell = collectionView?.cellForItem(at: IndexPath(item: index, section: 0)) as? ParticipantCollectionViewCell {
                    cell.set(participant: participant)
                }
            case .deleted:
                collectionView?.deleteItems(at: [IndexPath(item: index, section: 0)])
            }
        }
        
        viewModel.errorAlerts.add { [weak self] error in
            guard let error = error else { return }
            let alert = UIAlertController(title: error.title,
                                          message: error.message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
        
        viewModel.observableStageConnectionState.addAndNotify { [weak joinStageContainerView] stageState in
            DispatchQueue.main.async { [weak joinStageContainerView] in
                joinStageContainerView?.isHidden = (stageState != .disconnected)
            }
        }
        
        viewModel.localUserAudioMuted.addAndNotify { [weak micButton] muted in
            DispatchQueue.main.async { [weak micButton] in
                micButton?.setTitle(muted ? "Mic: Off" : "Mic: On", for: .normal)
            }
        }
        
        viewModel.localUserVideoMuted.addAndNotify { [weak videoCamButton] muted in
            DispatchQueue.main.async { [weak videoCamButton] in
                videoCamButton?.setTitle(muted ? "Camera: Off" : "Camera: On", for: .normal)
            }
        }
        
        viewModel.isBroadcasting.addAndNotify { [weak broadcastButton] isBroadcasting in
            DispatchQueue.main.async { [weak broadcastButton] in
                broadcastButton?.setTitleColor(isBroadcasting ? .green : .white, for: .normal)
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.viewDidAppear()
        
        checkAVPermissions { [weak self] granted in
            guard granted else {
                self?.displayPermissionError()
                return
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.viewDidDisappear()
    }
    
    // MARK: - User Interaction
    
    @IBAction func joinTapped(_ sender: Any) {
        viewModel.joinStage(token: tokenTextField.text!)
    }
    
    @IBAction func muteTapped(_ sender: Any) {
        viewModel.toggleLocalAudioMute()
    }
    
    @IBAction func stopVideoTapped(_ sender: Any) {
        viewModel.toggleLocalVideoMute()
    }
    
    @IBAction func broadcastTapped(_ sender: Any) {
        if streamSetupContainerView.isHidden == false {
            streamSetupContainerView.isHidden = true
            return
        }
        if viewModel.isBroadcasting.value {
            // If we're broadcasting, tapping the broadcast buttons stops the broadcasting.
            viewModel.toggleBroadcasting()
        } else {
            // Otherwise toggle visibility
            streamSetupContainerView.isHidden = false
        }
    }
    
    @IBAction func startStreamTapped(_ sender: Any) {
        view.endEditing(false)
        streamSetupContainerView.isHidden = true
        if viewModel.setBroadcastAuth(endpoint: endpointTextField.text, streamKey: streamKeyTextField.text) {
            viewModel.toggleBroadcasting()
        }
    }
    
    @IBAction func leaveTapped(_ sender: Any) {
        viewModel.leaveStage()
    }
    
}

extension StageViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.participantCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ParticipantCollectionViewCell", for: indexPath) as? ParticipantCollectionViewCell {
            let participant = viewModel.participantsData[indexPath.item]
            cell.set(participant: participant)
            cell.delegate = self
            return cell
        } else {
            fatalError("Couldn't load custom cell type 'ParticipantCollectionViewCell'")
        }
    }
}

extension StageViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        view.endEditing(false)
        if let cell = collectionView.cellForItem(at: indexPath) as? ParticipantCollectionViewCell {
            cell.toggleEditMode()
        }
    }

}

extension StageViewController: ParticipantCollectionViewCellDelegate {
    
    func toggleAudioOnlySubscribe(forParticipant participantId: String) {
        viewModel.toggleAudioOnlySubscribe(forParticipant: participantId)
    }
    
}

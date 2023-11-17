//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import AmazonIVSBroadcast
import Foundation
import UIKit

struct AuthItem {
    let endpoint: String
    let streamKey: String
}

class StageViewModel: NSObject {
    
    enum ChangeType {
        case inserted, updated, deleted
    }
    
    // MARK: - Bindable properties
    
    let isBroadcasting: Observable<Bool> = .init(false)
    let localUserAudioMuted: Observable<Bool> = .init(false)
    let localUserVideoMuted: Observable<Bool> = .init(false)
    let observableStageConnectionState: Observable<IVSStageConnectionState> = .init(.disconnected)
    let participantUpdates: Observable<(index: Int, change: ChangeType, data: ParticipantData?)> = .init((0, .updated, nil))
    let errorAlerts: Observable<(title: String, message: String)?> = .init(nil)
    
    var participantsData: [ParticipantData] = [ParticipantData(isLocal: true, participantId: nil)] {
        didSet { updateBroadcastSlots() }
    }
    
    var participantCount: Int {
        return participantsData.count
    }
    
    // MARK: - Internal State
    
    private let broadcastConfig = IVSPresets.configurations().standardPortrait()
    private let camera: IVSCamera?
    private let microphone: IVSMicrophone?
    private var currentAuthItem: AuthItem?
    
    private var stage: IVSStage?
    private var localUserWantsPublish: Bool = true

    private var isVideoMuted = false {
        didSet {
            validateVideoMuteSetting()
            signalParticipantUpdate(index: 0, changeType: .updated)
        }
    }
    private var isAudioMuted = false {
        didSet {
            validateAudioMuteSetting()
            signalParticipantUpdate(index: 0, changeType: .updated)
        }
    }

    private var localStreams: [IVSLocalStageStream] {
        set {
            participantsData[0].streams = newValue
            updateBroadcastBindings()
            validateVideoMuteSetting()
            validateAudioMuteSetting()
        }
        get {
            return participantsData[0].streams as? [IVSLocalStageStream] ?? []
        }
    }

    private var broadcastSession: IVSBroadcastSession?
    
    // Store broadcast slot configurations for all participants,
    // configuring the layout on broadcast canvas
    private var broadcastSlots: [IVSMixerSlotConfiguration] = [] {
        didSet {
            guard let broadcastSession = broadcastSession else { return }
            let oldSlots = broadcastSession.mixer.slots()
            // We're going to remove old slots, then add new slots, and update existing slots.

            // Removing old slots
            oldSlots.forEach { oldSlot in
                if !broadcastSlots.contains(where: { $0.name == oldSlot.name }) {
                    broadcastSession.mixer.removeSlot(withName: oldSlot.name)
                }
            }

            // Adding new slots
            broadcastSlots.forEach { newSlot in
                if !oldSlots.contains(where: { $0.name == newSlot.name }) {
                    broadcastSession.mixer.addSlot(newSlot)
                }
            }

            // Update existing slots
            broadcastSlots.forEach { newSlot in
                if oldSlots.contains(where: { $0.name == newSlot.name }) {
                    broadcastSession.mixer.transitionSlot(withName: newSlot.name, toState: newSlot, duration: 0.3)
                }
            }
        }
    }
    
    // MARK: - Stages session management state

    private var stageConnectionState: IVSStageConnectionState = .disconnected {
        didSet {
            observableStageConnectionState.value = stageConnectionState
        }
    }
    
    // MARK: - Lifecycle
    
    override init() {
        
        // Setup default camera and microphone devices
        let devices = IVSDeviceDiscovery().listLocalDevices()
        camera = devices.compactMap({ $0 as? IVSCamera }).first
        microphone = devices.compactMap({ $0 as? IVSMicrophone }).first

        // Use `IVSStageAudioManager` to control the underlying AVAudioSession instance. The presets provided
        // by the IVS SDK make optimizing the audio configuration for different use-cases easy.
        IVSStageAudioManager.sharedInstance().setPreset(.videoChat)

        super.init()

        camera?.errorDelegate = self
        microphone?.errorDelegate = self
        setupLocalUser()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }
    
    private func setupLocalUser() {
        if let camera = camera {
            // Find front camera input source and set it as preferred camera input source
            if let frontSource = camera.listAvailableInputSources().first(where: { $0.position == .front }) {
                camera.setPreferredInputSource(frontSource) { [weak self] in
                    if let error = $0 {
                        self?.displayErrorAlert(error, logSource: "setupLocalUser")
                    }
                }
            }
            
            // Add stream with local image device to localStreams
            localStreams.append(IVSLocalStageStream(device: camera, config: IVSLocalStageStreamConfiguration()))
        }

        if let microphone = microphone {
            // Add stream with local audio device to localStreams
            localStreams.append(IVSLocalStageStream(device: microphone))
        }
        
        // Notify UI updates
        signalParticipantUpdate(index: 0, changeType: .inserted)
    }
    
    func viewDidAppear() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func viewDidDisappear() {
        UIApplication.shared.isIdleTimerDisabled = false
        destroyBroadcastSession()
        leaveStage()
    }
    
    @objc
    private func applicationDidEnterBackground() {
        print("app did enter background")
        let stageState = observableStageConnectionState.value
        let connectingOrConnected = (stageState == .connecting) || (stageState == .connected)

        if connectingOrConnected {
            // Stop publishing when entering background
            localUserWantsPublish = false
            
            // Switch other participants to audio only subscribe
            participantsData
                .compactMap { $0.participantId }
                .forEach {
                    mutatingParticipant($0) { data in
                        data.requiresAudioOnly = true
                    }
                }
            
            // Call `refreshStrategy` to trigger a refresh of all the `IVSStageStrategy` functions,
            // which after our changes above will change all subscriptions
            // to audio-only, and stop publishing.
            stage?.refreshStrategy()
        }
    }

    @objc
    private func applicationWillEnterForeground() {
        print("app did resume foreground")
        // Resume publishing when entering foreground
        localUserWantsPublish = true
        
        // Resume other participants from audio only subscribe
        if !participantsData.isEmpty {
            participantsData
                .compactMap { $0.participantId }
                .forEach {
                    mutatingParticipant($0) { data in
                        data.requiresAudioOnly = false
                    }
                }
            
            // Call `refreshStrategy` to trigger a refresh of all the `IVSStageStrategy` functions,
            // which after our changes above will change all subscriptions
            // to audio+video, and start publishing.
            stage?.refreshStrategy()
        }
    }
    
    // MARK: - Actions from view
    
    func joinStage(token: String) {
        UserDefaults.standard.set(token, forKey: "joinToken")
        
        do {
            self.stage = nil
            let stage = try IVSStage(token: token, strategy: self)
            stage.addRenderer(self)
            try stage.join()
            self.stage = stage
        } catch {
            displayErrorAlert(error, logSource: "JoinStageSession")
        }
    }
    
    func leaveStage() {
        stage?.leave()
    }
    
    func toggleLocalVideoMute() {
        isVideoMuted.toggle()
        signalParticipantUpdate(index: 0, changeType: .updated)
    }

    private func validateVideoMuteSetting() {
        // Find local image device and update the mute state
        localStreams
            .filter { $0.device is IVSImageDevice }
            .forEach {
                $0.setMuted(isVideoMuted)
                
                // Notify UI updates
                localUserVideoMuted.value = isVideoMuted
            }
    }
    
    func toggleLocalAudioMute() {
        isAudioMuted.toggle()
        signalParticipantUpdate(index: 0, changeType: .updated)
    }

    private func validateAudioMuteSetting() {
        // Find local audio device and update the mute state
        localStreams
            .filter { $0.device is IVSAudioDevice }
            .forEach {
                $0.setMuted(isAudioMuted)
                
                // Notify UI updates
                localUserAudioMuted.value = isAudioMuted
            }
    }
    
    func toggleAudioOnlySubscribe(forParticipant participantId: String) {
        mutatingParticipant(participantId) {
            $0.wantsAudioOnly.toggle()
        }
        
        // Call `refreshStrategy` to trigger a refresh of all the `IVSStageStrategy` functions,
        // which after the changes above will update the subscribe type of this participant
        stage?.refreshStrategy()
    }
    
    func toggleBroadcasting() {
        guard let authItem = currentAuthItem, let endpoint = URL(string: authItem.endpoint) else {
            errorAlerts.value = (
                "Invalid Endpoint or StreamKey",
                "Please double check that your endpoint is a valid URL and your streamkey is not empty"
            )
            return
        }
        
        // Create broadcast session if needed
        guard setupBroadcastSessionIfNeeded() else { return }
        
        if isBroadcasting.value {
            // Stop broadcasting if the broadcast session is running
            broadcastSession?.stop()
            isBroadcasting.value = false
            
        } else {
            // Start broadcasting
            do {
                try broadcastSession?.start(with: endpoint, streamKey: authItem.streamKey)
                isBroadcasting.value = true
            } catch {
                displayErrorAlert(error, logSource: "StartBroadcast")
                isBroadcasting.value = false
                broadcastSession = nil
            }
        }
    }
    
    func setBroadcastAuth(endpoint: String?, streamKey: String?) -> Bool {
        // Update and store broadcast settings, call this method before start broadcasting
        guard let endpoint = endpoint, let streamKey = streamKey, URL(string: endpoint) != nil else {
            errorAlerts.value = (
                "Invalid Endpoint or StreamKey",
                "Please double check that your endpoint is a valid URL and your streamkey is not empty"
            )
            return false
        }
        UserDefaults.standard.set(endpoint, forKey: "endpointPath")
        UserDefaults.standard.set(streamKey, forKey: "streamKey")
        let authItem = AuthItem(endpoint: endpoint, streamKey: streamKey)
        currentAuthItem = authItem
        return true
    }
    
    private func setupBroadcastSessionIfNeeded() -> Bool {
        guard broadcastSession == nil else {
            print("Session not created since it already exists")
            return true
        }
        do {
            self.broadcastSession = try IVSBroadcastSession(configuration: broadcastConfig,
                                                            descriptors: nil,
                                                            delegate: self)
            updateBroadcastSlots()
            return true
        } catch {
            displayErrorAlert(error, logSource: "SetupBroadcastSession")
            return false
        }
    }
    
    private func updateBroadcastSlots() {
        do {
            // Decide which participants to broadcast
            let participantsToBroadcast = participantsData
            
            // Use StageLayoutCalculator to calculate each participant's layout on the broadcast canvas,
            // and create slot configuration with the layout settings for each participant
            // Update broadcastSlots property with all participants' slot configurations
            broadcastSlots = try StageLayoutCalculator().calculateFrames(participantCount: participantsToBroadcast.count,
                                                                         width: broadcastConfig.video.size.width,
                                                                         height: broadcastConfig.video.size.height,
                                                                         padding: 10)
            .enumerated()
            .map { (index, frame) in
                let slot = IVSMixerSlotConfiguration()
                try slot.setName(participantsToBroadcast[index].broadcastSlotName)
                slot.position = frame.origin
                slot.size = frame.size
                slot.zIndex = Int32(index)
                return slot
            }
            
            // After updating broadcast slots, bind each participant's streams
            // to the participant's slot configuration
            updateBroadcastBindings()
            
        } catch {
            errorAlerts.value = (
                "Broadcast Slots",
                "There was an error updating the slots for the Broadcast. The Broadcast might be out of sync with the Stage"
            )
        }
    }
    
    private func updateBroadcastBindings() {
        guard let broadcastSession = broadcastSession else { return }
        
        broadcastSession.awaitDeviceChanges { [weak self] in
            // Find devices attached to current broadcast session
            var attachedDevices = broadcastSession.listAttachedDevices()
            
            // Bind each participant's stream devices to the participant's slot configuration
            self?.participantsData.forEach { participant in
                participant.streams.forEach { stream in
                    let slotName = participant.broadcastSlotName
                    if attachedDevices.contains(where: { $0 === stream.device }) {
                        // If this participant's stream device is already attached to current broadcast session,
                        // bind the stream device to this participant's slot configuration if the current binding is incorrect
                        if broadcastSession.mixer.binding(for: stream.device) != slotName {
                            broadcastSession.mixer.bindDevice(stream.device, toSlotWithName: slotName)
                        }
                    } else {
                        // If this participant's stream device is not attached to current broadcast session,
                        // attach the device to current broadcast session with the participant's slot name
                        broadcastSession.attach(stream.device, toSlotWithName: slotName)
                    }
                    
                    attachedDevices.removeAll(where: { $0 === stream.device })
                }
            }
            
            // Anything still in the attached devices list at the end shouldn't be attached anymore
            attachedDevices.forEach {
                broadcastSession.detach($0)
            }
        }
    }
    
    private func destroyBroadcastSession() {
        if isBroadcasting.value {
            print("Destroying broadcast session")
            broadcastSession?.stop()
            broadcastSession = nil
            isBroadcasting.value = false
        }
    }
    
    // MARK: - Private
    
    private func dataForParticipant(_ participantId: String) -> ParticipantData? {
        let participant = participantsData.first { $0.participantId == participantId }
        return participant
    }

    private func mutatingParticipant(_ participantId: String?, modifier: (inout ParticipantData) -> Void) {
        guard let index = participantsData.firstIndex(where: { $0.participantId == participantId }) else { return }

        var participant = participantsData[index]
        modifier(&participant)
        participantsData[index] = participant
        
        // Notify UI updates
        signalParticipantUpdate(index: index, changeType: .updated)
    }
    
    private func signalParticipantUpdate(index: Int, changeType: ChangeType) {
        participantUpdates.value = (index, changeType, (changeType == .deleted) ? nil : participantsData[index])
    }
    
    private func displayErrorAlert(_ error: Error, logSource: String? = nil) {
        var sourceDescription = ""
        if let logSource = logSource {
            sourceDescription = "Source: \(logSource)\n"
        }
        errorAlerts.value = (
            "Error (Code: \((error as NSError).code))",
            "\(sourceDescription)Error: \(error.localizedDescription)"
        )
    }
    
}

// These callbacks are triggered by `IVSStage.refreshStrategy()`
// Call `IVSStage.refreshStrategy()` whenever we want to update the answers to these questions
extension StageViewModel: IVSStageStrategy {

    func stage(_ stage: IVSStage, shouldSubscribeToParticipant participant: IVSParticipantInfo) -> IVSStageSubscribeType {
        guard let data = dataForParticipant(participant.participantId) else { return .none }
        let subType: IVSStageSubscribeType = data.isAudioOnly ? .audioOnly : .audioVideo

        return subType
    }

    func stage(_ stage: IVSStage, shouldPublishParticipant participant: IVSParticipantInfo) -> Bool {
        return localUserWantsPublish
    }

    func stage(_ stage: IVSStage, streamsToPublishForParticipant participant: IVSParticipantInfo) -> [IVSLocalStageStream] {
        // We should only try to publish streams for the local participant
        guard participantsData[0].participantId == participant.participantId else {
            return []
        }
        return localStreams
    }

}

extension StageViewModel: IVSStageRenderer {

    func stage(_ stage: IVSStage, participantDidJoin participant: IVSParticipantInfo) {
        print("[IVSStageRenderer] participantDidJoin - \(participant.participantId)")
        if participant.isLocal {
            // Update local participant ID
            participantsData[0].participantId = participant.participantId
            // Notify UI updates
            signalParticipantUpdate(index: 0, changeType: .updated)
        } else {
            // Create and store ParticipantData for newly joined participants
            participantsData.append(ParticipantData(isLocal: false, participantId: participant.participantId))
            // Notify UI updates
            signalParticipantUpdate(index: (participantsData.count - 1), changeType: .inserted)
        }
    }

    func stage(_ stage: IVSStage, participantDidLeave participant: IVSParticipantInfo) {
        print("[IVSStageRenderer] participantDidLeave - \(participant.participantId)")
        if participant.isLocal {
            // Reset local participant ID
            participantsData[0].participantId = nil
            // Notify UI updates
            signalParticipantUpdate(index: 0, changeType: .updated)
        } else {
            if let index = participantsData.firstIndex(where: { $0.participantId == participant.participantId }) {
                participantsData.remove(at: index)
                // Notify UI updates
                signalParticipantUpdate(index: index, changeType: .deleted)
            }
        }
    }

    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didChange publishState: IVSParticipantPublishState) {
        print("[IVSStageRenderer] participant \(participant.participantId) didChangePublishState to \(publishState.text)")
        mutatingParticipant(participant.participantId) { data in
            data.publishState = publishState
        }
    }
    
    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didChange subscribeState: IVSParticipantSubscribeState) {
        print("[IVSStageRenderer] participant \(participant.participantId) didChangeSubscribeState to \(subscribeState.text)")
        mutatingParticipant(participant.participantId) { data in
            data.subscribeState = subscribeState
        }
    }

    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didAdd streams: [IVSStageStream]) {
        print("[IVSStageRenderer] participant (\(participant.participantId)) didAdd \(streams.count) streams")
        if participant.isLocal { return }

        mutatingParticipant(participant.participantId) { data in
            data.streams.append(contentsOf: streams)
        }
    }

    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didRemove streams: [IVSStageStream]) {
        print("[IVSStageRenderer] participant (\(participant.participantId)) didRemove \(streams.count) streams")
        if participant.isLocal { return }

        mutatingParticipant(participant.participantId) { data in
            // Use unique device locator to remove desinated streams for participant
            let oldUrns = streams.map { $0.device.descriptor().urn }
            data.streams.removeAll(where: { stream in
                return oldUrns.contains(stream.device.descriptor().urn)
            })
        }
    }

    func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didChangeMutedStreams streams: [IVSStageStream]) {
        print("[IVSStageRenderer] participant (\(participant.participantId)) didChangeMutedStreams")
        if participant.isLocal { return }
        if let index = participantsData.firstIndex(where: { $0.participantId == participant.participantId }) {
            // The `streams` are the same objects managed by the SDK, so we don't need to update anything. The refs are updated.
            // Notify UI updates
            signalParticipantUpdate(index: index, changeType: .updated)
        }
    }

    func stage(_ stage: IVSStage, didChange connectionState: IVSStageConnectionState, withError error: Error?) {
        print("[IVSStageRenderer] didChangeConnectionStateWithError to \(connectionState.text)")
        stageConnectionState = connectionState;
        if let error = error {
            displayErrorAlert(error)
        }
    }

}

extension StageViewModel: IVSBroadcastSession.Delegate {

    func broadcastSession(_ session: IVSBroadcastSession, didChange state: IVSBroadcastSession.State) {
        print("[IVSBroadcastSession] state changed to \(state.text)")
        switch state {
        case .invalid, .disconnected, .error:
            isBroadcasting.value = false
            broadcastSession = nil
        case .connecting, .connected:
            isBroadcasting.value = true
        default:
            return
        }
    }

    func broadcastSession(_ session: IVSBroadcastSession, didEmitError error: Error) {
        print("[IVSBroadcastSession] did emit error \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.displayErrorAlert(error, logSource: "IVSBroadcastSessionDelegate")
        }
    }

}

extension StageViewModel: IVSErrorDelegate {

    func source(_ source: IVSErrorSource, didEmitError error: Error) {
        print("[IVSErrorDelegate] did emit error \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.displayErrorAlert(error, logSource: "\(source)")
        }
    }

}

// MARK: - State extensions

extension IVSBroadcastSession.State {
    var text: String {
        switch self {
        case .invalid: return "Invalid"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        @unknown default: return "Unknown"
        }
    }
}

extension IVSStageConnectionState {
    var text: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        @unknown default: return "Unknown"
        }
    }
}

extension IVSParticipantPublishState {
    var text: String {
        switch self {
        case .notPublished: return "Not Published"
        case .attemptingPublish: return "Attempting to Publish"
        case .published: return "Published"
        @unknown default: return "Unknown"
        }
    }
}

extension IVSParticipantSubscribeState {
    var text: String {
        switch self {
        case .notSubscribed: return "Not Subscribed"
        case .attemptingSubscribe: return "Attempting to Subscribe"
        case .subscribed: return "Subscribed"
        @unknown default: return "Unknown"
        }
    }
}

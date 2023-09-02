//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import AmazonIVSBroadcast
import Foundation

struct ParticipantData {
    let isLocal: Bool
    var participantId: String?
    var publishState: IVSParticipantPublishState = .notPublished
    var subscribeState: IVSParticipantSubscribeState = .notSubscribed
    var streams: [IVSStageStream] = []

    // The host-app has explicitly requested audio only
    var wantsAudioOnly = false
    // The host-app is in the background and requires audio only
    var requiresAudioOnly = false
    // The actual audio only state to be used for subscriptions.
    var isAudioOnly: Bool {
        return wantsAudioOnly || requiresAudioOnly
    }

    var broadcastSlotName: String {
        if isLocal {
            return "localUser"
        } else {
            guard let participantId = participantId else {
                fatalError("non-local participants must have a participantId")
            }
            return "participant-\(participantId)"
        }
    }

    var isStatsEnabled = false

    init(isLocal: Bool, participantId: String?) {
        self.isLocal = isLocal
        self.participantId = participantId
    }
}

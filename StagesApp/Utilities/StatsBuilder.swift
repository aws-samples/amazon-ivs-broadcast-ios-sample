//
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import Foundation

class StatsBuilder {
    private var lastStats: [String : [String : String]]?
    var stats: [String : [String : String]]? {
        willSet {
            lastStats = stats
        }
    }
    var isLocal = false
    
    var commonStatsString: String {
        guard let stats = stats else {
            return ""
        }
        var result = ""
                
        for stat in stats.sorted(by: { $0.key < $1.key }) {
            let rtcStats = RTCStats(stat.value)
            guard let type = rtcStats.type else {
                continue
            }
            switch type {
            case RTCIceCandidatePairStats.kType:
                let candidatePair = RTCIceCandidatePairStats(stat.value)
                if let bwe = isLocal ? candidatePair.availableOutgoingBitrate : candidatePair.availableIncomingBitrate {
                    result.append("BWE: \(bwe.kbps()) kbps\n")
                }

                if let lastStats = lastStats, let lastStat = lastStats[stat.key] {
                    let lastCandidatePair = RTCIceCandidatePairStats(lastStat)
                    if let bitrate = calculateBitrate(
                        bytes: isLocal ? candidatePair.bytesSent : candidatePair.bytesReceived,
                        timestamp: candidatePair.timestampUs,
                        lastBytes: isLocal ? lastCandidatePair.bytesSent : lastCandidatePair.bytesReceived,
                        lastTimestamp: lastCandidatePair.timestampUs) {
                        result.append("Bitrate: \(bitrate.kbps()) kbps\n")
                    }
                }
            default:
                break
            }
        }
        if result.last == "\n" {
            result.removeLast()
        }
        return result
    }
    
    var statsString: String {
        guard let stats = stats else {
            return ""
        }
        var result = ""
        
        for stat in stats.sorted(by: { $0.key < $1.key }) {
            let rtcStats = RTCStats(stat.value)
            guard let type = rtcStats.type else {
                continue
            }
            switch type {
            case RTCAudioSourceStats.kType:
                guard isLocal else { break }
                let mediaSource = RTCMediaSourceStats(stat.value)
                switch mediaSource.kind {
                case "audio":
                    let audioSource = RTCAudioSourceStats(stat.value)
                    if let audioLevel = audioSource.audioLevel {
                        result.append("Audio Level: \(audioLevel)\n")
                    }
                case "video":
                    let _ = RTCVideoSourceStats(stat.value)
                    break
                default:
                    break
                }
            case RTCOutboundRTPStreamStats.kType:
                guard isLocal else { break }
                let outboundRtp = RTCOutboundRTPStreamStats(stat.value)
                var tab = ""
                if let rid = outboundRtp.rid {
                    result.append("\(rid)\n")
                    tab = "  "
                }
                if let codec = findCodec(codecId: outboundRtp.codecId, stats: stats) {
                    if let mimeType = codec.mimeType {
                        result.append("\(tab)Codec: \(mimeType)\n")
                    }
                    if let channels = codec.channels {
                        result.append("\(tab)Channels: \(channels)\n")
                    }
                }
                if let size = makeVideoSize(width: outboundRtp.frameWidth, height: outboundRtp.frameHeight) {
                    result.append("\(tab)Size: \(size)\n")
                }
                if let fps = outboundRtp.framesPerSecond {
                    result.append("\(tab)Framerate: \(fps)\n")
                }
                if let lastStats = lastStats, let lastStat = lastStats[stat.key] {
                    let lastOutboundRtp = RTCOutboundRTPStreamStats(lastStat)
                    if let bitrate = calculateBitrate(bytes: outboundRtp.bytesSent, timestamp: outboundRtp.timestampUs, lastBytes: lastOutboundRtp.bytesSent, lastTimestamp: lastOutboundRtp.timestampUs) {
                        result.append("\(tab)Bitrate: \(bitrate.kbps()) kbps\n")
                    }
                }
                if let remoteInboundRtp = findRemoteInboundRtp(remoteId: outboundRtp.remoteId, stats: stats) {
                    if let jitter = remoteInboundRtp.jitter {
                        result.append("\(tab)Jitter: \(jitter.msec()) ms\n")
                    }
                    if let rtt = remoteInboundRtp.roundTripTime {
                        result.append("\(tab)Rtt: \(rtt.msec()) ms\n")
                    }
                    if let rate = calculatePacketLoss(packetsLost: remoteInboundRtp.packetsLost, packetsSent: outboundRtp.packetsSent) {
                        result.append("\(tab)Packet Loss: \(rate.percent())\n")
                    }
                }
            case RTCInboundRTPStreamStats.kType:
                guard !isLocal else { break }
                let inboundRtp = RTCInboundRTPStreamStats(stat.value)
                if let codec = findCodec(codecId: inboundRtp.codecId, stats: stats) {
                    if let mimeType = codec.mimeType {
                        result.append("Codec: \(mimeType)\n")
                    }
                    if let channels = codec.channels {
                        result.append("Channels: \(channels)\n")
                    }
                }
                if let size = makeVideoSize(width: inboundRtp.frameWidth, height: inboundRtp.frameHeight) {
                    result.append("Size: \(size)\n")
                }

                if let fps = inboundRtp.framesPerSecond
                {
                    result.append("Framerate \(fps)\n")
                }
                if let audioLevel = inboundRtp.audioLevel {
                    result.append("Audio Level: \(audioLevel)\n")
                }
                if let lastStats = lastStats, let lastStat = lastStats[stat.key] {
                    let lastInboundRtp = RTCInboundRTPStreamStats(lastStat)
                    if let bitrate = calculateBitrate(bytes: inboundRtp.bytesReceived, timestamp: inboundRtp.timestampUs, lastBytes: lastInboundRtp.bytesReceived, lastTimestamp: lastInboundRtp.timestampUs) {
                        result.append("Bitrate: \(bitrate.kbps()) kbps\n")
                    }
                    
                }
                if let jitter = inboundRtp.jitter {
                    result.append("Jitter: \(jitter.msec()) ms\n")
                }
                if let remoteOutboundRtp = findRemoteOutboundRtp(remoteId: inboundRtp.remoteId, stats: stats) {
                    if let rtt = remoteOutboundRtp.roundTripTime {
                        result.append("Rtt: \(rtt.msec()) ms\n")
                    }
                    if let rate = calculatePacketLoss(packetsLost: inboundRtp.packetsLost, packetsSent: remoteOutboundRtp.packetsSent) {
                        result.append("Packet Loss: \(rate.percent())\n")
                    }
                }
                // video doesn't have remote-outbound-rtp
                else if let packetsLost = inboundRtp.packetsLost,
                        let packetsReceived = inboundRtp.packetsReceived,
                        let rate = calculatePacketLoss(packetsLost: packetsLost, packetsSent: UInt32(packetsLost) + packetsReceived) {
                    result.append("Packet Loss: \(rate.percent())\n")
                }
            default:
                break
            }
        }
        if result.last == "\n" {
            result.removeLast()
        }
        return result
    }
    
    func isNew(_ stats: [String: [String: String]]) -> Bool {
        if let stat = stats.first?.value, let lastStat = lastStats?.first?.value {
            return RTCStats(stat).timestampUs != RTCStats(lastStat).timestampUs
        }
        return true
    }
    
    private func makeVideoSize(width: UInt32?, height: UInt32?) -> String? {
        guard let width = width,
              let height = height else {
            return nil
        }
        return "\(width)x\(height)"
    }

    
    private func calculateBitrate(bytes: UInt64?, timestamp: Int64?, lastBytes: UInt64?, lastTimestamp: Int64?) -> Double? {
        guard let bytes = bytes,
              let timestamp = timestamp,
              let lastBytes = lastBytes,
              let lastTimestamp = lastTimestamp else {
            return nil
        }
        let diff = bytes - lastBytes
        let interval = timestamp - lastTimestamp
        guard diff >= 0 && interval > 0 else {
            return nil
        }
        return Double(diff) * 8 / (Double(interval) / 1_000_000)
    }
    
    private func findCodec(codecId: String?, stats: [String: [String:String]]) -> RTCCodecStats? {
        guard let codecId = codecId, let stat = stats[codecId] else {
            return nil
        }
        return RTCCodecStats(stat)
    }
    
    private func findRemoteInboundRtp(remoteId: String?, stats: [String: [String:String]]) -> RTCRemoteInboundRtpStreamStats? {
        guard let remoteId = remoteId, let stat = stats[remoteId] else {
            return nil
        }
        return RTCRemoteInboundRtpStreamStats(stat)
    }
    
    private func findRemoteOutboundRtp(remoteId: String?, stats: [String: [String:String]]) -> RTCRemoteOutboundRtpStreamStats? {
        guard let remoteId = remoteId, let stat = stats[remoteId] else {
            return nil
        }
        return RTCRemoteOutboundRtpStreamStats(stat)
    }
    
    private func calculatePacketLoss(packetsLost: Int32?, packetsSent: UInt32?) -> Double? {
        guard let packetsLost = packetsLost,
              let packetsSent = packetsSent,
              packetsSent > 0 else {
            return nil
        }
        return Double(packetsLost) / Double(packetsSent)
    }
}

private extension Dictionary where Key == String, Value == String {
    func boolValue(_ key: Key) -> Bool? {
        guard let value = self[key] else {
            return nil
        }
        return (value as NSString).boolValue
    }
    
    func int32Value(_ key: Key) -> Int32? {
        guard let value = self[key] else {
            return nil
        }
        return Int32(value)
    }
    
    func uint32Value(_ key: Key) -> UInt32? {
        guard let value = self[key] else {
            return nil
        }
        return UInt32(value)
    }

    func int64Value(_ key: Key) -> Int64? {
        guard let value = self[key] else {
            return nil
        }
        return Int64(value)
    }

    func uint64Value(_ key: Key) -> UInt64? {
        guard let value = self[key] else {
            return nil
        }
        return UInt64(value)
    }
    
    func doubleValue(_ key: Key) -> Double? {
        guard let value = self[key] else {
            return nil
        }
        return Double(value)
    }
    
    func stringValue(_ key: Key) -> String? {
        guard let value = self[key] else {
            return nil
        }
        return value
    }
}

private class RTCStats {
    private let stats: [String: String]
    
    init(_ stats: [String: String]) {
        self.stats = stats
    }
    
    var id: String? { stats.stringValue("id") }
    // Time relative to the UNIX epoch (Jan 1, 1970, UTC), in microseconds.
    var timestampUs: Int64? { stats.int64Value("timestamp") }
    var type: String? { stats.stringValue("type") }
}

private class RTCCertificateStats: RTCStats {
    class var kType: String { "certificate" }
    private let stats: [String: String]
    
    var fingerprint: String? { stats.stringValue("fingerprint") }
    var fingerprintAlgorithm: String? { stats.stringValue("fingerprintAlgorithm") }
    var base64Certificate: String? { stats.stringValue("base64Certificate") }
    var issuerCertificateId: String? { stats.stringValue("issuerCertificateId") }
    
    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCCodecStats: RTCStats {
    private let stats: [String: String]
    
    var transportId: String? { stats.stringValue("transportId") }
    var payloadType: UInt32? { stats.uint32Value("payloadType") }
    var mimeType: String? { stats.stringValue("mimeType") }
    var clockRate: UInt32? { stats.uint32Value("clockRate") }
    var channels: UInt32? { stats.uint32Value("channels") }
    var sdpFmtpLine: String? { stats.stringValue("sdpFmtpLine") }

    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCIceCandidatePairStats: RTCStats {
    class var kType: String { "candidate-pair" }
    private let stats: [String: String]
    
    var transportId: String? { stats.stringValue("transportId") }
    var localCandidateId: String? { stats.stringValue("localCandidateId") }
    var remoteCandidateId: String? { stats.stringValue("remoteCandidateId") }
    var state: String? { stats.stringValue("state") }
    var priority: UInt64? { stats.uint64Value("priority") }
    var nominated: Bool? { stats.boolValue("nominated") }
    var writable: Bool? { stats.boolValue("writable") }
    var packetsSent: UInt64? { stats.uint64Value("packetsSent") }
    var packetsReceived: UInt64? { stats.uint64Value("packetsReceived") }
    var bytesSent: UInt64? { stats.uint64Value("bytesSent") }
    var bytesReceived: UInt64? { stats.uint64Value("bytesReceived") }
    var totalRoundTripTime: Double? { stats.doubleValue("totalRoundTripTime") }
    var currentRoundTripTime: Double? { stats.doubleValue("currentRoundTripTime") }
    var availableOutgoingBitrate: Double? { stats.doubleValue("availableOutgoingBitrate") }
    var availableIncomingBitrate: Double? { stats.doubleValue("availableIncomingBitrate") }
    var requestsReceived: UInt64? { stats.uint64Value("requestsReceived") }
    var requestsSent: UInt64? { stats.uint64Value("requestsSent") }
    var responsesReceived: UInt64? { stats.uint64Value("responsesReceived") }
    var responsesSent: UInt64? { stats.uint64Value("responsesSent") }
    var consentRequestsSent: UInt64? { stats.uint64Value("consentRequestsSent") }
    var packetsDiscardedOnSend: UInt64? { stats.uint64Value("packetsDiscardedOnSend") }
    var bytesDiscardedOnSend: UInt64? { stats.uint64Value("bytesDiscardedOnSend") }

    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCIceCandidateStats: RTCStats {
    class var kType: String { "abstract-ice-candidate" }
    private let stats: [String: String]
    
    var transportId: String? { stats.stringValue("transportId") }
    var networkType: String? { stats.stringValue("networkType") }
    var ip: String? { stats.stringValue("ip") }
    var address: String? { stats.stringValue("address") }
    var port: Int32? { stats.int32Value("port") }
    var `protocol`: String? { stats.stringValue("protocol") }
    var relayProtocol: String? { stats.stringValue("relayProtocol") }
    var candidateType: String? { stats.stringValue("candidateType") }
    var priority: Int32? { stats.int32Value("priority") }
    var url: String? { stats.stringValue("url") }
    var vpn: Bool? { stats.boolValue("vpn") }
    var networkAdapterType: String? { stats.stringValue("networkAdapterType") }
    
    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCLocalIceCandidateStats: RTCIceCandidateStats {
    override class var kType: String { "local-candidate" }
    private let stats: [String: String]
    
    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCRemoteIceCandidateStats: RTCIceCandidateStats {
    override class var kType: String { "remote-candidate" }
    private let stats: [String: String]
    
    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCRTPStreamStats: RTCStats {
    class var kType: String { "rtp" }
    private let stats: [String: String]
    
    var ssrc: UInt32? { stats.uint32Value("ssrc") }
    var kind: String? { stats.stringValue("kind") }
    var transportId: String? { stats.stringValue("transportId") }
    var codecId: String? { stats.stringValue("codecId") }
    
    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCReceivedRtpStreamStats: RTCRTPStreamStats {
    override class var kType: String { "received-rtp" }
    private let stats: [String: String]
    
    var jitter: Double? { stats.doubleValue("jitter") }
    var packetsLost: Int32? { stats.int32Value("packetsLost") }
    var packetsDiscarded: UInt64? { stats.uint64Value("packetsDiscarded") }
    
    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCSentRtpStreamStats: RTCRTPStreamStats {
    override class var kType: String { "sent-rtp" }
    private let stats: [String: String]
    
    var packetsSent: UInt32? { stats.uint32Value("packetsSent") }
    var bytesSent: UInt64? { stats.uint64Value("bytesSent") }
    
    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCInboundRTPStreamStats: RTCReceivedRtpStreamStats {
    override class var kType: String { "inbound-rtp" }
    private let stats: [String: String]
    
    var trackIdentifier: String? { stats.stringValue("trackIdentifier") }
    var mid: String? { stats.stringValue("mid") }
    var remoteId: String? { stats.stringValue("remoteId") }
    var packetsReceived: UInt32? { stats.uint32Value("packetsReceived") }
    var fecPacketsReceived: UInt64? { stats.uint64Value("fecPacketsReceived") }
    var fecPacketsDiscarded: UInt64? { stats.uint64Value("fecPacketsDiscarded") }
    var bytesReceived: UInt64? { stats.uint64Value("bytesReceived") }
    var headerBytesReceived: UInt64? { stats.uint64Value("headerBytesReceived") }
    var lastPacketReceivedTimestamp: Double? { stats.doubleValue("lastPacketReceivedTimestamp") }
    var jitterBufferDelay: Double? { stats.doubleValue("jitterBufferDelay") }
    var jitterBufferTargetDelay: Double? { stats.doubleValue("jitterBufferTargetDelay") }
    var jitterBufferMinimumDelay: Double? { stats.doubleValue("jitterBufferMinimumDelay") }
    var jitterBufferEmittedCount: UInt64? { stats.uint64Value("jitterBufferEmittedCount") }
    var totalSamplesReceived: UInt64? { stats.uint64Value("totalSamplesReceived") }
    var concealedSamples: UInt64? { stats.uint64Value("concealedSamples") }
    var silentConcealedSamples: UInt64? { stats.uint64Value("silentConcealedSamples") }
    var concealmentEvents: UInt64? { stats.uint64Value("concealmentEvents") }
    var insertedSamplesForDeceleration: UInt64? { stats.uint64Value("insertedSamplesForDeceleration") }
    var removedSamplesForAcceleration: UInt64? { stats.uint64Value("removedSamplesForAcceleration") }
    var audioLevel: Double? { stats.doubleValue("audioLevel") }
    var totalAudioEnergy: Double? { stats.doubleValue("totalAudioEnergy") }
    var totalSamplesDuration: Double? { stats.doubleValue("totalSamplesDuration") }
    // Stats below are only implemented or defined for video.
    var framesReceived: Int32? { stats.int32Value("framesReceived") }
    var frameWidth: UInt32? { stats.uint32Value("frameWidth") }
    var frameHeight: UInt32? { stats.uint32Value("frameHeight") }
    var framesPerSecond: Double? { stats.doubleValue("framesPerSecond") }
    var framesDecoded: UInt32? { stats.uint32Value("framesDecoded") }
    var keyFramesDecoded: UInt32? { stats.uint32Value("keyFramesDecoded") }
    var framesDropped: UInt32? { stats.uint32Value("framesDropped") }
    var totalDecodeTime: Double? { stats.doubleValue("totalDecodeTime") }
    var totalProcessingDelay: Double? { stats.doubleValue("totalProcessingDelay") }
    var totalAssemblyTime: Double? { stats.doubleValue("totalAssemblyTime") }
    var framesAssembledFromMultiplePackets: UInt32? { stats.uint32Value("framesAssembledFromMultiplePackets") }
    var totalInterFrameDelay: Double? { stats.doubleValue("totalInterFrameDelay") }
    var totalSquaredInterFrameDelay: Double? { stats.doubleValue("totalSquaredInterFrameDelay") }
    // https://w3c.github.io/webrtc-provisional-stats/#dom-rtcinboundrtpstreamstats-contenttype
    var contentType: String? { stats.stringValue("contentType") }
    var estimatedPlayoutTimestamp: Double? { stats.doubleValue("estimatedPlayoutTimestamp") }
    var decoderImplementation: String? { stats.stringValue("decoderImplementation") }
    var firCount: UInt32? { stats.uint32Value("firCount") }
    var pliCount: UInt32? { stats.uint32Value("pliCount") }
    var nackCount: UInt32? { stats.uint32Value("nackCount") }
    var qpSum: UInt64? { stats.uint64Value("qpSum") }
    var minPlayoutDelay: Double? { stats.doubleValue("minPlayoutDelay") }

    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCOutboundRTPStreamStats: RTCRTPStreamStats {
    override class var kType: String { "outbound-rtp" }
    private let stats: [String: String]
    
    var mediaSourceId: String? { stats.stringValue("mediaSourceId") }
    var remoteId: String? { stats.stringValue("remoteId") }
    var mid: String? { stats.stringValue("mid") }
    var rid: String? { stats.stringValue("rid") }
    var packetsSent: UInt32? { stats.uint32Value("packetsSent") }
    var retransmittedPacketsSent: UInt64? { stats.uint64Value("retransmittedPacketsSent") }
    var bytesSent: UInt64? { stats.uint64Value("bytesSent") }
    var headerBytesSent: UInt64? { stats.uint64Value("headerBytesSent") }
    var retransmittedBytesSent: UInt64? { stats.uint64Value("retransmittedBytesSent") }
    var targetBitrate: Double? { stats.doubleValue("targetBitrate") }
    var framesEncoded: UInt32? { stats.uint32Value("framesEncoded") }
    var keyFramesEncoded: UInt32? { stats.uint32Value("keyFramesEncoded") }
    var totalEncodeTime: Double? { stats.doubleValue("totalEncodeTime") }
    var totalEncodedBytesTarget: UInt64? { stats.uint64Value("totalEncodedBytesTarget") }
    var frameWidth: UInt32? { stats.uint32Value("frameWidth") }
    var frameHeight: UInt32? { stats.uint32Value("frameHeight") }
    var framesPerSecond: Double? { stats.doubleValue("framesPerSecond") }
    var framesSent: UInt32? { stats.uint32Value("framesSent") }
    var hugeFramesSent: UInt32? { stats.uint32Value("hugeFramesSent") }
    var totalPacketSendDelay: Double? { stats.doubleValue("totalPacketSendDelay") }
    var qualityLimitationReason: String? { stats.stringValue("qualityLimitationReason") }
    var qualityLimitationDurations: String? { stats.stringValue("qualityLimitationDurations") }
    // https://w3c.github.io/webrtc-stats/#dom-rtcoutboundrtpstreamstats-qualitylimitationresolutionchanges
    var qualityLimitationResolutionChanges: UInt32? { stats.uint32Value("qualityLimitationResolutionChanges") }
    // https://w3c.github.io/webrtc-provisional-stats/#dom-rtcoutboundrtpstreamstats-contenttype
    var contentType: String? { stats.stringValue("contentType") }
    var encoderImplementation: String? { stats.stringValue("encoderImplementation") }
    var firCount: UInt32? { stats.uint32Value("firCount") }
    var pliCount: UInt32? { stats.uint32Value("pliCount") }
    var nackCount: UInt32? { stats.uint32Value("nackCount") }
    var qpSum: UInt64? { stats.uint64Value("qpSum") }
    var active: Bool? { stats.boolValue("active") }
    
    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCRemoteInboundRtpStreamStats: RTCReceivedRtpStreamStats {
    override class var kType: String {"remote-inbound-rtp" }
    private let stats: [String: String]
    
    var localId: String? { stats.stringValue("localId") }
    var roundTripTime: Double? { stats.doubleValue("roundTripTime") }
    var fractionLost: Double? { stats.doubleValue("fractionLost") }
    var totalRoundTripTime: Double? { stats.doubleValue("totalRoundTripTime") }
    var roundTripTimeMeasurements: Int32? { stats.int32Value("roundTripTimeMeasurements") }

    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCRemoteOutboundRtpStreamStats: RTCSentRtpStreamStats {
    override class var kType: String { "remote-outbound-rtp" }
    private let stats: [String: String]
    
    var localId: String? { stats.stringValue("localId") }
    var remoteTimestamp: Double? { stats.doubleValue("remoteTimestamp") }
    var reportsSent: UInt64? { stats.uint64Value("reportsSent") }
    var roundTripTime: Double? { stats.doubleValue("roundTripTime") }
    var roundTripTimeMeasurements: UInt64? { stats.uint64Value("roundTripTimeMeasurements") }
    var totalRoundTripTime: Double? { stats.doubleValue("totalRoundTripTime") }

    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCMediaSourceStats: RTCStats {
    class var kType: String { "parent-media-source" }
    private let stats: [String: String]
    
    var trackIdentifier: String? { stats.stringValue("trackIdentifier") }
    var kind: String? { stats.stringValue("kind") }

    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCAudioSourceStats: RTCMediaSourceStats {
    override class var kType: String { "media-source" }
    private let stats: [String: String]
    
    var audioLevel: Double? { stats.doubleValue("audioLevel") }
    var totalAudioEnergy: Double? { stats.doubleValue("totalAudioEnergy") }
    var totalSamplesDuration: Double? { stats.doubleValue("totalSamplesDuration") }
    var echoReturnLoss: Double? { stats.doubleValue("echoReturnLoss") }
    var echoReturnLossEnhancement: Double? { stats.doubleValue("echoReturnLossEnhancement") }

    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCVideoSourceStats: RTCMediaSourceStats {
    override class var kType: String { "media-source" }
    private let stats: [String: String]
    
    var width: UInt32? { stats.uint32Value("width") }
    var height: UInt32? { stats.uint32Value("height") }
    var frames: UInt32? { stats.uint32Value("frames") }
    var framesPerSecond: Double? { stats.doubleValue("framesPerSecond") }

    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private class RTCTransportStats: RTCStats {
    class var kType: String { "transport" }
    private let stats: [String: String]
    
    var bytesSent: UInt64? { stats.uint64Value("bytesSent") }
    var packetsSent: UInt64? { stats.uint64Value("packetsSent") }
    var bytesReceived: UInt64? { stats.uint64Value("bytesReceived") }
    var packetsReceived: UInt64? { stats.uint64Value("packetsReceived") }
    var rtcpTransportStatsId: String? { stats.stringValue("rtcpTransportStatsId") }
    var dtlsState: String? { stats.stringValue("dtlsState") }
    var selectedCandidatePairId: String? { stats.stringValue("selectedCandidatePairId") }
    var localCertificateId: String? { stats.stringValue("localCertificateId") }
    var remoteCertificateId: String? { stats.stringValue("remoteCertificateId") }
    var tlsVersion: String? { stats.stringValue("tlsVersion") }
    var dtlsCipher: String? { stats.stringValue("dtlsCipher") }
    var dtlsRole: String? { stats.stringValue("dtlsRole") }
    var srtpCipher: String? { stats.stringValue("srtpCipher") }
    var selectedCandidatePairChanges: UInt32? { stats.uint32Value("selectedCandidatePairChanges") }
    var iceRole: String? { stats.stringValue("iceRole") }
    var iceLocalUsernameFragment: String? { stats.stringValue("iceLocalUsernameFragment") }
    var iceState: String? { stats.stringValue("iceState") }

    override init(_ stats: [String: String]) {
        self.stats = stats
        super.init(stats)
    }
}

private extension Double {
    func kbps() -> Int {
        Int(self/1000)
    }
    
    func msec() -> Int {
        Int(self*1000)
    }
    
    func percent() -> String {
        String(format: "%.1f %%", self * 100)
    }
}

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

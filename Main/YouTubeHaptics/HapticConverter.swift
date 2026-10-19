import AVFoundation
import CoreHaptics
import Foundation

struct HapticConversion {
    let pattern: CHHapticPattern
    let eventCount: Int
    let transientCount: Int
}

/// Creates haptic events directly from the audio waveform.
/// Each 50 ms window contributes loudness, peak and zero-crossing measurements.
enum HapticConverter {
    private struct Window {
        let time: Double
        let rms: Float
        let peak: Float
        let zeroCrossingRate: Float
    }

    static func convert(audioURL: URL) throws -> HapticConversion {
        let file = try AVAudioFile(forReading: audioURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0, format.sampleRate > 0, format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return try emptyConversion()
        }
        try file.read(into: buffer)

        let rate = format.sampleRate
        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)
        guard frames > 0, let channelsData = buffer.floatChannelData else {
            return try emptyConversion()
        }

        let windowFrames = max(1, Int(rate * 0.05))
        var windows: [Window] = []
        windows.reserveCapacity((frames + windowFrames - 1) / windowFrames)

        for start in stride(from: 0, to: frames, by: windowFrames) {
            let end = min(start + windowFrames, frames)
            let count = end - start
            var energy: Double = 0
            var peak: Float = 0
            var crossings = 0
            var previous: Float = channelsData[0][start]

            for frame in start..<end {
                var sample: Float = 0
                for channel in 0..<channels { sample += channelsData[channel][frame] }
                sample /= Float(channels)
                energy += Double(sample * sample)
                peak = max(peak, abs(sample))
                if frame > start && ((sample >= 0) != (previous >= 0)) { crossings += 1 }
                previous = sample
            }

            windows.append(Window(time: Double(start) / rate,
                                  rms: Float(sqrt(energy / Double(count))),
                                  peak: peak,
                                  zeroCrossingRate: count > 1 ? Float(crossings) / Float(count - 1) : 0))
        }

        let loudness = windows.map(\.rms).sorted()
        let reference = loudness[min(loudness.count - 1, Int(Double(loudness.count - 1) * 0.95))]
        guard reference > 0.0001 else { return try emptyConversion() }

        var events: [CHHapticEvent] = []
        var transientCount = 0
        events.reserveCapacity(windows.count)

        for index in windows.indices {
            let window = windows[index]
            // Reject room noise roughly 32 dB below the clip's representative peak.
            guard window.rms >= reference * 0.025 else { continue }

            let level = min(1, max(0, window.rms / reference))
            let intensity = min(0.9, max(0.06, 0.9 * sqrt(level)))
            // A higher zero-crossing rate tends to feel sharper; low bass stays soft.
            let sharpness = min(0.95, max(0.08, sqrt(window.zeroCrossingRate) * 1.35))
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ]

            let previousLevel = index > 0 ? windows[index - 1].rms : 0
            let isOnset = window.rms > max(previousLevel * 1.65, previousLevel + reference * 0.08)
                && level > 0.35 && window.peak > reference * 0.12

            if isOnset {
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: parameters,
                                            relativeTime: window.time))
                transientCount += 1
            } else {
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: parameters,
                                            relativeTime: window.time, duration: 0.05))
            }
        }

        return HapticConversion(pattern: try CHHapticPattern(events: events, parameters: []),
                                eventCount: events.count, transientCount: transientCount)
    }

    private static func emptyConversion() throws -> HapticConversion {
        HapticConversion(pattern: try CHHapticPattern(events: [], parameters: []), eventCount: 0, transientCount: 0)
    }
}

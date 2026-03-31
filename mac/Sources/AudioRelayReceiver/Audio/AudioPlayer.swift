import AVFoundation
import Foundation

final class AudioPlayer {

    private static let sampleRate: Double = 48_000
    private static let channelCount: AVAudioChannelCount = 2
    private static let frameSizePerChannel: Int = 960
    /// Pre-buffer: wait for this many packets before starting playback.
    private static let preBufferPackets: Int = 7

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private var jitterBuffer: JitterBuffer?
    private var decoder: OpusDecoder?

    private(set) var audioLevel: Float = 0
    private(set) var isPlaying = false
    private var primed = false

    func start(jitterBuffer: JitterBuffer, decoder: OpusDecoder) {
        guard !isPlaying else { return }

        self.jitterBuffer = jitterBuffer
        self.decoder = decoder
        self.primed = false

        // AVAudioEngine on macOS requires non-interleaved (deinterleaved) format.
        let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: Self.sampleRate,
            channels: Self.channelCount
        )!

        var residual = [Float]()

        let node = AVAudioSourceNode(format: audioFormat) {
            [weak self] _, _, frameCount, audioBufferList -> OSStatus in

            guard let self = self,
                  let jitterBuffer = self.jitterBuffer,
                  let decoder = self.decoder else {
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for buf in abl {
                    if let ptr = buf.mData { memset(ptr, 0, Int(buf.mDataByteSize)) }
                }
                return noErr
            }

            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            // Pre-buffer: output silence until enough packets accumulate.
            if !self.primed {
                if jitterBuffer.packetCount >= Self.preBufferPackets {
                    self.primed = true
                    print("[AudioPlayer] Pre-buffer reached (\(jitterBuffer.packetCount) pkts), starting playback")
                } else {
                    for buf in abl {
                        if let ptr = buf.mData { memset(ptr, 0, Int(buf.mDataByteSize)) }
                    }
                    return noErr
                }
            }

            // We need `frames` interleaved stereo samples = frames * 2 floats.
            let interleavedCount = frames * Int(Self.channelCount)
            var samples = residual
            while samples.count < interleavedCount {
                if let packet = jitterBuffer.pull() {
                    if let decoded = try? decoder.decode(opusData: packet.opusData) {
                        samples.append(contentsOf: decoded)
                    } else {
                        samples.append(contentsOf: decoder.decodePLC())
                    }
                } else {
                    samples.append(contentsOf: decoder.decodePLC())
                }
            }

            if samples.count > interleavedCount {
                residual = Array(samples[interleavedCount...])
                samples = Array(samples[..<interleavedCount])
            } else {
                residual = []
            }

            // RMS level.
            var sumSq: Float = 0
            for s in samples { sumSq += s * s }
            let rms = sqrtf(sumSq / Float(max(samples.count, 1)))
            self.audioLevel = 0.3 * rms + 0.7 * self.audioLevel

            // De-interleave: Opus gives LRLRLR, AVAudioEngine wants separate L and R buffers.
            if abl.count >= 2 {
                let leftBuf = abl[0]
                let rightBuf = abl[1]
                if let leftPtr = leftBuf.mData?.assumingMemoryBound(to: Float.self),
                   let rightPtr = rightBuf.mData?.assumingMemoryBound(to: Float.self) {
                    for i in 0..<frames {
                        leftPtr[i] = samples[i * 2]
                        rightPtr[i] = samples[i * 2 + 1]
                    }
                }
            } else if let buffer = abl.first,
                      let dest = buffer.mData?.assumingMemoryBound(to: Float.self) {
                // Mono fallback — mix L+R.
                for i in 0..<frames {
                    dest[i] = (samples[i * 2] + samples[i * 2 + 1]) * 0.5
                }
            }

            return noErr
        }

        self.sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: audioFormat)

        do {
            try engine.start()
            isPlaying = true
            print("[AudioPlayer] Engine started, waiting for pre-buffer...")
        } catch {
            print("[AudioPlayer] Failed to start AVAudioEngine: \(error)")
            cleanup()
        }

        subscribeToConfigurationChanges()
    }

    func stop() {
        guard isPlaying else { return }
        engine.stop()
        cleanup()
        isPlaying = false
        audioLevel = 0
        primed = false
    }

    private var configChangeObserver: NSObjectProtocol?

    private func subscribeToConfigurationChanges() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func handleConfigurationChange() {
        print("[AudioPlayer] Audio configuration changed, restarting engine.")
        if isPlaying {
            engine.stop()
            do { try engine.start() } catch {
                print("[AudioPlayer] Failed to restart engine: \(error)")
            }
        }
    }

    private func cleanup() {
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        jitterBuffer = nil
        decoder = nil
    }
}

import Foundation
import COpus
import COpusHelpers

/// Error type for Opus decoding failures.
enum OpusDecoderError: Error {
    case createFailed(Int32)
    case decodeFailed(Int32)
}

/// Decodes Opus-encoded audio frames to interleaved Float32 PCM.
///
/// Configured for 48 kHz stereo. Each 20 ms frame produces 960 samples
/// per channel (1920 interleaved floats).
final class OpusDecoder {

    // MARK: - Constants

    static let sampleRate: Int32 = 48_000
    static let channelCount: Int32 = 2
    /// Samples per channel in a 20 ms frame at 48 kHz.
    static let frameSizePerChannel: Int = 960
    /// Total interleaved sample count per frame (960 * 2).
    static let frameSizeInterleaved: Int = frameSizePerChannel * Int(channelCount)

    // MARK: - Properties

    private let decoder: OpaquePointer

    // MARK: - Initialization

    /// Creates a new Opus decoder for 48 kHz stereo audio.
    init() throws {
        var error: Int32 = 0
        guard let dec = opus_decoder_create(Self.sampleRate, Self.channelCount, &error) else {
            throw OpusDecoderError.createFailed(error)
        }
        self.decoder = dec
    }

    deinit {
        opus_decoder_destroy(decoder)
    }

    // MARK: - Decoding

    /// Decodes an Opus packet into interleaved Float32 PCM samples.
    ///
    /// - Parameter opusData: The Opus-encoded packet data.
    /// - Returns: An array of interleaved Float32 samples (1920 floats for a 20 ms stereo frame).
    /// - Throws: `OpusDecoderError.decodeFailed` if decoding fails.
    func decode(opusData: Data) throws -> [Float] {
        var output = [Float](repeating: 0, count: Self.frameSizeInterleaved)

        let samplesDecoded = opusData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int32 in
            let opusPtr = ptr.bindMemory(to: UInt8.self).baseAddress!
            return opus_decode_float(
                decoder,
                opusPtr,
                Int32(opusData.count),
                &output,
                Int32(Self.frameSizePerChannel),
                0 // no FEC
            )
        }

        if samplesDecoded < 0 {
            throw OpusDecoderError.decodeFailed(samplesDecoded)
        }

        // If fewer samples than a full frame, trim.
        let totalSamples = Int(samplesDecoded) * Int(Self.channelCount)
        if totalSamples < output.count {
            output.removeSubrange(totalSamples..<output.count)
        }
        return output
    }

    /// Resets the decoder's internal state. Useful when the audio source changes
    /// abruptly (e.g. new video, seek) and the decoder's prediction model is stale.
    func resetState() {
        opus_helpers_decoder_reset(decoder)
    }

    /// Generates a frame of audio using Opus packet loss concealment (PLC).
    ///
    /// Call this when a packet is missing from the jitter buffer. The decoder
    /// will interpolate/extrapolate from its internal state to produce a
    /// smooth continuation of audio rather than silence.
    ///
    /// - Returns: An array of interleaved Float32 samples (1920 floats).
    func decodePLC() -> [Float] {
        var output = [Float](repeating: 0, count: Self.frameSizeInterleaved)

        let samplesDecoded = opus_decode_float(
            decoder,
            nil,   // NULL input triggers PLC
            0,
            &output,
            Int32(Self.frameSizePerChannel),
            0
        )

        if samplesDecoded < 0 {
            // PLC failure is non-fatal; return silence.
            return [Float](repeating: 0, count: Self.frameSizeInterleaved)
        }
        return output
    }
}

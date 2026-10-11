import AVFoundation
import Foundation

/// Procedural audio. Mirrors the canvas game's `Sfx` class but uses
/// AVAudioEngine so it respects the system audio session and the player's
/// SFX / sound toggles in SettingsStore.
final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private let sfxMixer: AVAudioMixerNode
    private let ambientMixer: AVAudioMixerNode
    private var ambientPlayer: AVAudioPlayer?
    private let settings: SettingsStore

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        self.sfxMixer = AVAudioMixerNode()
        self.ambientMixer = AVAudioMixerNode()
        engine.attach(sfxMixer)
        engine.attach(ambientMixer)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(ambientMixer, to: engine.mainMixerNode, format: nil)

        configureSession()
        applyVolumes()
        // Observe volume/toggle changes.
        NotificationCenter.default.addObserver(self, selector: #selector(applyVolumes),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[Mossgate:Audio] AVAudioSession error: \(error)")
        }
    }

    @objc private func applyVolumes() {
        ambientMixer.outputVolume = settings.soundOn ? Float(settings.soundVolume) : 0
        sfxMixer.outputVolume = settings.sfxOn ? Float(settings.sfxVolume) : 0
    }

    /// Resume the engine after the first user interaction (required by iOS).
    func unlock() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("[Mossgate:Audio] engine.start: \(error)")
        }
    }

    // ──────────── SFX (procedural) ────────────

    func jump(_ double: Bool = false) {
        let from: Double = double ? 560 : 420
        let to: Double = double ? 640 : 220
        tone(freqFrom: from, freqTo: to, dur: 0.11, type: .square, vol: 0.06)
    }

    func coin() {
        tone(freqFrom: 880, freqTo: 1320, dur: 0.08, type: .triangle, vol: 0.07)
        tone(freqFrom: 1320, freqTo: 1760, dur: 0.1, type: .sine, vol: 0.04, delay: 0.05)
    }

    func land() {
        noise(dur: 0.06, vol: 0.04, cutoff: 280)
    }

    func checkpoint() {
        tone(freqFrom: 520, freqTo: 780, dur: 0.14, type: .triangle, vol: 0.06)
        tone(freqFrom: 780, freqTo: 1040, dur: 0.18, type: .sine, vol: 0.05, delay: 0.08)
    }

    func die() {
        tone(freqFrom: 220, freqTo: 50, dur: 0.35, type: .sawtooth, vol: 0.07)
        noise(dur: 0.25, vol: 0.06, cutoff: 180)
    }

    func win() {
        [523, 659, 784, 1046].enumerated().forEach { i, freq in
            tone(freqFrom: Double(freq), freqTo: Double(freq) * 1.01, dur: 0.2,
                 type: .triangle, vol: 0.06, delay: Double(i) * 0.09)
        }
    }

    func tap() {
        tone(freqFrom: 320, freqTo: 480, dur: 0.06, type: .sine, vol: 0.04)
    }

    // ──────────── Tone synth helpers ────────────

    private enum WaveformType { case sine, square, triangle, sawtooth }

    private func tone(freqFrom: Double, freqTo: Double, dur: Double,
                     type: WaveformType, vol: Double, delay: Double = 0) {
        guard settings.sfxOn else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frameTotal = AVAudioFrameCount(dur * format.sampleRate + delay * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameTotal) else { return }
        buffer.frameLength = frameTotal

        let data = buffer.floatChannelData![0]
        let startSample = Int(delay * format.sampleRate)
        let durSamples = Int(dur * format.sampleRate)
        let sampleRate = Float(format.sampleRate)
        for i in 0..<durSamples {
            let t = Float(i) / sampleRate
            let progress = Float(i) / Float(durSamples)
            let freq = Float(freqFrom) + (Float(freqTo) - Float(freqFrom)) * progress
            let phase = 2.0 * .pi * freq * t
            let raw: Float
            switch type {
            case .sine:     raw = sin(phase)
            case .square:   raw = sin(phase) > 0 ? 1 : -1
            case .triangle: raw = (2.0 / .pi) * asin(sin(phase))
            case .sawtooth: raw = 2.0 * (t * freq - floor(0.5 + t * freq))
            }
            let env = Float(vol) * (1.0 - progress)
            data[startSample + i] = raw * env
        }
        // Schedule on the SFX mixer.
        sfxMixer.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func noise(dur: Double, vol: Double, cutoff: Double) {
        guard settings.sfxOn else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frameTotal = AVAudioFrameCount(dur * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameTotal) else { return }
        buffer.frameLength = frameTotal

        let data = buffer.floatChannelData![0]
        let n = Int(frameTotal)
        for i in 0..<n {
            let env = Float(vol) * Float(1.0 - Double(i) / Double(n))
            data[i] = Float.random(in: -1...1) * env
        }
        sfxMixer.scheduleBuffer(buffer, completionHandler: nil)
    }
}
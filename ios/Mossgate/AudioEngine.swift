import AVFoundation
import Foundation

/// Audio. Sound effects are synthesised in code; the two background music
/// tracks are bundled AAC files (see scripts/make-music.py) played on a looping
/// player node. Everything routes through AVAudioEngine so it respects the
/// system audio session and the player's sound / SFX toggles in SettingsStore.
final class AudioEngine {
    static let shared = AudioEngine()

    /// The two looping background tracks. Raw values are the bundled file names.
    enum MusicTrack: String, CaseIterable {
        case dusk   // Mossgate Dusk — title screen and world 0
        case ember  // Ember Caves — world 1
    }

    private let engine = AVAudioEngine()
    private let sfxNode = AVAudioPlayerNode()
    private let ambientNode = AVAudioPlayerNode()
    private let sfxMixer: AVAudioMixerNode
    private let ambientMixer: AVAudioMixerNode
    private let settings: SettingsStore

    /// Decoded music, kept so switching back to a track costs nothing.
    private var musicBuffers: [MusicTrack: AVAudioPCMBuffer] = [:]
    private var currentMusic: MusicTrack?
    /// The last track asked for, even while muted — so re-enabling sound can
    /// start it again without waiting for the next level change.
    private var musicWanted: MusicTrack?

    /// Dedicated serial queue for all AVAudioEngine operations. SpriteKit calls
    /// our scene's `step(_:)` on the main thread; calling `scheduleBuffer` on
    /// the main thread can throw an NSException inside AVFAudio. Routing
    /// everything through this queue keeps the audio engine happy.
    private let audioQueue = DispatchQueue(label: "io.jphsystems.mossgate.audio", qos: .userInitiated)
    private var isEngineStarted = false
    private let startLock = NSLock()

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        self.sfxMixer = AVAudioMixerNode()
        self.ambientMixer = AVAudioMixerNode()
        engine.attach(sfxNode)
        engine.attach(sfxMixer)
        engine.attach(ambientNode)
        engine.attach(ambientMixer)
        // Connect the sfxNode with an explicit mono 44.1 kHz format. Without
        // this, the node defaults to the engine's mainMixer output (stereo),
        // and `scheduleBuffer` fails at runtime with
        // "_outputFormat.channelCount == buffer.format.channelCount" because
        // the SFX buffers are mono (see `tone()`).
        let sfxFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        // The music path is stereo, matching the bundled AAC files.
        let musicFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.connect(sfxNode, to: sfxMixer, format: sfxFormat)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: sfxFormat)
        engine.connect(ambientNode, to: ambientMixer, format: musicFormat)
        engine.connect(ambientMixer, to: engine.mainMixerNode, format: musicFormat)

        configureSession()
        applyVolumes()
        // Observe volume/toggle changes.
        NotificationCenter.default.addObserver(self, selector: #selector(applyVolumes),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    private func configureSession() {
        // iOS 18+ warns when AVAudioSession setters run on the main thread.
        // Use the async API so it doesn't block the first frame.
        let session = AVAudioSession.sharedInstance()
        Task.detached(priority: .userInitiated) {
            do {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                print("[Mossgate:Audio] AVAudioSession error: \(error)")
            }
        }
    }

    @objc private func applyVolumes() {
        ambientMixer.outputVolume = settings.soundOn ? Float(settings.soundVolume) : 0
        sfxMixer.outputVolume = settings.sfxOn ? Float(settings.sfxVolume) : 0
        // Turning sound back on should bring the music back immediately rather
        // than waiting for the next level change.
        if settings.soundOn, let wanted = musicWanted,
           currentMusic != wanted || !ambientNode.isPlaying {
            playMusic(wanted)
        }
    }

    // ──────────── Background music ────────────

    /// Start, or switch to, a looping background track. Safe to call from
    /// anywhere and as often as you like — re-requesting the track that is
    /// already playing is a no-op.
    func playMusic(_ track: MusicTrack) {
        musicWanted = track
        guard settings.soundOn else { return }          // started later if re-enabled
        guard currentMusic != track || !ambientNode.isPlaying else { return }
        currentMusic = track

        ensureEngineStarted()
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.engine.isRunning { Thread.sleep(forTimeInterval: 0.08) }
            guard self.engine.isRunning else {
                print("[Mossgate:Audio] music \(track.rawValue): engine not running")
                return
            }

            let buffer: AVAudioPCMBuffer
            if let cached = self.musicBuffers[track] {
                buffer = cached
            } else {
                guard let loaded = Self.loadMusicBuffer(track) else {
                    print("[Mossgate:Audio] music \(track.rawValue): could not load from bundle")
                    return
                }
                self.musicBuffers[track] = loaded
                buffer = loaded
            }

            // The ambient path is connected as stereo 44.1 kHz; scheduling a
            // buffer in any other format aborts inside AVFAudio.
            guard buffer.format.channelCount == 2,
                  buffer.format.sampleRate == 44_100 else {
                print("[Mossgate:Audio] music \(track.rawValue): unexpected format "
                      + "\(buffer.format.channelCount)ch @ \(buffer.format.sampleRate)Hz")
                return
            }

            self.ambientNode.stop()
            self.ambientNode.scheduleBuffer(buffer, at: nil, options: .loops,
                                            completionHandler: nil)
            self.ambientNode.play()
            if ProcessInfo.processInfo.arguments.contains("-TestSfx") {
                let secs = Double(buffer.frameLength) / buffer.format.sampleRate
                print("[Mossgate:AUDIO] music \(track.rawValue) frames=\(buffer.frameLength) "
                      + "(\(String(format: "%.1f", secs))s) ch=\(buffer.format.channelCount) "
                      + "running=\(self.engine.isRunning) vol=\(self.ambientMixer.outputVolume)")
            }
        }
    }

    /// Fade out and drop the current track (used when leaving for the splash).
    func stopMusic() {
        musicWanted = nil
        currentMusic = nil
        audioQueue.async { [weak self] in
            self?.ambientNode.stop()
        }
    }

    /// Decodes a bundled track into a PCM buffer for looping. Prefers the
    /// AAC file; falls back to WAV if a raw render is present.
    private static func loadMusicBuffer(_ track: MusicTrack) -> AVAudioPCMBuffer? {
        let url = Bundle.main.url(forResource: track.rawValue, withExtension: "m4a")
               ?? Bundle.main.url(forResource: track.rawValue, withExtension: "wav")
        guard let url else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }

        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: frames) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            print("[Mossgate:Audio] music read \(track.rawValue): \(error)")
            return nil
        }
        return buffer
    }

    /// Resume the engine after the first user interaction (required by iOS).
    /// Called lazily on the first SFX — the engine is then started on the audio
    /// queue, never on the main thread.
    private func ensureEngineStarted() {
        startLock.lock()
        let alreadyRunning = isEngineStarted
        startLock.unlock()
        if alreadyRunning { return }

        audioQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.engine.isRunning else { return }
            do {
                try self.engine.start()
                self.startLock.lock()
                self.isEngineStarted = true
                self.startLock.unlock()
            } catch {
                print("[Mossgate:Audio] engine.start: \(error)")
            }
        }
    }

    /// Schedule a buffer on the SFX node, off the main thread. Crashes inside
    /// AVFAudio's `scheduleBuffer` cannot be caught by Swift `try` — they are
    /// NSExceptions thrown on the main thread when the engine isn't ready or
    /// the node is being torn down. Routing through a serial queue avoids that.
    private func scheduleSFX(_ buffer: AVAudioPCMBuffer) {
        ensureEngineStarted()
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            // Wait briefly for the engine to actually start before scheduling.
            // 50ms is enough on the simulator; the first frame won't fire SFX
            // until the user touches a control anyway.
            if !self.engine.isRunning {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if ProcessInfo.processInfo.arguments.contains("-TestSfx") {
                print("[Mossgate:AUDIO] schedule frames=\(buffer.frameLength) running=\(self.engine.isRunning) mixerVol=\(self.sfxMixer.outputVolume) nodeVol=\(self.sfxNode.volume) formatCh=\(buffer.format.channelCount)")
            }
            self.sfxNode.scheduleBuffer(buffer, completionHandler: nil)
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

    /// How many harmonics still fit below Nyquist for `f`. Partials past this
    /// point fold back down as inharmonic tones — the harsh metallic buzz the
    /// old naive `sin(phase) > 0 ? 1 : -1` square produced.
    private static func harmonicLimit(_ f: Double) -> Int {
        max(1, min(24, Int(20_000.0 / max(abs(f), 1.0))))
    }

    private func tone(freqFrom: Double, freqTo: Double, dur: Double,
                     type: WaveformType, vol: Double, delay: Double = 0) {
        guard settings.sfxOn else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let sr = format.sampleRate
        let frameTotal = AVAudioFrameCount((dur + delay) * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameTotal) else { return }
        buffer.frameLength = frameTotal

        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameTotal) { data[i] = 0 }

        let startSample = Int(delay * sr)
        let durSamples = Int(dur * sr)
        guard durSamples > 0 else { return }

        let harmonics = Self.harmonicLimit(max(abs(freqFrom), abs(freqTo)))
        let attack = min(0.004 * sr, Double(durSamples) * 0.3)   // 4 ms, never the whole note

        var raw = [Float](repeating: 0, count: durSamples)
        var phase = 0.0
        var peak: Float = 0.0001
        for i in 0..<durSamples {
            let progress = Double(i) / Double(durSamples)
            let freq = freqFrom + (freqTo - freqFrom) * progress

            // Additive up to Nyquist, so no partial can alias. Triangle and
            // saw use the standard alternating signs.
            var s = 0.0
            for k in 1...harmonics {
                if type == .square && k % 2 == 0 { continue }
                let a: Double
                switch type {
                case .sine:     a = (k == 1) ? 1 : 0
                case .square:   a = 1.0 / Double(k)
                case .triangle: a = 1.0 / Double(k * k) * (k % 4 == 1 ? 1 : -1)
                case .sawtooth: a = 1.0 / Double(k) * (k % 2 == 1 ? 1 : -1)
                }
                if a != 0 { s += a * sin(Double(k) * phase) }
            }

            // Attack then decay to silence: the old `(1 - progress)` started at
            // full amplitude, which is a step discontinuity — an audible click.
            let env: Double
            if Double(i) < attack {
                env = Double(i) / attack
            } else {
                env = 1.0 - (Double(i) - attack) / max(1.0, Double(durSamples) - attack)
            }
            let v = Float(s * env)
            raw[i] = v
            peak = max(peak, abs(v))

            // Integrate the frequency. `2π · freq · t` is only correct for a
            // constant pitch; on a sweep its derivative is freq + t·df/dt, which
            // made the jump/coin/die glides warble.
            phase += 2.0 * .pi * freq / sr
            if phase > 2.0 * .pi { phase -= 2.0 * .pi * (phase / (2.0 * .pi)).rounded(.down) }
        }

        // Normalise so each effect peaks at exactly `vol` whichever waveform it
        // uses — consistent loudness across the whole set.
        let gain = Float(vol) / peak
        for i in 0..<durSamples { data[startSample + i] = raw[i] * gain }
        scheduleSFX(buffer)
    }

    private func noise(dur: Double, vol: Double, cutoff: Double) {
        guard settings.sfxOn else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let sr = format.sampleRate
        let frameTotal = AVAudioFrameCount(dur * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameTotal) else { return }
        buffer.frameLength = frameTotal

        let data = buffer.floatChannelData![0]
        let n = Int(frameTotal)
        guard n > 0 else { return }

        // `cutoff` used to be accepted and then ignored, so every landing and
        // death was a full-bandwidth white-noise burst — the hiss. Two cascaded
        // one-pole low passes give a soft thud instead of interference.
        let rc = 1.0 / (2.0 * Double.pi * max(cutoff, 1))
        let alpha = (1.0 / sr) / (rc + 1.0 / sr)

        var raw = [Float](repeating: 0, count: n)
        var y1 = 0.0, y2 = 0.0
        var peak: Float = 0.0001
        for i in 0..<n {
            y1 += alpha * (Double.random(in: -1...1) - y1)
            y2 += alpha * (y1 - y2)
            let env = 1.0 - Double(i) / Double(n)
            let v = Float(y2 * env)
            raw[i] = v
            peak = max(peak, abs(v))
        }
        let gain = Float(vol) / peak
        for i in 0..<n { data[i] = raw[i] * gain }
        scheduleSFX(buffer)
    }
}

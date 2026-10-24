import AVFoundation

/// Original BGM and effects bundled in Resources/Brushing.
@MainActor
final class BrushingSound {
    enum Track: String { case menu = "brushing-menu", brushing = "brushing-bgm" }
    enum Effect: String, CaseIterable { case pop, chime, fanfare, select, tap }

    var isEnabled = true {
        didSet { if !isEnabled { stopMusic() } }
    }

    private var current: Track?
    private lazy var tracks: [Track: AVAudioPlayer] = Dictionary(
        uniqueKeysWithValues: [Track.menu, .brushing].compactMap { track in
            Self.player(track.rawValue, loops: true).map { (track, $0) }
        }
    )
    private lazy var effects: [Effect: AVAudioPlayer] = Dictionary(
        uniqueKeysWithValues: Effect.allCases.compactMap { effect in
            Self.player("brushing-\(effect.rawValue)", loops: false).map { (effect, $0) }
        }
    )

    /// Switches to `track` from the start; keeps playing if it is already on.
    func playMusic(_ track: Track) {
        guard isEnabled else { return }
        if current == track, tracks[track]?.isPlaying == true { return }
        stopMusic()
        activate()
        tracks[track]?.currentTime = 0
        tracks[track]?.play()
        current = track
    }

    func stopMusic() {
        tracks.values.forEach { $0.stop() }
        current = nil
    }

    func play(_ effect: Effect) {
        guard isEnabled, let player = effects[effect] else { return }
        activate()
        player.currentTime = 0
        player.play()
    }

    func deactivate() {
        stopMusic()
        effects.values.forEach { $0.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func activate() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private static func player(_ name: String, loops: Bool) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = loops ? -1 : 0
        player.volume = loops ? 0.5 : 0.9
        player.prepareToPlay()
        return player
    }
}

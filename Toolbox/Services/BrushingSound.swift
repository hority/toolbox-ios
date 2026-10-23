import AVFoundation

/// Original BGM and effects bundled in Resources/Brushing.
@MainActor
final class BrushingSound {
    enum Effect: String { case pop, chime, fanfare }

    var isEnabled = true {
        didSet { if !isEnabled { stopMusic() } }
    }

    private lazy var music = Self.player("brushing-bgm", loops: true)
    private lazy var effects: [Effect: AVAudioPlayer] = Dictionary(
        uniqueKeysWithValues: [Effect.pop, .chime, .fanfare].compactMap { effect in
            Self.player("brushing-\(effect.rawValue)", loops: false).map { (effect, $0) }
        }
    )

    func startMusic() {
        guard isEnabled else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        music?.currentTime = 0
        music?.play()
    }

    func stopMusic() {
        music?.stop()
    }

    func play(_ effect: Effect) {
        guard isEnabled, let player = effects[effect] else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.currentTime = 0
        player.play()
    }

    func deactivate() {
        stopMusic()
        effects.values.forEach { $0.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func player(_ name: String, loops: Bool) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = loops ? -1 : 0
        player.volume = loops ? 0.55 : 0.9
        player.prepareToPlay()
        return player
    }
}

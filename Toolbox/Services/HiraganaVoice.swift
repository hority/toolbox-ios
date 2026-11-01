import AVFoundation

/// On-device Japanese speech. Sign in with ChatGPT offers no speech endpoint, so the best
/// installed system voice (premium > enhanced > default) is used and nothing leaves the device.
@MainActor final class HiraganaVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language == "ja-JP" }
        .max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "ja-JP")

    /// A lone は or へ would be read as a particle (wa / e); katakana keeps the letter's own sound.
    static func reading(_ character: String) -> String {
        character.applyingTransform(.hiraganaToKatakana, reverse: false) ?? character
    }

    func say(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.15
        synthesizer.speak(utterance)
    }

    func letter(_ character: String) { say(Self.reading(character)) }

    func caught(_ characters: [String]) {
        guard !characters.isEmpty else { say("ひらがなが、みつからなかったよ"); return }
        say(characters.prefix(8).map(Self.reading).joined(separator: "、") + "、ゲット！")
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

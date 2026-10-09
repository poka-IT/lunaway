import AVFoundation

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

/// The spoken instructions of the guidance, through the system's own speech
/// synthesis on iOS and macOS: the voices installed on the device, nothing
/// downloaded by the app. On iOS the audio session is the one Apple
/// describes for navigation prompts (`voicePrompt`): music ducks under the
/// instruction, a podcast pauses, and both come back once it is said. macOS
/// has no audio session to ask for: the instruction plays over the rest.
///
/// The chime before an alert plays through `AVAudioPlayer` in the same
/// session, and the sentence starts once it has ended. A `speak` call answers
/// when its sentence is over (said, cut or failed), so the app says one
/// sentence at a time.
public class LunawayNavPlugin: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate,
  AVAudioPlayerDelegate
{
  private let synthesizer = AVSpeechSynthesizer()

  /// The chime's WAV bytes, handed over once per run.
  private var chime: Data?

  /// The chime playing now, and what waits for its end: the sentence to say
  /// after it (none for the chime alone) and the caller's answer.
  private var player: AVAudioPlayer?
  private var afterChime: (utterance: AVSpeechUtterance?, result: FlutterResult)?

  /// The answers of the sentences being said, by utterance, each called once:
  /// by the synthesizer's end of it, or by `stop`.
  private var pending: [ObjectIdentifier: (utterance: AVSpeechUtterance, result: FlutterResult)] =
    [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "lunaway_nav/voice", binaryMessenger: messenger)
    let instance = LunawayNavPlugin()
    instance.synthesizer.delegate = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "voices":
      result(voices(for: args["language"] as? String ?? ""))
    case "languageStatus":
      let found = !voices(for: args["language"] as? String ?? "").isEmpty
      result(found ? "available" : "notSupported")
    case "setChime":
      // Kept only if the player can read it.
      let data = (args["wav"] as? FlutterStandardTypedData)?.data
      if let data = data, (try? AVAudioPlayer(data: data)) != nil {
        chime = data
        result(true)
      } else {
        result(false)
      }
    case "speak":
      speak(
        text: args["text"] as? String ?? "",
        language: args["language"] as? String ?? "",
        voiceId: args["voiceId"] as? String,
        rate: args["rate"] as? Double ?? 1.0,
        chime: args["chime"] as? Bool ?? false,
        result: result)
    case "stop":
      stopAll()
      result(nil)
    case "installVoiceData":
      // iOS offers no way in: the app explains where the voices are.
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func voices(for language: String) -> [[String: Any]] {
    let wanted = String(language.prefix(2)).lowercased()
    return AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.lowercased().hasPrefix(wanted) }
      .map { voice in
        [
          "id": voice.identifier,
          "locale": voice.language,
          "networkRequired": false,
          "notInstalled": false,
          "quality": quality(voice),
        ]
      }
  }

  /// Android's scale (300 normal, 400 high, 500 very high), so the app ranks
  /// voices the same way on both platforms.
  private func quality(_ voice: AVSpeechSynthesisVoice) -> Int {
    switch voice.quality {
    case .premium: return 500
    case .enhanced: return 400
    default: return 300
    }
  }

  private func speak(
    text: String, language: String, voiceId: String?, rate: Double, chime withChime: Bool,
    result: @escaping FlutterResult
  ) {
    var utterance: AVSpeechUtterance?
    if !text.isEmpty {
      let u = AVSpeechUtterance(string: text)
      u.voice =
        voiceId.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
        ?? AVSpeechSynthesisVoice(language: language)
      u.rate = Float(Double(AVSpeechUtteranceDefaultSpeechRate) * rate)
      utterance = u
    }
    if utterance == nil && !(withChime && chime != nil) {
      result(false)
      return
    }
    activateSession()
    if withChime, let data = chime, let player = try? AVAudioPlayer(data: data) {
      // The app says one sentence at a time; a chime left over is cut.
      cutChime()
      player.delegate = self
      player.prepareToPlay()
      self.player = player
      afterChime = (utterance, result)
      if player.play() { return }
      // A chime that cannot play does not hold the sentence back.
      self.player = nil
      afterChime = nil
    }
    guard let utterance = utterance else {
      result(false)
      release()
      return
    }
    say(utterance, result)
  }

  private func say(_ utterance: AVSpeechUtterance, _ result: @escaping FlutterResult) {
    pending[ObjectIdentifier(utterance)] = (utterance, result)
    synthesizer.speak(utterance)
  }

  #if os(iOS)
    private func activateSession() {
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(
          .playback, mode: .voicePrompt,
          options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try session.setActive(true)
      } catch {
        // Speech still works without the session; it just does not duck.
      }
    }
  #else
    private func activateSession() {}
  #endif

  /// Ends the chime and answers what waited for it, without the sentence.
  private func cutChime() {
    player?.stop()
    player = nil
    if let waiting = afterChime {
      afterChime = nil
      waiting.result(false)
    }
  }

  private func stopAll() {
    cutChime()
    let running = pending
    pending.removeAll()
    synthesizer.stopSpeaking(at: .immediate)
    for entry in running.values { entry.result(false) }
    release()
  }

  private func finish(_ utterance: AVSpeechUtterance, said: Bool) {
    if let entry = pending.removeValue(forKey: ObjectIdentifier(utterance)) {
      entry.result(said)
    }
    release()
  }

  /// The chime is over: the sentence after it starts, or the chime alone is
  /// answered.
  private func chimeEnded(_ player: AVAudioPlayer, played: Bool) {
    guard player === self.player, let waiting = afterChime else { return }
    self.player = nil
    afterChime = nil
    if let utterance = waiting.utterance {
      say(utterance, waiting.result)
    } else {
      waiting.result(played)
      release()
    }
  }

  private func release() {
    #if os(iOS)
      guard !synthesizer.isSpeaking, player == nil else { return }
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }

  public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    DispatchQueue.main.async { self.chimeEnded(player, played: flag) }
  }

  public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    DispatchQueue.main.async { self.chimeEnded(player, played: false) }
  }

  public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    DispatchQueue.main.async { self.finish(utterance, said: true) }
  }

  public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    DispatchQueue.main.async { self.finish(utterance, said: false) }
  }
}

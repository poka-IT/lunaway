import AVFoundation
import Flutter
import UIKit

/// The spoken instructions of the guidance, through iOS's own speech
/// synthesis: the voices installed on the device, nothing downloaded by the
/// app. The audio session is the one Apple describes for navigation prompts
/// (`voicePrompt`): music ducks under the instruction, a podcast pauses, and
/// both come back once it is said.
public class LunawayNavPlugin: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "lunaway_nav/voice", binaryMessenger: registrar.messenger())
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
    case "speak":
      result(
        speak(
          text: args["text"] as? String ?? "",
          language: args["language"] as? String ?? "",
          voiceId: args["voiceId"] as? String,
          rate: args["rate"] as? Double ?? 1.0,
          queue: args["queue"] as? Bool ?? false))
    case "stop":
      synthesizer.stopSpeaking(at: .immediate)
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
    text: String, language: String, voiceId: String?, rate: Double, queue: Bool
  ) -> Bool {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playback, mode: .voicePrompt,
        options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
      try session.setActive(true)
    } catch {
      // Speech still works without the session; it just does not duck.
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice =
      voiceId.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
      ?? AVSpeechSynthesisVoice(language: language)
    utterance.rate = Float(Double(AVSpeechUtteranceDefaultSpeechRate) * rate)
    // The synthesizer queues what it is given: a new instruction cuts the
    // one being said, a warning waits for it.
    if !queue { synthesizer.stopSpeaking(at: .immediate) }
    synthesizer.speak(utterance)
    return true
  }

  private func release() {
    guard !synthesizer.isSpeaking else { return }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    release()
  }

  public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    release()
  }
}

package legal.p2p.lunaway.nav

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

/**
 * The spoken instructions of the guidance, through Android's own speech
 * engine: nothing is downloaded by the app and nothing leaves the device
 * unless the user's engine does so itself (a voice that needs the network is
 * reported as such, and the app prefers the others).
 *
 * The speech uses the navigation guidance audio usage and asks for a
 * transient focus that lets music duck under it, as a navigation app does.
 */
class LunawayNavPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var tts: TextToSpeech? = null

    /** Null while the engine starts, then its status. */
    private var engineStatus: Int? = null
    private val waiting = mutableListOf<(TextToSpeech?) -> Unit>()
    private val main = Handler(Looper.getMainLooper())
    private var focus: AudioFocusRequest? = null

    private val attributes: AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "lunaway_nav/voice")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        tts?.stop()
        tts?.shutdown()
        tts = null
        engineStatus = null
        releaseFocus()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "voices" -> withEngine(result) { engine ->
                val language = call.argument<String>("language") ?: ""
                result.success(voicesFor(engine, language))
            }
            "languageStatus" -> withEngine(result) { engine ->
                val language = call.argument<String>("language") ?: ""
                result.success(
                    when (engine.isLanguageAvailable(Locale.forLanguageTag(language))) {
                        TextToSpeech.LANG_MISSING_DATA -> "missingData"
                        TextToSpeech.LANG_NOT_SUPPORTED -> "notSupported"
                        else -> "available"
                    },
                )
            }
            "speak" -> withEngine(result) { engine ->
                val text = call.argument<String>("text") ?: ""
                val language = call.argument<String>("language") ?: ""
                val voiceId = call.argument<String>("voiceId")
                val rate = call.argument<Double>("rate") ?: 1.0
                val queue = call.argument<Boolean>("queue") ?: false
                result.success(speak(engine, text, language, voiceId, rate.toFloat(), queue))
            }
            "stop" -> {
                tts?.stop()
                releaseFocus()
                result.success(null)
            }
            "installVoiceData" -> {
                val ctx = context
                if (ctx == null) {
                    result.success(false)
                } else {
                    val intent =
                        Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    result.success(
                        try {
                            ctx.startActivity(intent)
                            true
                        } catch (e: Exception) {
                            false
                        },
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [action] once the engine is ready; answers an error when there is none. */
    private fun withEngine(result: MethodChannel.Result, action: (TextToSpeech) -> Unit) {
        val run: (TextToSpeech?) -> Unit = { engine ->
            if (engine == null) {
                result.error("unavailable", "no speech engine on this device", null)
            } else {
                action(engine)
            }
        }
        val status = engineStatus
        val engine = tts
        when {
            engine != null && status == TextToSpeech.SUCCESS -> run(engine)
            status != null && status != TextToSpeech.SUCCESS -> run(null)
            else -> {
                waiting.add(run)
                if (engine == null) start()
            }
        }
    }

    private fun start() {
        val ctx = context ?: return
        tts =
            TextToSpeech(ctx) { status ->
                main.post {
                    engineStatus = status
                    val engine = if (status == TextToSpeech.SUCCESS) tts else null
                    engine?.setAudioAttributes(attributes)
                    engine?.setOnUtteranceProgressListener(
                        object : UtteranceProgressListener() {
                            override fun onStart(utteranceId: String?) {}

                            override fun onDone(utteranceId: String?) {
                                main.post { releaseFocus() }
                            }

                            @Deprecated("Deprecated in Java")
                            override fun onError(utteranceId: String?) {
                                main.post { releaseFocus() }
                            }

                            override fun onStop(utteranceId: String?, interrupted: Boolean) {
                                main.post { releaseFocus() }
                            }
                        },
                    )
                    val pending = waiting.toList()
                    waiting.clear()
                    pending.forEach { it(engine) }
                }
            }
    }

    private fun voicesFor(engine: TextToSpeech, language: String): List<Map<String, Any?>> {
        val wanted = Locale.forLanguageTag(language).language
        val voices: Set<Voice> = engine.voices ?: emptySet()
        return voices
            .filter { it.locale.language == wanted }
            .map { voice ->
                mapOf(
                    "id" to voice.name,
                    "locale" to voice.locale.toLanguageTag(),
                    "networkRequired" to voice.isNetworkConnectionRequired,
                    "notInstalled" to
                        voice.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED),
                    "quality" to voice.quality,
                )
            }
    }

    private fun speak(
        engine: TextToSpeech,
        text: String,
        language: String,
        voiceId: String?,
        rate: Float,
        queue: Boolean,
    ): Boolean {
        val voice = voiceId?.let { id -> engine.voices?.firstOrNull { it.name == id } }
        if (voice != null) {
            engine.voice = voice
        } else {
            engine.language = Locale.forLanguageTag(language)
        }
        engine.setSpeechRate(rate)
        requestFocus()
        val queued =
            engine.speak(
                text,
                if (queue) TextToSpeech.QUEUE_ADD else TextToSpeech.QUEUE_FLUSH,
                null,
                UUID.randomUUID().toString(),
            )
        if (queued != TextToSpeech.SUCCESS) releaseFocus()
        return queued == TextToSpeech.SUCCESS
    }

    private fun audioManager(): AudioManager? =
        context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    @Suppress("DEPRECATION")
    private fun requestFocus() {
        val audio = audioManager() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request =
                focus
                    ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                        .setAudioAttributes(attributes)
                        .build()
            focus = request
            audio.requestAudioFocus(request)
        } else {
            audio.requestAudioFocus(
                null,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun releaseFocus() {
        val audio = audioManager() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focus?.let { audio.abandonAudioFocusRequest(it) }
        } else {
            audio.abandonAudioFocus(null)
        }
    }
}

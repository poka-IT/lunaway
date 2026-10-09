package legal.p2p.lunaway.nav

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.Locale
import java.util.UUID

/**
 * The spoken instructions of the guidance, through Android's own speech
 * engine: nothing is downloaded by the app, and a voice that needs the
 * network is reported as such; the app speaks with installed voices only, so
 * the instructions stay on the device.
 *
 * The speech uses the navigation guidance audio usage and asks for a
 * transient focus that lets music duck under it, as a navigation app does.
 * The chime before an alert plays in the app's own process, with the same
 * usage and under the same focus, and the sentence is queued once it has
 * ended. It cannot be an earcon of the engine: the engine runs in another
 * app, which cannot open a file of this app's private storage (measured
 * on the emulator with Google's engine: ENOENT, and no end ever reported).
 *
 * A `speak` call answers when its sentence is over (said, cut or failed),
 * so the app says one sentence at a time.
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

    /** The chime, written to the app's files once the app hands it over. */
    private var chimeFile: File? = null

    /** The chime playing now; its end queues the sentence after it. */
    private var chimePlayer: MediaPlayer? = null

    /** The utterance id of the `speak` that waits for [chimePlayer]. */
    private var chimeFor: String? = null

    /**
     * Counts the `stop` calls: a `speak` that waited for the engine to start
     * while one came is answered without a word.
     */
    private var stops = 0

    /**
     * The answers of the `speak` calls still running, by utterance id. Each
     * is answered exactly once, on the main thread: by the engine's end of
     * the utterance (or the chime's, for the chime alone), by `stop`, or when
     * the plugin is detached.
     */
    private val pending = mutableMapOf<String, MethodChannel.Result>()

    private val attributes: AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

    private val chimeAttributes: AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "lunaway_nav/voice")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        stops++
        cutChime()
        tts?.stop()
        tts?.shutdown()
        tts = null
        engineStatus = null
        finishAll()
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
            "setChime" -> result.success(setChime(call.argument<ByteArray>("wav")))
            "speak" -> {
                val asked = stops
                withEngine(result) { engine ->
                    if (asked != stops) {
                        result.success(false)
                    } else {
                        val text = call.argument<String>("text") ?: ""
                        val language = call.argument<String>("language") ?: ""
                        val voiceId = call.argument<String>("voiceId")
                        val rate = call.argument<Double>("rate") ?: 1.0
                        val chime = call.argument<Boolean>("chime") ?: false
                        speak(engine, text, language, voiceId, rate.toFloat(), chime, result)
                    }
                }
            }
            "stop" -> {
                stops++
                cutChime()
                tts?.stop()
                finishAll()
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
                                main.post { finish(utteranceId, true) }
                            }

                            @Deprecated("Deprecated in Java")
                            override fun onError(utteranceId: String?) {
                                main.post { finish(utteranceId, false) }
                            }

                            override fun onStop(utteranceId: String?, interrupted: Boolean) {
                                main.post { finish(utteranceId, false) }
                            }
                        },
                    )
                    val pendingCalls = waiting.toList()
                    waiting.clear()
                    pendingCalls.forEach { it(engine) }
                }
            }
    }

    /**
     * Writes [wav] where the media player reads it: among the app's files
     * that are not backed up, which the system never empties, unlike the
     * cache.
     */
    private fun setChime(wav: ByteArray?): Boolean {
        val ctx = context ?: return false
        if (wav == null || wav.isEmpty()) return false
        return try {
            val file = File(ctx.noBackupFilesDir, "lunaway_alert_chime.wav")
            file.writeBytes(wav)
            chimeFile = file
            true
        } catch (e: IOException) {
            false
        }
    }

    /**
     * Plays [file] for the `speak` of [id] and calls [ended] once, on the
     * main thread, with whether it played to its end; never when [cutChime]
     * stops it first.
     */
    private fun playChime(file: File, id: String, ended: (Boolean) -> Unit) {
        cutChime()
        val player = MediaPlayer()
        fun end(played: Boolean) {
            if (chimePlayer !== player) return
            chimePlayer = null
            chimeFor = null
            player.release()
            ended(played)
        }
        try {
            player.setAudioAttributes(chimeAttributes)
            // A small file of the app's own: read at once.
            player.setDataSource(file.absolutePath)
            player.setOnCompletionListener { end(true) }
            player.setOnErrorListener { _, _, _ ->
                end(false)
                true
            }
            player.prepare()
            chimePlayer = player
            chimeFor = id
            player.start()
        } catch (e: Exception) {
            chimePlayer = null
            chimeFor = null
            player.release()
            ended(false)
        }
    }

    /**
     * Stops the chime playing, whose end then calls nobody: the `speak`
     * waiting for it is answered here, without its sentence.
     */
    private fun cutChime() {
        val player = chimePlayer ?: return
        val waiting = chimeFor
        chimePlayer = null
        chimeFor = null
        player.release()
        if (waiting != null) finish(waiting, false)
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

    /**
     * Plays the chime, when asked and known, then queues [text], and
     * answers [result] when the sentence ends, or when the chime ends for
     * the chime alone.
     */
    private fun speak(
        engine: TextToSpeech,
        text: String,
        language: String,
        voiceId: String?,
        rate: Float,
        chime: Boolean,
        result: MethodChannel.Result,
    ) {
        val chimeFile = this.chimeFile
        val withChime = chime && chimeFile != null
        if (text.isEmpty() && !withChime) {
            result.success(false)
            return
        }
        val voice = voiceId?.let { id -> engine.voices?.firstOrNull { it.name == id } }
        if (voice != null) {
            engine.voice = voice
        } else {
            engine.language = Locale.forLanguageTag(language)
        }
        engine.setSpeechRate(rate)
        val id = UUID.randomUUID().toString()
        pending[id] = result
        requestFocus()
        if (chimeFile == null || !withChime) {
            say(engine, text, id)
            return
        }
        playChime(chimeFile, id) { played ->
            // Stopped meanwhile: already answered, nothing more to say.
            if (pending.containsKey(id)) {
                // Without its chime, a sentence is still worth saying.
                if (text.isEmpty()) finish(id, played) else say(engine, text, id)
            }
        }
    }

    private fun say(engine: TextToSpeech, text: String, id: String) {
        val queued = engine.speak(text, TextToSpeech.QUEUE_ADD, null, id)
        if (queued != TextToSpeech.SUCCESS) finish(id, false)
    }

    /** Answers the `speak` of [utteranceId], once; the focus goes with the last one. */
    private fun finish(utteranceId: String?, said: Boolean) {
        val result = pending.remove(utteranceId ?: return) ?: return
        result.success(said)
        if (pending.isEmpty()) releaseFocus()
    }

    /** Answers every `speak` still running: nothing more will be said. */
    private fun finishAll() {
        val results = pending.values.toList()
        pending.clear()
        results.forEach { it.success(false) }
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

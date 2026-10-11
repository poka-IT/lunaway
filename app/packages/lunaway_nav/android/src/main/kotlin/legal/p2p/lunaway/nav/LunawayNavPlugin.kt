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
import java.util.MissingResourceException
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The spoken instructions of the guidance, through the speech engines of
 * the device: nothing is downloaded by the app, and a voice that needs the
 * network is reported as such; the app speaks with installed voices only, so
 * the instructions stay on the device.
 *
 * A device may carry several engines (Google's, its maker's, eSpeak NG,
 * RHVoice), one of them chosen in the system's settings. The app asks the
 * default one first and the others only when it has no voice of the
 * language; it then speaks with the engine the app picked (`useEngine`). A
 * language is matched on its ISO 639 code, two or three letters, as engines
 * name it either way.
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

    /** One engine of the device, bound when first asked for. */
    private class Engine {
        var tts: TextToSpeech? = null

        /** Null while the engine starts, then its status. */
        var status: Int? = null
        val waiting = mutableListOf<(TextToSpeech?) -> Unit>()
    }

    /** The device's default engine, bound without naming it. */
    private var defaultSlot = Engine()

    /** Its package, once it is bound. */
    private var defaultName: String? = null

    /** The other engines asked for, by package. */
    private val others = mutableMapOf<String, Engine>()

    /** The engine the app speaks with; null for the default one. */
    private var speaker: String? = null
    private val main = Handler(Looper.getMainLooper())

    /**
     * Where the voices and the languages are asked of an engine, away
     * from the main thread, which also draws the app: the engine runs in
     * another process, and Google's lists hundreds of voices, a binder call
     * that holds its caller as long as it takes.
     */
    private var lists: ExecutorService? = null
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
        lists = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "lunaway_nav/voice")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        stops++
        cutChime()
        unbindAll()
        lists?.shutdown()
        lists = null
        finishAll()
        releaseFocus()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "engines" -> withEngine(defaultSlot, result) { engine -> result.success(enginesOf(engine)) }
            "voices" -> {
                val language = call.argument<String>("language") ?: ""
                withEngine(slot(call.argument<String>("engine")), result) { engine ->
                    offMain(result) { voicesFor(engine, language) }
                }
            }
            "languageStatus" -> {
                val language = call.argument<String>("language") ?: ""
                withEngine(slot(call.argument<String>("engine")), result) { engine ->
                    offMain(result) { statusOf(engine, Locale.forLanguageTag(language)) }
                }
            }
            "useEngine" -> {
                useEngine(call.argument<String>("engine"))
                result.success(null)
            }
            "refresh" -> {
                // Called while nothing is said with an engine (the voice
                // was missing): what was installed or chosen meanwhile is
                // seen by engines bound anew.
                unbindAll()
                result.success(null)
            }
            "setChime" -> result.success(setChime(call.argument<ByteArray>("wav")))
            "speak" -> {
                val text = call.argument<String>("text") ?: ""
                val chime = call.argument<Boolean>("chime") ?: false
                val chimeFile = this.chimeFile
                when {
                    // The chime alone needs no speech engine: a device
                    // without one, or without a voice, still hears it
                    // before an alert.
                    text.isEmpty() && chime && chimeFile != null -> chimeAlone(chimeFile, result)
                    text.isEmpty() -> result.success(false)
                    else -> {
                        val asked = stops
                        withEngine(slot(speaker), result) { engine ->
                            if (asked != stops) {
                                result.success(false)
                            } else {
                                val language = call.argument<String>("language") ?: ""
                                val voiceId = call.argument<String>("voiceId")
                                val rate = call.argument<Double>("rate") ?: 1.0
                                speak(engine, text, language, voiceId, rate.toFloat(), chime, result)
                            }
                        }
                    }
                }
            }
            "stop" -> {
                stops++
                cutChime()
                defaultSlot.tts?.stop()
                others.values.forEach { it.tts?.stop() }
                finishAll()
                releaseFocus()
                result.success(null)
            }
            "installVoiceData" -> result.success(installVoiceData(call.argument<String>("engine")))
            else -> result.notImplemented()
        }
    }

    /**
     * Opens the page of [engine] that installs voices, or, with no engine
     * named or one that has none, the system's choice among the engines.
     */
    private fun installVoiceData(engine: String?): Boolean {
        val ctx = context ?: return false
        val intent =
            Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (engine != null) {
            val own = Intent(intent).setPackage(engine)
            if (own.resolveActivity(ctx.packageManager) != null) {
                return try {
                    ctx.startActivity(own)
                    true
                } catch (e: Exception) {
                    false
                }
            }
        }
        return try {
            ctx.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** The slot of [name]; the default engine's when null or its own name. */
    private fun slot(name: String?): Engine =
        if (name == null || name == defaultName) defaultSlot else others.getOrPut(name) { Engine() }

    /**
     * Speaks from now on with [name] (null: the default engine), and lets go
     * of the other engines asked about, which the system would otherwise
     * keep running for this app.
     */
    private fun useEngine(name: String?) {
        speaker = if (name == defaultName) null else name
        val keep = speaker
        val iterator = others.entries.iterator()
        while (iterator.hasNext()) {
            val (key, engine) = iterator.next()
            if (key != keep) {
                unbind(engine)
                iterator.remove()
            }
        }
    }

    private fun unbind(engine: Engine) {
        engine.tts?.stop()
        engine.tts?.shutdown()
        engine.tts = null
        engine.status = null
        val waiting = engine.waiting.toList()
        engine.waiting.clear()
        waiting.forEach { it(null) }
    }

    private fun unbindAll() {
        unbind(defaultSlot)
        defaultSlot = Engine()
        defaultName = null
        others.values.forEach { unbind(it) }
        others.clear()
    }

    /** The engines of the device, the default one first. */
    private fun enginesOf(engine: TextToSpeech): List<Map<String, Any?>> {
        val default = engine.defaultEngine
        defaultName = default
        return engine.engines
            .sortedBy { if (it.name == default) 0 else 1 }
            .map { info ->
                mapOf(
                    "name" to info.name,
                    "label" to info.label,
                    "isDefault" to (info.name == default),
                )
            }
    }

    /** Runs [read] on [lists] and answers its value, or its failure, on the main thread. */
    private fun offMain(
        result: MethodChannel.Result,
        read: () -> Any?,
    ) {
        val pool = lists
        if (pool == null) {
            result.error("unavailable", "the plugin is detached", null)
            return
        }
        pool.execute {
            val value = runCatching(read)
            main.post {
                value.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("unavailable", it.message, null) },
                )
            }
        }
    }

    /** Runs [action] once [slot]'s engine is ready; answers an error when there is none. */
    private fun withEngine(slot: Engine, result: MethodChannel.Result, action: (TextToSpeech) -> Unit) {
        val run: (TextToSpeech?) -> Unit = { engine ->
            if (engine == null) {
                result.error("unavailable", "no speech engine on this device", null)
            } else {
                action(engine)
            }
        }
        val status = slot.status
        val engine = slot.tts
        when {
            engine != null && status == TextToSpeech.SUCCESS -> run(engine)
            status != null && status != TextToSpeech.SUCCESS -> run(null)
            else -> {
                slot.waiting.add(run)
                if (engine == null) start(slot)
            }
        }
    }

    private fun start(slot: Engine) {
        val ctx = context ?: return
        val name = if (slot === defaultSlot) null else others.entries.firstOrNull { it.value === slot }?.key
        val onInit =
            TextToSpeech.OnInitListener { status ->
                main.post {
                    // Let go of meanwhile (refresh, another engine chosen):
                    // whoever waited was answered then.
                    if (slot.tts == null) return@post
                    slot.status = status
                    val engine = if (status == TextToSpeech.SUCCESS) slot.tts else null
                    engine?.setAudioAttributes(attributes)
                    engine?.setOnUtteranceProgressListener(progress)
                    val pendingCalls = slot.waiting.toList()
                    slot.waiting.clear()
                    pendingCalls.forEach { it(engine) }
                }
            }
        slot.tts = if (name == null) TextToSpeech(ctx, onInit) else TextToSpeech(ctx, onInit, name)
    }

    private val progress =
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

    /**
     * The voices of [language] in [engine], their locale written with two
     * letters where it has them: an engine may name French `fra`, and the
     * app compares tags.
     */
    private fun voicesFor(engine: TextToSpeech, language: String): List<Map<String, Any?>> {
        val wanted = Locale.forLanguageTag(language)
        val voices: Set<Voice> = engine.voices ?: emptySet()
        return voices
            .filter { sameLanguage(it.locale, wanted) }
            .map { voice ->
                mapOf(
                    "id" to voice.name,
                    "locale" to tagOf(voice.locale),
                    "networkRequired" to voice.isNetworkConnectionRequired,
                    "notInstalled" to
                        voice.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED),
                    "quality" to voice.quality,
                )
            }
    }

    /**
     * Whether [engine] speaks [locale] now, for an engine that lists no
     * voice of it: available, through its vendor's server only, once its
     * data is downloaded, or not at all.
     */
    @Suppress("DEPRECATION")
    private fun statusOf(engine: TextToSpeech, locale: Locale): String =
        when (engine.isLanguageAvailable(locale)) {
            TextToSpeech.LANG_MISSING_DATA -> "missingData"
            TextToSpeech.LANG_NOT_SUPPORTED -> "notSupported"
            else -> {
                val features = engine.getFeatures(locale).orEmpty()
                when {
                    TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED in features -> "missingData"
                    TextToSpeech.Engine.KEY_FEATURE_NETWORK_SYNTHESIS in features &&
                        TextToSpeech.Engine.KEY_FEATURE_EMBEDDED_SYNTHESIS !in features -> "network"
                    else -> "available"
                }
            }
        }

    /**
     * Plays the chime, when asked and known, then queues [text], never
     * empty, and answers [result] when the sentence ends.
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
        val chimeFile = this.chimeFile
        if (!chime || chimeFile == null) {
            say(engine, text, id)
            return
        }
        playChime(chimeFile, id) { _ ->
            // Stopped meanwhile: already answered, nothing more to say.
            // Without its chime, a sentence is still worth saying.
            if (pending.containsKey(id)) say(engine, text, id)
        }
    }

    /** Plays the chime alone, and answers [result] when it ends. */
    private fun chimeAlone(file: File, result: MethodChannel.Result) {
        val id = UUID.randomUUID().toString()
        pending[id] = result
        requestFocus()
        playChime(file, id) { played -> finish(id, played) }
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

    companion object {
        /** Three-letter ISO 639 codes to two-letter ones, read once. */
        private val twoLetterLanguages: Map<String, String> by lazy {
            Locale.getISOLanguages()
                .mapNotNull { code -> iso3Language(Locale.forLanguageTag(code))?.let { it to code } }
                .toMap()
        }

        /** Three-letter ISO 3166 codes to two-letter ones, read once. */
        private val twoLetterCountries: Map<String, String> by lazy {
            Locale.getISOCountries()
                .mapNotNull { code ->
                    try {
                        Locale.Builder().setRegion(code).build().isO3Country
                            .takeIf { it.isNotEmpty() }
                            ?.let { it to code }
                    } catch (e: MissingResourceException) {
                        null
                    } catch (e: java.util.IllformedLocaleException) {
                        null
                    }
                }
                .toMap()
        }

        private fun iso3Language(locale: Locale): String? =
            try {
                locale.isO3Language.takeIf { it.isNotEmpty() }?.lowercase(Locale.ROOT)
            } catch (e: MissingResourceException) {
                null
            }

        /** Whether [locale] is of [wanted]'s language, named with two letters or three. */
        fun sameLanguage(locale: Locale, wanted: Locale): Boolean {
            if (locale.language.equals(wanted.language, ignoreCase = true)) return true
            val a = iso3Language(locale)
            return a != null && a == iso3Language(wanted)
        }

        /** [locale] as a language tag with two-letter codes where they exist: `fr-FR`. */
        fun tagOf(locale: Locale): String {
            val language = locale.language.lowercase(Locale.ROOT)
            val country = locale.country.uppercase(Locale.ROOT)
            val lang = if (language.length == 3) twoLetterLanguages[language] ?: language else language
            val region = if (country.length == 3) twoLetterCountries[country] ?: country else country
            return if (region.isEmpty()) lang else "$lang-$region"
        }
    }
}

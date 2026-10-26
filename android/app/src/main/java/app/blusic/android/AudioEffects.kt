package app.blusic.android

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import kotlin.math.*

/** Ten peaking filters per channel, calculated only when settings change. */
class TenBandEqualizer {
    private data class Filter(val b0: Double, val b1: Double, val b2: Double, val a1: Double, val a2: Double, var z1: Double = 0.0, var z2: Double = 0.0) {
        fun sample(x: Double): Double { val y = b0 * x + z1; z1 = b1 * x - a1 * y + z2; z2 = b2 * x - a2 * y; return y }
    }
    private var filters: List<List<Filter>> = emptyList()
    private var headroom = 1.0
    fun configure(sampleRate: Int, channels: Int, gains: List<Float>) {
        headroom = 10.0.pow(-maxOf(0f, gains.maxOrNull() ?: 0f) / 20.0)
        filters = List(channels) { frequencies.mapIndexed { index, frequency ->
            val a = 10.0.pow((gains.getOrNull(index) ?: 0f).coerceIn(-12f, 12f) / 40.0)
            val w = 2 * PI * min(frequency, sampleRate * .45) / sampleRate; val alpha = sin(w) / 2; val a0 = 1 + alpha / a
            Filter((1 + alpha * a) / a0, -2 * cos(w) / a0, (1 - alpha * a) / a0, -2 * cos(w) / a0, (1 - alpha / a) / a0)
        } }
    }
    fun process(sample: Float, channel: Int): Float {
        var value = sample.toDouble() * headroom
        for (filter in filters[channel]) value = filter.sample(value)
        return value.coerceIn(-1.0, 1.0).toFloat()
    }
    companion object { val frequencies = listOf(31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0) }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class EqualizerAudioProcessor(private val settings: () -> LibraryState) : BaseAudioProcessor() {
    private val eq = TenBandEqualizer(); private var previous: List<Float>? = null; private val flat = List(10) { 0f }
    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        previous = null; return inputAudioFormat
    }
    override fun queueInput(inputBuffer: ByteBuffer) {
        val s = settings(); val gains = if (s.equalizerEnabled) s.equalizer else flat
        if (previous != gains) { eq.configure(inputAudioFormat.sampleRate, inputAudioFormat.channelCount, gains); previous = gains.toList() }
        val buffer = replaceOutputBuffer(inputBuffer.remaining()); var channel = 0
        while (inputBuffer.remaining() >= 2) {
            val sample = inputBuffer.short
            buffer.putShort(if (s.equalizerEnabled) (eq.process(sample / 32768f, channel) * 32767).toInt().toShort() else sample)
            channel = (channel + 1) % inputAudioFormat.channelCount
        }
        buffer.flip()
    }
    override fun onFlush() { previous = null }
}

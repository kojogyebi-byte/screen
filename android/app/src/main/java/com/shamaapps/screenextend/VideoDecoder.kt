package com.shamaapps.screenextend

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue

/*
 * Hardware H.264 decoder that renders directly to a Surface.
 *
 * Uses MediaCodec asynchronous mode. Because input buffers arrive via callback,
 * incoming packets and free input-buffer indices are matched in a single FIFO so
 * the codec-config (SPS/PPS) is always submitted before the first frame.
 */
class VideoDecoder(
    private val surface: Surface,
    private val onError: (String) -> Unit,
) {
    private data class Packet(val data: ByteArray, val isConfig: Boolean)

    private var codec: MediaCodec? = null
    private val pending = ConcurrentLinkedQueue<Packet>()
    private val availableInputs = ConcurrentLinkedQueue<Int>()
    private val lock = Any()
    @Volatile private var started = false

    fun start(width: Int, height: Int) {
        if (started) return
        try {
            val format = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC, width, height
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }

            val c = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            c.setCallback(object : MediaCodec.Callback() {
                override fun onInputBufferAvailable(mc: MediaCodec, index: Int) {
                    availableInputs.add(index)
                    pump()
                }

                override fun onOutputBufferAvailable(
                    mc: MediaCodec, index: Int, info: MediaCodec.BufferInfo
                ) {
                    try {
                        // render = true: hand the frame to the surface.
                        mc.releaseOutputBuffer(index, true)
                    } catch (e: Exception) {
                        onError(e.message ?: "release output failed")
                    }
                }

                override fun onError(mc: MediaCodec, e: MediaCodec.CodecException) {
                    onError("decoder: ${e.message}")
                }

                override fun onOutputFormatChanged(mc: MediaCodec, format: MediaFormat) {
                    // Surface handles sizing automatically.
                }
            })
            c.configure(format, surface, null, 0)
            c.start()
            codec = c
            started = true
            pump()
        } catch (e: Exception) {
            onError(e.message ?: "decoder init failed")
        }
    }

    /** Feed SPS/PPS (Annex-B). Submitted with the codec-config flag. */
    fun submitConfig(data: ByteArray) {
        pending.add(Packet(data, true))
        pump()
    }

    /** Feed one H.264 access unit (Annex-B). */
    fun submitFrame(data: ByteArray) {
        pending.add(Packet(data, false))
        pump()
    }

    private fun pump() {
        val c = codec ?: return
        synchronized(lock) {
            while (true) {
                val packet = pending.peek() ?: return
                val index = availableInputs.poll() ?: return
                pending.poll()
                try {
                    val buffer: ByteBuffer = c.getInputBuffer(index) ?: continue
                    buffer.clear()
                    buffer.put(packet.data)
                    val flags = if (packet.isConfig) {
                        MediaCodec.BUFFER_FLAG_CODEC_CONFIG
                    } else 0
                    c.queueInputBuffer(index, 0, packet.data.size, 0, flags)
                } catch (e: Exception) {
                    onError(e.message ?: "queue input failed")
                    return
                }
            }
        }
    }

    fun stop() {
        started = false
        try { codec?.stop() } catch (_: Exception) {}
        try { codec?.release() } catch (_: Exception) {}
        codec = null
        pending.clear()
        availableInputs.clear()
    }
}

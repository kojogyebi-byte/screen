package com.shamaapps.screenextend

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer

/*
 * Single-connection TCP client speaking the ScreenExtend wire protocol.
 *
 * Frame layout (all multi-byte integers big-endian):
 *   [1 byte messageType][4 byte payloadLength][payload...]
 *
 * Mac -> Tablet:
 *   0x01 INFO    JSON {"w":Int,"h":Int,"fps":Int}
 *   0x02 CONFIG  H.264 SPS/PPS (Annex-B)
 *   0x03 FRAME   [1 byte keyframeFlag][H.264 access unit, Annex-B]
 *
 * Tablet -> Mac:
 *   0x10 POINTER [1 byte action][nx][ny][dx][dy]  (4x IEEE-754 big-endian float)
 */
class StreamClient(
    private val host: String,
    private val port: Int,
    private val nativeWidth: Int,
    private val nativeHeight: Int,
    private val densityDpi: Int,
    private val deviceName: String,
    private val onInfo: (w: Int, h: Int, fps: Int) -> Unit,
    private val onConfig: (ByteArray) -> Unit,
    private val onFrame: (data: ByteArray, isKeyframe: Boolean) -> Unit,
    private val onError: (String) -> Unit,
    private val onConnected: () -> Unit,
) {
    companion object {
        const val MSG_INFO = 0x01
        const val MSG_CONFIG = 0x02
        const val MSG_FRAME = 0x03
        const val MSG_POINTER = 0x10
        const val MSG_HELLO = 0x11
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private var job: Job? = null
    private var socket: Socket? = null
    private var output: DataOutputStream? = null
    @Volatile private var running = false

    fun connect() {
        if (running) return
        running = true
        job = scope.launch {
            try {
                val s = Socket()
                s.tcpNoDelay = true
                s.connect(InetSocketAddress(host, port), 8000)
                socket = s
                output = DataOutputStream(s.getOutputStream())
                onConnected()
                sendHello()
                readLoop(DataInputStream(BufferedInputStream(s.getInputStream())))
            } catch (e: Exception) {
                if (running) onError(e.message ?: "connection failed")
            } finally {
                close()
            }
        }
    }

    private fun readLoop(input: DataInputStream) {
        val header = ByteArray(5)
        while (running) {
            input.readFully(header, 0, 5)
            val type = header[0].toInt() and 0xFF
            val len = ((header[1].toInt() and 0xFF) shl 24) or
                    ((header[2].toInt() and 0xFF) shl 16) or
                    ((header[3].toInt() and 0xFF) shl 8) or
                    (header[4].toInt() and 0xFF)
            if (len < 0 || len > 64 * 1024 * 1024) {
                throw IllegalStateException("bad frame length $len")
            }
            val payload = ByteArray(len)
            if (len > 0) input.readFully(payload, 0, len)

            when (type) {
                MSG_INFO -> {
                    val json = JSONObject(String(payload, Charsets.UTF_8))
                    onInfo(json.getInt("w"), json.getInt("h"), json.optInt("fps", 30))
                }
                MSG_CONFIG -> onConfig(payload)
                MSG_FRAME -> {
                    if (payload.isNotEmpty()) {
                        val isKey = payload[0].toInt() != 0
                        val unit = payload.copyOfRange(1, payload.size)
                        onFrame(unit, isKey)
                    }
                }
                else -> { /* ignore unknown */ }
            }
        }
    }

    /** Report this tablet's native size and name so the Mac can pick a resolution. */
    private fun sendHello() {
        val out = output ?: return
        try {
            val json = JSONObject()
                .put("w", nativeWidth)
                .put("h", nativeHeight)
                .put("dpi", densityDpi)
                .put("name", deviceName)
                .toString()
            val bytes = json.toByteArray(Charsets.UTF_8)
            synchronized(out) {
                out.writeByte(MSG_HELLO)
                out.writeInt(bytes.size)
                out.write(bytes)
                out.flush()
            }
        } catch (e: Exception) {
            if (running) onError(e.message ?: "hello failed")
        }
    }

    /*
     * Send a pointer event. nx/ny are normalized [0,1] surface coordinates.
     * dx/dy carry scroll deltas (only used for SCROLL).
     */
    fun sendPointer(action: Int, nx: Float, ny: Float, dx: Float, dy: Float) {
        val out = output ?: return
        scope.launch {
            try {
                // Payload: [1 byte action][nx][ny][dx][dy] = 17 bytes.
                // ByteBuffer is big-endian by default, matching the Mac parser.
                val buf = ByteBuffer.allocate(17)
                buf.put(action.toByte())
                buf.putFloat(nx); buf.putFloat(ny); buf.putFloat(dx); buf.putFloat(dy)
                synchronized(out) {
                    out.writeByte(MSG_POINTER)
                    out.writeInt(17)
                    out.write(buf.array())
                    out.flush()
                }
            } catch (e: Exception) {
                if (running) onError(e.message ?: "send failed")
            }
        }
    }

    fun close() {
        running = false
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        output = null
        job?.cancel()
        job = null
    }
}

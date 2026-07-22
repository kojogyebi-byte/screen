package com.shamaapps.screenextend

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import org.json.JSONObject
import java.net.ServerSocket
import kotlin.concurrent.thread

/**
 * Makes this tablet discoverable to the Expanse Mac app over the local network
 * (NSD / Bonjour, "_expanse._tcp") and listens on a small control port. When the
 * Mac hands over its address, [onConnect] fires so the app can connect back to
 * the Mac's video server. Runs only while the connection screen is showing.
 */
class TabletAdvertiser(
    private val context: Context,
    private val serviceName: String,
    private val controlPort: Int,
    private val onConnect: (host: String, port: Int) -> Unit,
) {
    companion object {
        const val SERVICE_TYPE = "_expanse._tcp"
    }

    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var serverSocket: ServerSocket? = null
    @Volatile private var running = false

    fun start() {
        if (running) return
        running = true
        thread(name = "expanse-control") { serve() }
    }

    private fun serve() {
        try {
            val server = ServerSocket(controlPort)
            serverSocket = server
            registerService()
            while (running) {
                val socket = try {
                    server.accept()
                } catch (e: Exception) {
                    if (running) continue else break
                }
                try {
                    val line = socket.getInputStream().bufferedReader().readLine()
                    socket.close()
                    if (!line.isNullOrBlank()) {
                        val json = JSONObject(line)
                        val host = json.getString("host")
                        val port = json.optInt("port", 53121)
                        onConnect(host, port)
                    }
                } catch (_: Exception) {
                    try { socket.close() } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {
            // Control port unavailable — discovery just won't work; manual entry still does.
        }
    }

    private fun registerService() {
        try {
            val mgr = context.getSystemService(Context.NSD_SERVICE) as NsdManager
            val info = NsdServiceInfo().apply {
                serviceName = this@TabletAdvertiser.serviceName
                serviceType = SERVICE_TYPE
                port = controlPort
            }
            val listener = object : NsdManager.RegistrationListener {
                override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {}
                override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {}
                override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            }
            mgr.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
            nsdManager = mgr
            registrationListener = listener
        } catch (_: Exception) {
        }
    }

    fun stop() {
        running = false
        try {
            registrationListener?.let { nsdManager?.unregisterService(it) }
        } catch (_: Exception) {}
        registrationListener = null
        nsdManager = null
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
    }
}

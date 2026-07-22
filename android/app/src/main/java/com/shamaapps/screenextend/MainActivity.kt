package com.shamaapps.screenextend

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import android.app.Activity

private const val PREFS = "screenextend"
private const val KEY_HOST = "host"
private const val KEY_PORT = "port"
private const val DEFAULT_PORT = 53121
private const val CONTROL_PORT = 53123

private val BgTop = Color(0xFF0B1221)
private val BgBottom = Color(0xFF16294F)
private val Accent = Color(0xFF4F9CFF)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent { App() }
    }
}

private val DarkColors = darkColorScheme(
    primary = Accent,
    background = BgTop,
    surface = Color(0xFF131C2E),
)

@Composable
fun App() {
    MaterialTheme(colorScheme = DarkColors) {
        var connected by remember { mutableStateOf(false) }
        var host by remember { mutableStateOf("") }
        var port by remember { mutableStateOf(DEFAULT_PORT) }

        if (connected) {
            StreamingScreen(host = host, port = port, onDisconnect = { connected = false })
        } else {
            ConnectionScreen(onConnect = { h, p -> host = h; port = p; connected = true })
        }
    }
}

@Composable
private fun BrandMark(size: Int = 72) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(RoundedCornerShape((size * 0.24f).dp))
            .background(
                Brush.linearGradient(listOf(Color(0xFF101A33), Color(0xFF2B5CC8)))
            ),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.size((size * 0.62f).dp)) {
            val w = this.size.width
            val h = this.size.height
            drawRoundRect(
                color = Color(0xFF3E5EA6),
                topLeft = Offset(w * 0.06f, h * 0.16f),
                size = Size(w * 0.54f, h * 0.40f),
                cornerRadius = CornerRadius(w * 0.05f, w * 0.05f),
            )
            drawRoundRect(
                color = Color(0xFF5AA0FF),
                topLeft = Offset(w * 0.34f, h * 0.36f),
                size = Size(w * 0.56f, h * 0.44f),
                cornerRadius = CornerRadius(w * 0.06f, w * 0.06f),
            )
        }
    }
}

@Composable
fun ConnectionScreen(onConnect: (String, Int) -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE) }
    var hostText by remember { mutableStateOf(prefs.getString(KEY_HOST, "") ?: "") }
    var portText by remember { mutableStateOf(prefs.getInt(KEY_PORT, DEFAULT_PORT).toString()) }
    val deviceName = remember { deviceModelName() }
    val mainHandler = remember { Handler(Looper.getMainLooper()) }

    DisposableEffect(Unit) {
        val advertiser = TabletAdvertiser(
            context = context.applicationContext,
            serviceName = deviceName,
            controlPort = CONTROL_PORT,
            onConnect = { host, port -> mainHandler.post { onConnect(host, port) } },
        )
        advertiser.start()
        onDispose { advertiser.stop() }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(BgTop, BgBottom))),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 40.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            BrandMark(72)
            Spacer(Modifier.height(18.dp))
            Text("Expanse", fontSize = 36.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Spacer(Modifier.height(6.dp))
            Text(
                "A second screen for your Mac",
                fontSize = 15.sp,
                color = Color.White.copy(alpha = 0.65f),
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(34.dp))

            OutlinedTextField(
                value = hostText,
                onValueChange = { hostText = it.trim() },
                label = { Text("Mac IP address") },
                placeholder = { Text("192.168.1.42") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(0.72f),
            )
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = portText,
                onValueChange = { portText = it.filter { c -> c.isDigit() } },
                label = { Text("Port") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(0.72f),
            )
            Spacer(Modifier.height(24.dp))

            Button(
                onClick = {
                    val h = hostText.trim()
                    val p = portText.toIntOrNull() ?: DEFAULT_PORT
                    if (h.isNotEmpty()) {
                        prefs.edit().putString(KEY_HOST, h).putInt(KEY_PORT, p).apply()
                        onConnect(h, p)
                    }
                },
                enabled = hostText.isNotBlank(),
                modifier = Modifier.fillMaxWidth(0.72f).height(50.dp),
            ) {
                Text("Connect", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }

            Spacer(Modifier.height(20.dp))
            Text(
                "On the same Wi-Fi, open Expanse on your Mac — this tablet shows up there to pick. Or enter the Mac's address above and connect.",
                fontSize = 12.sp,
                color = Color.White.copy(alpha = 0.5f),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(0.82f),
            )
        }

        Text(
            "Discoverable on your Mac as \u201C$deviceName\u201D",
            fontSize = 11.sp,
            color = Color.White.copy(alpha = 0.4f),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 14.dp),
        )
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun StreamingScreen(host: String, port: Int, onDisconnect: () -> Unit) {
    HideSystemBars()

    val context = LocalContext.current
    val native = remember { nativeLandscapeSize(context) }
    val deviceName = remember { deviceModelName() }
    val dpi = remember { context.resources.displayMetrics.densityDpi }

    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    var aspect by remember { mutableFloatStateOf(16f / 10f) }
    var status by remember { mutableStateOf("Connecting\u2026") }
    var resText by remember { mutableStateOf("") }
    var showBar by remember { mutableStateOf(true) }
    var boxW by remember { mutableStateOf(1) }
    var boxH by remember { mutableStateOf(1) }

    val decoderRef = remember { mutableStateOf<VideoDecoder?>(null) }
    val clientRef = remember { mutableStateOf<StreamClient?>(null) }
    val connected = remember { mutableStateOf(false) }

    val touch = remember {
        TouchHandler { action, nx, ny, dx, dy ->
            clientRef.value?.sendPointer(action, nx, ny, dx, dy)
        }
    }

    fun onMain(block: () -> Unit) = mainHandler.post(block)

    val holderCallback = remember {
        object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                if (connected.value) return
                connected.value = true

                val decoder = VideoDecoder(holder.surface) { e ->
                    onMain { status = "Error: $e" }
                }
                decoder.start(1920, 1080)
                decoderRef.value = decoder

                val client = StreamClient(
                    host = host,
                    port = port,
                    nativeWidth = native.first,
                    nativeHeight = native.second,
                    densityDpi = dpi,
                    deviceName = deviceName,
                    onInfo = { w, h, _ ->
                        onMain {
                            if (h > 0) aspect = w.toFloat() / h.toFloat()
                            resText = "$w × $h"
                        }
                    },
                    onConfig = { decoder.submitConfig(it) },
                    onFrame = { data, _ -> decoder.submitFrame(data) },
                    onError = { e -> onMain { status = "Error: $e" } },
                    onConnected = { onMain { status = "Connected" } },
                )
                client.connect()
                clientRef.value = client
            }

            override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, ht: Int) {}
            override fun surfaceDestroyed(holder: SurfaceHolder) {}
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            clientRef.value?.close()
            decoderRef.value?.stop()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .aspectRatio(aspect)
                .onSizeChanged { boxW = it.width; boxH = it.height }
                .pointerInteropFilter { ev: MotionEvent -> touch.onTouch(ev, boxW, boxH) }
        ) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx -> SurfaceView(ctx).apply { holder.addCallback(holderCallback) } },
            )
        }

        if (showBar) {
            Row(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 12.dp)
                    .clip(RoundedCornerShape(22.dp))
                    .background(Color(0xE6131C2E))
                    .padding(start = 16.dp, end = 8.dp, top = 4.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(8.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(if (status == "Connected") Color(0xFF37D07A) else Color(0xFFF2B33D))
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    if (resText.isEmpty()) status else "Expanse · $resText",
                    color = Color.White,
                    fontSize = 13.sp,
                    fontFamily = FontFamily.Monospace,
                )
                Spacer(Modifier.width(10.dp))
                TextButton(onClick = onDisconnect) { Text("Disconnect") }
                TextButton(onClick = { showBar = false }) { Text("Hide") }
            }
        } else {
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .height(28.dp)
                    .pointerInteropFilter { ev ->
                        if (ev.actionMasked == MotionEvent.ACTION_DOWN) showBar = true
                        false
                    }
            )
        }
    }
}

@Composable
fun HideSystemBars() {
    val view = LocalView.current
    DisposableEffect(Unit) {
        val window = (view.context as Activity).window
        val controller = WindowInsetsControllerCompat(window, view)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        onDispose { controller.show(WindowInsetsCompat.Type.systemBars()) }
    }
}

private fun deviceModelName(): String {
    val manufacturer = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
    val model = Build.MODEL ?: ""
    return if (model.startsWith(manufacturer, ignoreCase = true)) model else "$manufacturer $model"
}

private fun nativeLandscapeSize(context: Context): Pair<Int, Int> {
    val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    val w: Int
    val h: Int
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val bounds = wm.currentWindowMetrics.bounds
        w = bounds.width()
        h = bounds.height()
    } else {
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(dm)
        w = dm.widthPixels
        h = dm.heightPixels
    }
    return if (w >= h) Pair(w, h) else Pair(h, w)
}

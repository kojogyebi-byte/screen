package com.shamaapps.screenextend

import android.view.MotionEvent
import kotlin.math.abs

/**
 * Translates tablet touch gestures into ScreenExtend pointer messages.
 *
 *   1 finger            -> left button (down / drag / up), direct-touch mapping
 *   2 fingers, dragging -> scroll (centroid delta)
 *   2 fingers, quick tap-> right click
 *
 * Once two fingers are down the gesture stays in scroll/right-click mode until
 * every finger lifts, so a sloppy second finger never injects a stray click.
 */
class TouchHandler(
    private val send: (action: Int, nx: Float, ny: Float, dx: Float, dy: Float) -> Unit
) {
    companion object {
        const val ACTION_MOVE = 0
        const val ACTION_DOWN = 1
        const val ACTION_UP = 2
        const val ACTION_DRAG = 3
        const val ACTION_RIGHT_DOWN = 4
        const val ACTION_RIGHT_UP = 5
        const val ACTION_SCROLL = 6

        // Flip to -1f if two-finger scrolling feels inverted on your setup.
        private const val SCROLL_SIGN = 1f
        // Converts finger travel (px) into scroll wheel pixels.
        private const val SCROLL_GAIN = 1.5f
        private const val TAP_TIMEOUT_MS = 280L
        private const val TAP_MOVE_SLOP = 24f
    }

    private enum class Mode { IDLE, SINGLE, MULTI }
    private var mode = Mode.IDLE

    private var lastCx = 0f
    private var lastCy = 0f
    private var multiStartTime = 0L
    private var multiMaxMove = 0f
    private var vw = 1
    private var vh = 1

    fun onTouch(event: MotionEvent, viewWidth: Int, viewHeight: Int): Boolean {
        vw = if (viewWidth > 0) viewWidth else 1
        vh = if (viewHeight > 0) viewHeight else 1

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                mode = Mode.SINGLE
                send(ACTION_DOWN, nx(event, 0), ny(event, 0), 0f, 0f)
            }

            MotionEvent.ACTION_POINTER_DOWN -> {
                if (mode == Mode.SINGLE) {
                    // Lift the left button we pressed on the first finger.
                    send(ACTION_UP, nx(event, 0), ny(event, 0), 0f, 0f)
                }
                mode = Mode.MULTI
                val (cx, cy) = centroid(event)
                lastCx = cx; lastCy = cy
                multiStartTime = event.eventTime
                multiMaxMove = 0f
            }

            MotionEvent.ACTION_MOVE -> when (mode) {
                Mode.SINGLE ->
                    send(ACTION_DRAG, nx(event, 0), ny(event, 0), 0f, 0f)
                Mode.MULTI -> {
                    val (cx, cy) = centroid(event)
                    val ddx = cx - lastCx
                    val ddy = cy - lastCy
                    lastCx = cx; lastCy = cy
                    multiMaxMove += abs(ddx) + abs(ddy)
                    send(
                        ACTION_SCROLL,
                        clamp(cx / vw), clamp(cy / vh),
                        ddx * SCROLL_GAIN * SCROLL_SIGN,
                        ddy * SCROLL_GAIN * SCROLL_SIGN
                    )
                }
                else -> {}
            }

            MotionEvent.ACTION_POINTER_UP -> {
                if (mode == Mode.MULTI) {
                    val (cx, cy) = centroidExcluding(event, event.actionIndex)
                    lastCx = cx; lastCy = cy
                }
            }

            MotionEvent.ACTION_UP -> {
                when (mode) {
                    Mode.SINGLE ->
                        send(ACTION_UP, nx(event, 0), ny(event, 0), 0f, 0f)
                    Mode.MULTI -> {
                        val elapsed = event.eventTime - multiStartTime
                        if (elapsed <= TAP_TIMEOUT_MS && multiMaxMove <= TAP_MOVE_SLOP) {
                            val ncx = clamp(lastCx / vw)
                            val ncy = clamp(lastCy / vh)
                            send(ACTION_RIGHT_DOWN, ncx, ncy, 0f, 0f)
                            send(ACTION_RIGHT_UP, ncx, ncy, 0f, 0f)
                        }
                    }
                    else -> {}
                }
                mode = Mode.IDLE
            }

            MotionEvent.ACTION_CANCEL -> {
                if (mode == Mode.SINGLE) {
                    send(ACTION_UP, nx(event, 0), ny(event, 0), 0f, 0f)
                }
                mode = Mode.IDLE
            }
        }
        return true
    }

    private fun nx(e: MotionEvent, i: Int) = clamp(e.getX(i) / vw)
    private fun ny(e: MotionEvent, i: Int) = clamp(e.getY(i) / vh)

    private fun clamp(v: Float): Float = when {
        v < 0f -> 0f
        v > 1f -> 1f
        else -> v
    }

    private fun centroid(event: MotionEvent): Pair<Float, Float> {
        var sx = 0f; var sy = 0f
        val n = event.pointerCount
        for (i in 0 until n) { sx += event.getX(i); sy += event.getY(i) }
        return Pair(sx / n, sy / n)
    }

    private fun centroidExcluding(event: MotionEvent, excludeIndex: Int): Pair<Float, Float> {
        var sx = 0f; var sy = 0f; var n = 0
        for (i in 0 until event.pointerCount) {
            if (i == excludeIndex) continue
            sx += event.getX(i); sy += event.getY(i); n++
        }
        if (n == 0) return centroid(event)
        return Pair(sx / n, sy / n)
    }
}

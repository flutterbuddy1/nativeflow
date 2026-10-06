package com.nativeflow

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.util.Base64
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * One floating window rendered from a small declarative node tree with
 * native views, so it keeps working when no Flutter engine exists.
 * Layout + position are persisted and restored with the runtime.
 */
internal class OverlayManager(
    private val context: Context,
    private val store: RuntimeStore,
    private val emit: (type: String, payload: Map<String, Any?>) -> Unit,
) {
    private val wm = context.getSystemService(WindowManager::class.java)
    private val density = context.resources.displayMetrics.density
    private var root: DragFrame? = null
    private var params: WindowManager.LayoutParams? = null
    private var spec: JSONObject? = null

    companion object {
        /** A button with this action id closes the overlay. */
        const val CLOSE_ACTION = "close"
    }

    fun canShow() = Settings.canDrawOverlays(context)

    fun show(window: JSONObject) {
        if (!canShow()) throw SecurityException("Overlay permission not granted")
        hide(byUser = false)
        spec = window
        val p = WindowManager.LayoutParams(
            dim(window, "width"), dim(window, "height"),
            if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = px(window.optDouble("x", 0.0))
            y = px(window.optDouble("y", 200.0))
        }
        val frame = DragFrame(window.optBoolean("draggable", true)).apply {
            addView(render(window.getJSONObject("content")))
        }
        wm.addView(frame, p)
        root = frame
        params = p
        persist()
    }

    fun update(content: JSONObject) {
        val frame = root ?: return
        spec?.put("content", content)
        frame.removeAllViews()
        frame.addView(render(content))
        persist()
    }

    fun move(x: Double, y: Double) = relayout { it.x = px(x); it.y = px(y) }

    fun resize(width: Double?, height: Double?) = relayout {
        it.width = width?.let(::px) ?: WindowManager.LayoutParams.WRAP_CONTENT
        it.height = height?.let(::px) ?: WindowManager.LayoutParams.WRAP_CONTENT
    }

    fun hide(byUser: Boolean) {
        val frame = root ?: run { if (!byUser) store.overlay = null; return }
        try { wm.removeView(frame) } catch (_: IllegalArgumentException) { }
        root = null
        params = null
        spec = null
        store.overlay = null
        if (byUser) emit("nativeflow.overlay.closed", emptyMap())
    }

    fun state(): Map<String, Any?> {
        val p = params ?: return mapOf("visible" to false)
        val v = root!!
        return mapOf(
            "visible" to true, "x" to p.x / density, "y" to p.y / density,
            "width" to v.width / density, "height" to v.height / density,
        )
    }

    /** Re-show the last overlay after process recreation, if still allowed. */
    fun restore() {
        if (root != null) return
        val saved = store.overlay ?: return
        if (canShow()) show(saved) else store.overlay = null
    }

    private fun relayout(change: (WindowManager.LayoutParams) -> Unit) {
        val p = params ?: return
        change(p)
        wm.updateViewLayout(root, p)
        persist()
    }

    private fun persist() {
        val p = params ?: return
        store.overlay = spec?.put("x", p.x / density.toDouble())?.put("y", p.y / density.toDouble())
    }

    private fun render(node: JSONObject): View = when (node.getString("t")) {
        "card" -> LinearLayout(context).apply {
            orientation = if (node.optString("axis") == "horizontal") LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            val pad = px(node.optDouble("padding", 12.0))
            setPadding(pad, pad, pad, pad)
            background = GradientDrawable().apply {
                setColor(colorOr(node, "background", 0xEE202124.toInt()))
                cornerRadius = node.optDouble("cornerRadius", 16.0).toFloat() * density
            }
            elevation = 6 * density
            actionOf(node)?.let { id -> setOnClickListener { emitAction(id) } }
            val children = node.optJSONArray("children")
            for (i in 0 until (children?.length() ?: 0)) addView(render(children!!.getJSONObject(i)))
        }
        "text" -> TextView(context).apply {
            text = node.optString("text")
            textSize = node.optDouble("size", 14.0).toFloat()
            setTextColor(colorOr(node, "color", 0xFFFFFFFF.toInt()))
            if (node.optBoolean("bold")) typeface = Typeface.DEFAULT_BOLD
            maxLines = node.optInt("maxLines", 2)
            ellipsize = TextUtils.TruncateAt.END
        }
        "button" -> TextView(context).apply {
            val id = node.getString("actionId")
            text = node.optString("label")
            setTextColor(0xFFFFFFFF.toInt())
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            val h = px(12.0); val v = px(8.0)
            setPadding(h, v, h, v)
            background = GradientDrawable().apply { setColor(0x33FFFFFF); cornerRadius = 12 * density }
            setOnClickListener { if (id == CLOSE_ACTION) hide(byUser = true) else emitAction(id) }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { setMargins(px(4.0), px(4.0), px(4.0), px(4.0)) }
        }
        "image" -> ImageView(context).apply {
            val bytes = Base64.decode(node.getString("bytes"), Base64.NO_WRAP)
            setImageBitmap(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
            layoutParams = LinearLayout.LayoutParams(px(node.optDouble("width", 40.0)), px(node.optDouble("height", 40.0)))
        }
        "progress" -> ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
            if (node.isNull("value")) isIndeterminate = true
            else { max = 1000; progress = (node.getDouble("value") * 1000).roundToInt() }
            layoutParams = LinearLayout.LayoutParams(px(160.0), LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        else -> View(context)
    }

    private fun emitAction(id: String) = emit("nativeflow.overlay.action", mapOf("actionId" to id))

    private fun actionOf(node: JSONObject) = if (node.isNull("actionId")) null else node.optString("actionId").ifEmpty { null }

    private fun colorOr(node: JSONObject, key: String, fallback: Int) =
        if (node.isNull(key) || !node.has(key)) fallback else node.getLong(key).toInt()

    private fun dim(o: JSONObject, key: String) =
        if (o.isNull(key) || !o.has(key)) WindowManager.LayoutParams.WRAP_CONTENT else px(o.getDouble(key))

    private fun px(dp: Double) = (dp * density).roundToInt()

    /** Container that turns a drag beyond touch slop into window movement. */
    @SuppressLint("ViewConstructor")
    private inner class DragFrame(private val draggable: Boolean) : FrameLayout(context) {
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false

        override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
            if (!draggable) return false
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY
                    startX = params?.x ?: 0; startY = params?.y ?: 0
                    dragging = false
                }
                MotionEvent.ACTION_MOVE ->
                    if (abs(e.rawX - downX) > slop || abs(e.rawY - downY) > slop) dragging = true
            }
            return dragging
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(e: MotionEvent): Boolean {
            if (!draggable) return super.onTouchEvent(e)
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY
                    startX = params?.x ?: 0; startY = params?.y ?: 0
                }
                MotionEvent.ACTION_MOVE -> {
                    val p = params ?: return true
                    p.x = startX + (e.rawX - downX).toInt()
                    p.y = startY + (e.rawY - downY).toInt()
                    wm.updateViewLayout(this, p)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) persist()
                    dragging = false
                }
            }
            return true
        }
    }
}

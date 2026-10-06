package com.nativeflow

import org.json.JSONObject
import java.io.File

/**
 * Small persistent log of runtime events awaiting delivery to Dart.
 *
 * Append-only JSON-lines file, replayed on load and compacted when it grows:
 *   {"op":"add", id, type, ts, adapterId, payload}
 *   {"op":"ack", "upTo": id}          cumulative acknowledgement
 *   {"op":"try", "id": id}            one redelivery attempt
 *   {"op":"meta", "nextId", "lastAck"} written at compaction
 *
 * A torn last line (crash mid-write) is skipped on load. Not a database: it
 * holds at most [maxEvents] unacknowledged events for at most [maxAgeMs].
 */
class EventStore(
    private val file: File,
    private val maxEvents: Int = 1000,
    private val maxAgeMs: Long = 7L * 24 * 60 * 60 * 1000,
    private val maxAttempts: Int = 10,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    data class Event(
        val id: Long,
        val type: String,
        val ts: Long,
        val adapterId: String?,
        val payload: JSONObject,
        var attempts: Int = 0,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "id" to id, "type" to type, "ts" to ts, "adapterId" to adapterId,
            "payload" to Json.toMap(payload),
        )
    }

    private val events = LinkedHashMap<Long, Event>()
    private var nextId = 1L
    private var lines = 0

    var lastAck = 0L
        private set

    init {
        load()
    }

    @Synchronized
    fun append(type: String, adapterId: String?, payload: JSONObject): Event {
        val event = Event(nextId++, type, clock(), adapterId, payload)
        events[event.id] = event
        write(
            JSONObject().put("op", "add").put("id", event.id).put("type", type)
                .put("ts", event.ts).put("adapterId", adapterId ?: JSONObject.NULL)
                .put("payload", payload)
        )
        prune()
        return event
    }

    /**
     * Unacknowledged events after [after], oldest first. Each returned event
     * counts as a delivery attempt; events past [maxAttempts] are dropped so
     * one poison event cannot block the queue forever.
     */
    @Synchronized
    fun pending(after: Long, limit: Int): List<Event> {
        prune()
        val result = events.values.filter { it.id > after }.take(limit)
        for (e in result) {
            e.attempts++
            write(JSONObject().put("op", "try").put("id", e.id))
        }
        val dead = result.filter { it.attempts > maxAttempts }
        dead.forEach { events.remove(it.id) }
        if (dead.isNotEmpty()) NFLog.w("Dropped ${dead.size} undeliverable events")
        return result - dead.toSet()
    }

    @Synchronized
    fun ack(upTo: Long) {
        if (upTo <= lastAck) return
        lastAck = minOf(upTo, nextId - 1)
        events.keys.removeAll { it <= lastAck }
        write(JSONObject().put("op", "ack").put("upTo", lastAck))
        compactIfNeeded()
    }

    @Synchronized
    fun size(): Int = events.size

    private fun prune() {
        val cutoff = clock() - maxAgeMs
        events.values.removeAll { it.ts < cutoff }
        while (events.size > maxEvents) events.remove(events.keys.first())
        compactIfNeeded()
    }

    private fun compactIfNeeded() {
        if (lines < 64 || lines < events.size * 2) return
        val tmp = File(file.path + ".tmp")
        tmp.bufferedWriter().use { w ->
            w.appendLine(
                JSONObject().put("op", "meta").put("nextId", nextId).put("lastAck", lastAck).toString()
            )
            for (e in events.values) {
                w.appendLine(
                    JSONObject().put("op", "add").put("id", e.id).put("type", e.type).put("ts", e.ts)
                        .put("adapterId", e.adapterId ?: JSONObject.NULL).put("payload", e.payload)
                        .put("attempts", e.attempts).toString()
                )
            }
        }
        if (!tmp.renameTo(file)) {
            NFLog.e("Event store compaction failed")
            tmp.delete()
            return
        }
        lines = events.size + 1
    }

    // ponytail: no fsync per append; survives process death, not power loss.
    private fun write(line: JSONObject) {
        file.parentFile?.mkdirs()
        file.appendText(line.toString() + "\n")
        lines++
    }

    private fun load() {
        if (!file.exists()) return
        file.forEachLine { raw ->
            lines++
            val o = try {
                JSONObject(raw)
            } catch (_: Exception) {
                return@forEachLine // torn write
            }
            when (o.optString("op")) {
                "meta" -> {
                    nextId = maxOf(nextId, o.optLong("nextId", 1))
                    lastAck = maxOf(lastAck, o.optLong("lastAck"))
                }
                "add" -> {
                    val id = o.getLong("id")
                    nextId = maxOf(nextId, id + 1)
                    if (id > lastAck) {
                        events[id] = Event(
                            id, o.getString("type"), o.getLong("ts"),
                            if (o.isNull("adapterId")) null else o.getString("adapterId"),
                            o.optJSONObject("payload") ?: JSONObject(), o.optInt("attempts"),
                        )
                    }
                }
                "ack" -> {
                    lastAck = maxOf(lastAck, o.getLong("upTo"))
                    events.keys.removeAll { it <= lastAck }
                }
                "try" -> events[o.getLong("id")]?.let { it.attempts++ }
            }
        }
        // Terminate a torn last line so the next append starts cleanly.
        if (file.length() > 0 && file.readBytes().last() != '\n'.code.toByte()) file.appendText("\n")
    }
}

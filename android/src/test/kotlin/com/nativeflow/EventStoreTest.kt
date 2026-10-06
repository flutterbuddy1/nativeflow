package com.nativeflow

import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class EventStoreTest {
    private val dir = Files.createTempDirectory("nf").toFile()
    private val file = File(dir, "events.jsonl")
    private var now = 1_000_000L

    private fun store(maxEvents: Int = 1000, maxAttempts: Int = 10) =
        EventStore(file, maxEvents = maxEvents, maxAgeMs = 10_000, maxAttempts = maxAttempts, clock = { now })

    @AfterTest
    fun cleanup() {
        dir.deleteRecursively()
    }

    @Test
    fun `ids are monotonic and survive reload`() {
        val s = store()
        val a = s.append("a", null, JSONObject().put("k", 1))
        val b = s.append("b", "driver", JSONObject())
        assertEquals(listOf(1L, 2L), listOf(a.id, b.id))

        val reloaded = store()
        val pending = reloaded.pending(0, 10)
        assertEquals(listOf("a", "b"), pending.map { it.type })
        assertEquals("driver", pending[1].adapterId)
        assertEquals(1, pending[0].payload.getInt("k"))
        assertEquals(3L, reloaded.append("c", null, JSONObject()).id)
    }

    @Test
    fun `ack is cumulative and persistent - recovery resumes after last ack`() {
        val s = store()
        repeat(5) { s.append("e$it", null, JSONObject()) } // ids 1..5
        s.ack(3)
        val reloaded = store()
        assertEquals(3L, reloaded.lastAck)
        assertEquals(listOf(4L, 5L), reloaded.pending(reloaded.lastAck, 10).map { it.id })
        reloaded.ack(2) // stale ack is ignored
        assertEquals(3L, reloaded.lastAck)
    }

    @Test
    fun `retention drops old and excess events`() {
        val s = store(maxEvents = 3)
        repeat(5) { s.append("e$it", null, JSONObject()) }
        assertEquals(listOf(3L, 4L, 5L), s.pending(0, 10).map { it.id })
        now += 20_000 // older than maxAge
        s.append("fresh", null, JSONObject())
        assertEquals(listOf("fresh"), s.pending(0, 10).map { it.type })
    }

    @Test
    fun `poison events are dropped after max attempts`() {
        val s = store(maxAttempts = 2)
        s.append("poison", null, JSONObject())
        assertEquals(1, s.pending(0, 10).size)
        assertEquals(1, store(maxAttempts = 2).pending(0, 10).size) // attempts persisted: 2
        assertEquals(0, store(maxAttempts = 2).pending(0, 10).size) // 3rd attempt: dropped
    }

    @Test
    fun `torn trailing line is ignored`() {
        val s = store()
        s.append("ok", null, JSONObject())
        file.appendText("{\"op\":\"add\",\"id\":2,\"ty") // crash mid-write
        val reloaded = store()
        assertEquals(listOf("ok"), reloaded.pending(0, 10).map { it.type })
        assertEquals(2L, reloaded.append("next", null, JSONObject()).id)
        assertEquals(listOf("ok", "next"), store().pending(0, 10).map { it.type })
    }

    @Test
    fun `compaction bounds the file and keeps ids monotonic`() {
        val s = store()
        repeat(500) {
            val e = s.append("e", null, JSONObject())
            s.ack(e.id)
        }
        assertTrue(file.readLines().size < 100, "file was not compacted: ${file.readLines().size} lines")
        val reloaded = store()
        assertEquals(500L, reloaded.lastAck)
        assertEquals(501L, reloaded.append("after", null, JSONObject()).id)
    }
}

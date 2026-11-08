package com.example.pace.services.focus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class JsonConversionTest {

    private val persisted = """
        {"sessionId":"1","blockedApps":["com.google.android.youtube","com.whatsapp"],
         "blockedWebsites":[{"url":"x.com","isActive":true}],
         "interruptions":[{"appPackage":"com.android.chrome","wasBlocked":true}],
         "shortFormBlocks":{},"notes":null,"plannedDuration":25,"shortFormBlocked":true}
    """.trimIndent()

    @Test
    fun nestedArrayBecomesRealListSoBlockedAppsSurviveRestore() {
        val map = JsonConversion.toMap(org.json.JSONObject(persisted))
        val blocked = map["blockedApps"] as? List<*>
        assertEquals(listOf("com.google.android.youtube", "com.whatsapp"), blocked)
    }

    @Test
    fun nestedObjectsInsideArraysBecomeMaps() {
        val map = JsonConversion.toMap(org.json.JSONObject(persisted))
        val interruptions = map["interruptions"] as List<*>
        val first = interruptions[0] as Map<*, *>
        assertEquals("com.android.chrome", first["appPackage"])
        assertEquals(true, first["wasBlocked"])
    }

    @Test
    fun emptyObjectBecomesEmptyMapAndJsonNullIsDropped() {
        val map = JsonConversion.toMap(org.json.JSONObject(persisted))
        assertEquals(emptyMap<String, Any>(), map["shortFormBlocks"])
        assertFalse(map.containsKey("notes"))
    }

    @Test
    fun primitivesKeepTheirValues() {
        val map = JsonConversion.toMap(org.json.JSONObject(persisted))
        assertEquals(25, map["plannedDuration"])
        assertEquals(true, map["shortFormBlocked"])
    }
}

package com.example.pace.services.focus

import org.json.JSONArray
import org.json.JSONObject

/**
 * Recursive JSON -> Kotlin conversion. The old shallow version left nested arrays/objects as
 * JSONArray/JSONObject, so a restored focus session lost `blockedApps` (read as empty list) and
 * enforcement did nothing after the app process was killed and restarted.
 */
object JsonConversion {

    fun toMap(json: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            convert(json.get(key))?.let { map[key] = it }
        }
        return map
    }

    fun toList(array: JSONArray): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until array.length()) {
            convert(array.get(i))?.let { list.add(it) }
        }
        return list
    }

    private fun convert(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> toMap(value)
        is JSONArray -> toList(value)
        else -> value
    }
}

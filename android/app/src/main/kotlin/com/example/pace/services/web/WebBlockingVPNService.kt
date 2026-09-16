package com.example.pace.services.web

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import com.example.pace.R
import com.example.pace.services.focus.FocusSessionManager
import com.example.pace.services.overlay.SimpleBlockOverlay
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetAddress
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap

/**
 * WebBlockingVPNService - Network-level website blocking using VPN
 * Provides bulletproof website blocking at the kernel level
 */
class WebBlockingVPNService : VpnService() {

    companion object {
        private const val TAG = "WebBlockingVPN"
        private const val NOTIFICATION_ID = 2001
        private const val CHANNEL_ID = "web_blocking_vpn"

        // VPN Actions
        const val ACTION_START_VPN = "START_VPN"
        const val ACTION_STOP_VPN = "STOP_VPN"
        const val ACTION_UPDATE_BLOCKS = "UPDATE_BLOCKS"

        // Critical domains that should never be blocked
        private val CRITICAL_DOMAINS = setOf(
            "googleapis.com",
            "gstatic.com",
            "firebase.googleapis.com",
            "firestore.googleapis.com",
            "firebaseapp.com",
            "google.com",
            "android.com",
            "cloudflare.com",
            "amazonaws.com",
            "cdn.jsdelivr.net",
            "github.com",
            "githubusercontent.com"
        )

        /**
         * Static methods for external control
         */
        @RequiresApi(Build.VERSION_CODES.O)
        fun startVPN(context: Context, blockedWebsites: List<Map<String, Any>>): Boolean {
            return try {
                val intent = Intent(context, WebBlockingVPNService::class. java).apply {
                    action = ACTION_START_VPN
                    putExtra("blocked_websites", JSONArray(blockedWebsites).toString())
                }
                context.startForegroundService(intent)
                true
            } catch (e: Exception) {
                Log.e(TAG, "Error starting VPN", e)
                false
            }
        }

        fun stopVPN(context: Context): Boolean {
            return try {
                val intent = Intent(context, WebBlockingVPNService::class.java).apply {
                    action = ACTION_STOP_VPN
                }
                context.startService(intent)
                true
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping VPN", e)
                false
            }
        }

        fun updateBlocks(context: Context, blockedWebsites: List<Map<String, Any>>): Boolean {
            return try {
                val intent = Intent(context, WebBlockingVPNService:: class.java).apply {
                    action = ACTION_UPDATE_BLOCKS
                    putExtra("blocked_websites", JSONArray(blockedWebsites).toString())
                }
                context. startService(intent)
                true
            } catch (e: Exception) {
                Log.e(TAG, "Error updating blocks", e)
                false
            }
        }

        fun prepare(context: Context): Intent? {
            return VpnService.prepare(context)
        }
    }

    // Core components
    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var sessionManager: FocusSessionManager

    // Blocking configuration
    private val blockedDomains = ConcurrentHashMap<String, BlockedWebsite>()
    private var totalBlockedRequests = 0

    // Network handling
    private var inputStream: FileInputStream? = null
    private var outputStream: FileOutputStream? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "WebBlockingVPNService created")

        sessionManager = FocusSessionManager.getInstance(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent?.action}")

        when (intent?.action) {
            ACTION_START_VPN -> {
                val blockedWebsitesJson = intent.getStringExtra("blocked_websites")
                if (! blockedWebsitesJson.isNullOrEmpty()) {
                    updateBlockedDomains(blockedWebsitesJson)
                }
                startVPN()
            }
            ACTION_STOP_VPN -> {
                stopVPN()
            }
            ACTION_UPDATE_BLOCKS -> {
                val blockedWebsitesJson = intent. getStringExtra("blocked_websites")
                if (!blockedWebsitesJson. isNullOrEmpty()) {
                    updateBlockedDomains(blockedWebsitesJson)
                }
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "WebBlockingVPNService destroyed")
        stopVPN()
        scope.cancel()
        super.onDestroy()
    }

    // ====================
    // VPN MANAGEMENT
    // ====================

    private fun startVPN() {
        if (isRunning) {
            Log.w(TAG, "VPN already running")
            return
        }

        try {
            Log. d(TAG, "Starting VPN service")

            val builder = Builder().apply {
                // Set VPN parameters
                setMtu(1500)
                addAddress("10.0.0.1", 32)
                addRoute("0.0.0.0", 0)

                // DNS servers
                addDnsServer("8.8.8.8")
                addDnsServer("8.8.4.4")

                // Set session name
                setSession("LockIn Web Blocker")

                // Block all traffic by default, then allow what we want
                setBlocking(true)

                // Configure allowed/disallowed apps
                try {
                    addDisallowedApplication(packageName) // Don't route our own traffic
                } catch (e: Exception) {
                    Log.w(TAG, "Could not exclude own package from VPN")
                }
            }

            vpnInterface = builder. establish()

            if (vpnInterface != null) {
                isRunning = true
                startForegroundNotification()
                setupNetworkStreams()
                startPacketProcessing()

                Log.d(TAG, "VPN started successfully")
            } else {
                Log.e(TAG, "Failed to establish VPN interface")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error starting VPN", e)
            stopVPN()
        }
    }

    private fun stopVPN() {
        try {
            Log.d(TAG, "Stopping VPN service")

            isRunning = false
            scope.cancel()

            // Close streams
            inputStream?.close()
            outputStream?.close()
            inputStream = null
            outputStream = null

            // Close VPN interface
            vpnInterface?.close()
            vpnInterface = null

            // Clear blocked domains
            blockedDomains.clear()

            stopForeground(true)
            stopSelf()

            Log. d(TAG, "VPN stopped successfully")

        } catch (e: Exception) {
            Log.e(TAG, "Error stopping VPN", e)
        }
    }

    private fun setupNetworkStreams() {
        try {
            val fd = vpnInterface?.fileDescriptor
            if (fd != null) {
                inputStream = FileInputStream(fd)
                outputStream = FileOutputStream(fd)
                Log.d(TAG, "Network streams configured")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting up network streams", e)
        }
    }

    // ====================
    // PACKET PROCESSING
    // ====================

    private fun startPacketProcessing() {
        scope.launch {
            try {
                Log. d(TAG, "Starting packet processing")
                val packetBuffer = ByteBuffer.allocate(32767)

                while (isRunning && inputStream != null) {
                    try {
                        packetBuffer.clear()

                        val bytesRead = inputStream!! .read(packetBuffer. array())
                        if (bytesRead > 0) {
                            packetBuffer.limit(bytesRead)

                            val processedPacket = processPacket(packetBuffer)
                            if (processedPacket != null && outputStream != null) {
                                outputStream!!.write(processedPacket. array(), 0, processedPacket.limit())
                                outputStream!!.flush()
                            }
                        }

                    } catch (e:  ErrnoException) {
                        if (e.errno == OsConstants.EAGAIN || e.errno == OsConstants.CAP_BLOCK_SUSPEND) {
                            delay(1) // No data available, brief pause
                            continue
                        } else {
                            Log.e(TAG, "Network error:  ${e.message}")
                            break
                        }
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "Error in packet processing", e)
            } finally {
                if (isRunning) {
                    Log.w(TAG, "Packet processing stopped unexpectedly, restarting VPN")
                    restartVPN()
                }
            }
        }
    }

    private fun processPacket(packet: ByteBuffer): ByteBuffer? {
        try {
            if (packet.remaining() < 20) return packet // Too small for IP header

            // Parse IP header
            val ipHeaderLength = (packet.get(0).toInt() and 0x0F) * 4
            val protocol = packet.get(9).toInt() and 0xFF
            val totalLength = ((packet.get(2).toInt() and 0xFF) shl 8) or (packet.get(3).toInt() and 0xFF)

            // Only process IPv4 TCP and UDP
            if (ipHeaderLength < 20 || protocol !in listOf(6, 17)) {
                return packet
            }

            // Extract destination IP
            val destIpBytes = ByteArray(4)
            packet.position(16)
            packet.get(destIpBytes)
            packet.position(0)

            val destIp = InetAddress.getByAddress(destIpBytes).hostAddress

            // Check if IP should be blocked (basic IP blocking)
            if (shouldBlockIP(destIp)) {
                logBlockedRequest("IP: $destIp")
                return null // Drop packet
            }

            // Process DNS queries (UDP port 53)
            if (protocol == 17 && packet.remaining() >= ipHeaderLength + 8) {
                val destPort = ((packet.get(ipHeaderLength + 2).toInt() and 0xFF) shl 8) or
                        (packet. get(ipHeaderLength + 3).toInt() and 0xFF)

                if (destPort == 53) {
                    return processDNSQuery(packet, ipHeaderLength)
                }
            }

            return packet // Forward packet

        } catch (e: Exception) {
            Log.e(TAG, "Error processing packet", e)
            return packet // Forward on error
        }
    }

    private fun processDNSQuery(packet: ByteBuffer, ipHeaderLength: Int): ByteBuffer? {
        try {
            val udpHeaderLength = 8
            val dnsOffset = ipHeaderLength + udpHeaderLength

            if (packet.remaining() < dnsOffset + 12) return packet // Too small for DNS

            // Extract domain name from DNS query
            val domainName = extractDomainFromDNSQuery(packet, dnsOffset)

            if (domainName != null) {
                Log.v(TAG, "DNS query for: $domainName")

                if (shouldBlockDomain(domainName)) {
                    logBlockedRequest(domainName)

                    // Show website blocked overlay
                    showWebsiteBlockedOverlay(domainName)

                    // Return DNS response pointing to localhost
                    return createDNSBlockResponse(packet, dnsOffset, domainName)
                }
            }

            return packet // Forward DNS query

        } catch (e:  Exception) {
            Log.e(TAG, "Error processing DNS query", e)
            return packet
        }
    }

    private fun extractDomainFromDNSQuery(packet: ByteBuffer, dnsOffset: Int): String? {
        try {
            packet.position(dnsOffset + 12) // Skip DNS header

            val domain = StringBuilder()
            var length = packet.get().toInt() and 0xFF

            while (length > 0 && packet.hasRemaining()) {
                if (domain.isNotEmpty()) domain.append('.')

                val labelBytes = ByteArray(length)
                packet. get(labelBytes)
                domain.append(String(labelBytes))

                if (!packet.hasRemaining()) break
                length = packet.get().toInt() and 0xFF
            }

            packet.position(0) // Reset position
            return if (domain.isNotEmpty()) domain.toString().lowercase() else null

        } catch (e: Exception) {
            Log.e(TAG, "Error extracting domain from DNS query", e)
            packet.position(0)
            return null
        }
    }

    private fun createDNSBlockResponse(originalPacket: ByteBuffer, dnsOffset: Int, domain: String): ByteBuffer {
        try {
            val response = ByteBuffer. allocate(originalPacket.capacity())

            // Copy IP and UDP headers
            originalPacket.position(0)
            val headers = ByteArray(dnsOffset)
            originalPacket.get(headers)
            response.put(headers)

            // Swap source and destination IPs in IP header
            val srcIp = ByteArray(4)
            val destIp = ByteArray(4)
            response.position(12)
            response. get(srcIp)
            response. get(destIp)
            response.position(12)
            response.put(destIp) // Swap dest to source
            response.put(srcIp)   // Swap source to dest

            // Update UDP length and checksum (simplified)
            response.position(dnsOffset - 8 + 4) // UDP length field
            response.putShort((12 + domain.split('.').size + 1 + 4 + 16).toShort()) // New UDP length
            response.putShort(0) // Clear checksum

            // Create DNS response
            response.position(dnsOffset)

            // DNS Header
            response.putShort(originalPacket.getShort(dnsOffset)) // Transaction ID
            response. putShort(0x8180.toShort()) // Flags: Response, no error
            response.putShort(1) // Questions: 1
            response.putShort(1) // Answers: 1
            response.putShort(0) // Authority RRs: 0
            response.putShort(0) // Additional RRs: 0

            // Copy original question
            originalPacket.position(dnsOffset + 12)
            while (originalPacket. hasRemaining()) {
                val b = originalPacket.get()
                response.put(b)
                if (b == 0.toByte()) break // End of domain name
            }

            if (originalPacket. remaining() >= 4) {
                response.put(originalPacket.get()) // QTYPE high byte
                response.put(originalPacket.get()) // QTYPE low byte
                response.put(originalPacket.get()) // QCLASS high byte
                response.put(originalPacket.get()) // QCLASS low byte
            }

            // Add answer record pointing to 127.0.0.1
            response.putShort(0xC00C.toShort()) // Name: pointer to question
            response.putShort(1) // Type: A
            response.putShort(1) // Class: IN
            response.putInt(300)  // TTL: 5 minutes
            response.putShort(4)  // Data length: 4 bytes
            response.put(127.toByte()) // 127.0.0.1
            response.put(0.toByte())
            response.put(0.toByte())
            response.put(1.toByte())

            // Update IP total length
            val newLength = response.position()
            response.position(2)
            response. putShort(newLength.toShort())

            response.flip()
            return response

        } catch (e: Exception) {
            Log.e(TAG, "Error creating DNS block response", e)
            return originalPacket
        }
    }

    // ====================
    // BLOCKING LOGIC
    // ====================

    private fun shouldBlockDomain(domain: String): Boolean {
        val normalizedDomain = domain.lowercase()

        // Never block critical domains
        if (isCriticalDomain(normalizedDomain)) {
            return false
        }

        // Check exact matches
        if (blockedDomains. containsKey(normalizedDomain)) {
            val config = blockedDomains[normalizedDomain]
            return config?.isActive == true
        }

        // Check pattern and subdomain matches
        for ((blocked, config) in blockedDomains) {
            if (! config.isActive) continue

            when (config.blockType) {
                "exact" -> {
                    if (normalizedDomain == blocked) return true
                }
                "pattern" -> {
                    val pattern = config.pattern
                    if (pattern != null && normalizedDomain.matches(Regex(pattern))) return true
                }
                "keyword" -> {
                    if (normalizedDomain.contains(blocked)) return true
                }
                "subdomain" -> {
                    if (normalizedDomain == blocked || normalizedDomain.endsWith(".$blocked")) {
                        return true
                    }
                }
                else -> {
                    // Default: subdomain matching
                    if (normalizedDomain == blocked || normalizedDomain.endsWith(".$blocked")) {
                        return true
                    }
                }
            }
        }

        return false
    }

    private fun shouldBlockIP(ip: String?): Boolean {
        if (ip == null) return false

        // Don't block local/private IPs
        if (ip.startsWith("127.") || ip.startsWith("10.") ||
            ip.startsWith("192.168.") || ip.startsWith("172.")) {
            return false
        }

        // Could maintain an IP blocklist here for known problematic IPs
        return false
    }

    private fun isCriticalDomain(domain: String): Boolean {
        return CRITICAL_DOMAINS. any { criticalDomain ->
            domain == criticalDomain || domain.endsWith(".$criticalDomain")
        }
    }

    // ====================
    // UI INTEGRATION
    // ====================

    private fun showWebsiteBlockedOverlay(domain: String) {
        try {
            val reason = if (sessionManager.isSessionActive()) {
                "This website is blocked during your focus session"
            } else {
                "This website is blocked"
            }

            SimpleBlockOverlay.showWebsite(
                context = applicationContext,
                url = "https://$domain",
                reason = reason
            ) {
                Log.d(TAG, "✅ Website blocked overlay dismissed for $domain")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing website blocked overlay", e)
        }
    }

    private fun logBlockedRequest(domain: String) {
        try {
            totalBlockedRequests++

            // Report to session manager if session is active
            if (sessionManager.isSessionActive()) {
                sessionManager.recordInterruption(
                    packageName = "web.browser",
                    appName = "Website: $domain",
                    type = "website_blocked",
                    wasBlocked = true
                )
            }

            // Update notification
            updateNotification()

            Log.d(TAG, "Blocked website request: $domain (total: $totalBlockedRequests)")

        } catch (e: Exception) {
            Log.e(TAG, "Error logging blocked request", e)
        }
    }

    // ====================
    // CONFIGURATION MANAGEMENT
    // ====================

    private fun updateBlockedDomains(json: String) {
        try {
            val jsonArray = JSONArray(json)
            blockedDomains. clear()

            for (i in 0 until jsonArray.length()) {
                val item = jsonArray.getJSONObject(i)
                val website = BlockedWebsite(
                    domain = item.getString("domain").lowercase(),
                    blockType = item. optString("blockType", "subdomain"),
                    pattern = item.optString("pattern", null),
                    isActive = item.optBoolean("isActive", true)
                )
                blockedDomains[website.domain] = website
            }

            Log.d(TAG, "Updated blocked domains: ${blockedDomains.size} domains")

            // Update notification
            if (isRunning) {
                updateNotification()
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error updating blocked domains", e)
        }
    }

    // ====================
    // NOTIFICATIONS
    // ====================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                CHANNEL_ID,
                "Website Blocking VPN",
                android.app.NotificationManager. IMPORTANCE_LOW
            ).apply {
                description = "VPN service for blocking websites during focus sessions"
                setShowBadge(false)
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
            }

            val notificationManager = getSystemService(android.app.NotificationManager:: class.java)
            notificationManager. createNotificationChannel(channel)
        }
    }

    private fun startForegroundNotification() {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Website Blocking Active")
            .setContentText("Blocking ${blockedDomains.size} websites • ${totalBlockedRequests} blocked")
            .setSmallIcon(R.drawable.ic_shield)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setSilent(true)
            .setShowWhen(false)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun updateNotification() {
        if (isRunning) {
            startForegroundNotification()
        }
    }

    // ====================
    // UTILITY METHODS
    // ====================

    private fun getFocusTimeMinutes(): Int {
        return try {
            val sessionStatus = sessionManager.getCurrentSessionStatus()
            (sessionStatus?.get("elapsedMinutes") as? Int) ?: 0
        } catch (e: Exception) {
            0
        }
    }

    private fun restartVPN() {
        scope.launch {
            try {
                delay(2000) // Wait 2 seconds
                if (sessionManager.isSessionActive()) {
                    Log.d(TAG, "Restarting VPN service")
                    stopVPN()
                    delay(1000)
                    startVPN()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error restarting VPN", e)
            }
        }
    }

    // ====================
    // DATA CLASSES
    // ====================

    data class BlockedWebsite(
        val domain: String,
        val blockType: String = "subdomain", // "exact", "pattern", "keyword", "subdomain"
        val pattern: String? = null,
        val isActive:  Boolean = true
    )
}
package com.example.pace.utils

import android.content. Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object AppUtils {

    private const val TAG = "AppUtils"

    /**
     * GET ALL INSTALLED APPS
     */
    suspend fun getInstalledApps(context: Context): List<Map<String, Any>> {
        return withContext(Dispatchers.IO) {
            try {
                val packageManager = context.packageManager
                // Use 0 or GET_META_DATA carefully; 0 is faster
                val packages = packageManager.getInstalledPackages(PackageManager.GET_META_DATA)
                val apps = mutableListOf<Map<String, Any>>()

                packages.forEach { packageInfo ->
                    val applicationInfo = packageInfo.applicationInfo ?: return@forEach

                    // 1. IMPROVED FILTERING
                    val isSys = isSystemApp(applicationInfo)
                    val isInteresting = isUserInterestingSystemApp(packageInfo.packageName)

                    // Only skip if it's a system app AND NOT interesting
                    if (isSys && !isInteresting) {
                        return@forEach
                    }

                    val appName = packageManager.getApplicationLabel(applicationInfo).toString()

                    apps.add(mapOf(
                        "appName" to appName,
                        "packageName" to packageInfo.packageName,
                        "isSystemApp" to isSys,
                        "category" to getAppCategory(applicationInfo),
                        "canLaunch" to canLaunchApp(packageManager, packageInfo.packageName)
                    ))
                }

                // 2. RETURN THE SORTED LIST
                apps.sortedBy { (it["appName"] as String).lowercase() }

            } catch (e: Exception) {
                Log.e(TAG, "Error getting installed apps", e)
                emptyList()
            }
        }
    }

    /**
     * Check if an app is a system app
     */
    private fun isSystemApp(applicationInfo: ApplicationInfo): Boolean {
        return (applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                (applicationInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
    }

    /**
     * Check if a system app is interesting to users (like Chrome, Play Store, etc.)
     */
    private fun isUserInterestingSystemApp(packageName: String): Boolean {
        val interestingSystemApps = setOf(
            "com.android.chrome",
            "com.google.android.youtube",
            "com.google.android.youtube.tv", // TV version
            "com.google.android.apps.youtube.music", // YouTube Music
            "com. android.vending", // Play Store
            "com.google.android. gms",
            "com. google.android.apps.maps",
            "com.google.android.calendar",
            "com.google. android.contacts",
            "com.android.gallery3d",
            "com.android.camera",
            "com.android.calculator2"
        )

        return packageName in interestingSystemApps || packageName.contains("youtube")
    }

    /**
     * Get app category
     */
    private fun getAppCategory(applicationInfo:  ApplicationInfo): String {
        return if (android.os.Build. VERSION.SDK_INT >= android. os.Build.VERSION_CODES.O) {
            when (applicationInfo.category) {
                ApplicationInfo.CATEGORY_GAME -> "Games"
                ApplicationInfo.CATEGORY_SOCIAL -> "Social"
                ApplicationInfo. CATEGORY_NEWS -> "News"
                ApplicationInfo.CATEGORY_MAPS -> "Maps"
                ApplicationInfo.CATEGORY_PRODUCTIVITY -> "Productivity"
                ApplicationInfo.CATEGORY_IMAGE -> "Photography"
                ApplicationInfo.CATEGORY_VIDEO -> "Video"
                ApplicationInfo.CATEGORY_AUDIO -> "Music & Audio"
                else -> getCategoryFromPackageName(applicationInfo.packageName)
            }
        } else {
            getCategoryFromPackageName(applicationInfo.packageName)
        }
    }

    /**
     * Guess category from package name
     */
    private fun getCategoryFromPackageName(packageName: String): String {
        return when {
            packageName.contains("game") -> "Games"
            packageName.contains("social") ||
                    packageName.contains("facebook") ||
                    packageName.contains("instagram") ||
                    packageName.contains("twitter") ||
                    packageName. contains("whatsapp") -> "Social"
            packageName.contains("news") ||
                    packageName.contains("reddit") -> "News"
            packageName.contains("music") ||
                    packageName.contains("spotify") ||
                    packageName.contains("audio") -> "Music & Audio"
            packageName.contains("video") ||
                    packageName.contains("youtube") ||
                    packageName.contains("netflix") -> "Video"
            packageName.contains("photo") ||
                    packageName.contains("camera") ||
                    packageName.contains("gallery") -> "Photography"
            packageName.contains("productivity") ||
                    packageName.contains("office") ||
                    packageName. contains("document") -> "Productivity"
            packageName.contains("shopping") ||
                    packageName.contains("amazon") -> "Shopping"
            packageName.contains("travel") ||
                    packageName.contains("maps") -> "Travel & Local"
            packageName. contains("fitness") ||
                    packageName.contains("health") -> "Health & Fitness"
            packageName.contains("education") ||
                    packageName.contains("learning") -> "Education"
            else -> "Other"
        }
    }

    /**
     * Check if an app can be launched
     */
    private fun canLaunchApp(packageManager:  PackageManager, packageName: String): Boolean {
        return try {
            val intent = packageManager. getLaunchIntentForPackage(packageName)
            intent != null
        } catch (e:  Exception) {
            false
        }
    }

    /**
     * Check if an app has a launcher activity
     */
    fun hasLauncherActivity(packageManager: PackageManager, packageName: String): Boolean {
        return try {
            val intent = android.content.Intent(android.content.Intent.ACTION_MAIN).apply {
                addCategory(android.content.Intent.CATEGORY_LAUNCHER)
                setPackage(packageName)
            }
            val activities = packageManager.queryIntentActivities(intent, 0)
            activities.isNotEmpty()
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Get app icon as byte array (for Flutter)
     */
    fun getAppIcon(context: Context, packageName: String): ByteArray? {
        return try {
            val packageManager = context.packageManager
            val appIcon = packageManager.getApplicationIcon(packageName)

            // Convert Drawable to Bitmap
            val bitmap = appIcon.toBitmap()

            // Compress to PNG Byte Array
            val stream = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray() // Return raw bytes directly
        } catch (e: Exception) {
            Log.e(TAG, "Error getting app icon for $packageName", e)
            null
        }
    }

    /**
     * Get app name from package name
     */
    fun getAppName(context: Context, packageName: String): String {
        return try {
            val packageManager = context.packageManager
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting app name for $packageName", e)
            packageName
        }
    }

    /**
     * Check if an app is installed
     */
    fun isAppInstalled(context: Context, packageName: String): Boolean {
        return try {
            context.packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    /**
     * Launch an app by package name
     */
    fun launchApp(context: Context, packageName: String): Boolean {
        return try {
            val intent = context.packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(android.content. Intent.FLAG_ACTIVITY_NEW_TASK)
                context. startActivity(intent)
                true
            } else {
                Log.w(TAG, "No launch intent found for $packageName")
                false
            }
        } catch (e:  Exception) {
            Log.e(TAG, "Error launching app $packageName", e)
            false
        }
    }

    fun getAppInfo(context: Context, packageName: String): Map<String, Any>? {
        return try {
            val packageManager = context. packageManager
            val packageInfo = packageManager. getPackageInfo(packageName, PackageManager.GET_META_DATA)
            val applicationInfo: ApplicationInfo? = packageInfo.applicationInfo

            if(applicationInfo == null) {
                Log.w(TAG, "ApplicationInfo is null for $packageName")
                return null
            }

            mapOf(
                "appName" to packageManager.getApplicationLabel(applicationInfo).toString(),
                "packageName" to packageName,
                "versionName" to (packageInfo.versionName ?: "Unknown"),
                "versionCode" to packageInfo.versionCode,
                "installTime" to packageInfo.firstInstallTime,
                "updateTime" to packageInfo.lastUpdateTime,
                "isSystemApp" to isSystemApp(applicationInfo),
                "category" to getAppCategory(applicationInfo),
                "targetSdk" to applicationInfo.targetSdkVersion,
                "minSdk" to
                        applicationInfo.minSdkVersion,
                "dataDir" to applicationInfo.dataDir,
                "canLaunch" to canLaunchApp(packageManager, packageName),
                "hasLauncherActivity" to hasLauncherActivity(packageManager, packageName)
            )
        } catch (e:  Exception) {
            Log.e(TAG, "Error getting app info for $packageName", e)
            null
        }
    }
}
package com.adwebsolutions.multiphone_player

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQ_PERMISSIONS = 4101
        private const val REQ_CAPTURE_CONSENT = 4102
        private const val REQ_HOTSPOT_PERMISSION = 4103

        init {
            // The Rust audio engine. Dart opens the same library through dart:ffi; loading it here as well
            // lets us hand it the Android Context before any audio code runs.
            System.loadLibrary("mpsp_ffi")
        }
    }

    /** Implemented in core/mpsp-ffi (JNI): gives the engine's audio backend (Oboe) the app Context. */
    private external fun nativeInit(context: android.content.Context)

    private var wifiLock: WifiManager.WifiLock? = null

    // Hotspot (host) and join-Wi-Fi (guest) state; see the "mpsp/hotspot" channel.
    private var hotspot: WifiManager.LocalOnlyHotspotReservation? = null
    private var pendingHotspot: MethodChannel.Result? = null
    private var joinCallback: ConnectivityManager.NetworkCallback? = null

    // One "share this phone's audio" request can be in flight at a time (permissions, then consent, then service).
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSourceId: Long = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nativeInit(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Keeps the Wi-Fi radio out of power-save while a session is active (see acquireWifiLock).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mpsp/wifi").setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> result.success(acquireWifiLock())
                "release" -> { releaseWifiLock(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        // Wi-Fi in the pairing QR: the host can start an app-owned hotspot, a guest can join the hotspot from the QR.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mpsp/hotspot").setMethodCallHandler { call, result ->
            when (call.method) {
                "startHotspot" -> startHotspot(result)
                "stopHotspot" -> { hotspot?.close(); hotspot = null; result.success(null) }
                "joinWifi" -> joinWifi(call.argument<String>("ssid") ?: "", call.argument<String>("password") ?: "", result)
                "leaveWifi" -> { leaveWifi(); result.success(null) }
                "filesDir" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
        // Host side: capture what other apps are playing and feed it to the engine.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mpsp/capture").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startCapture((call.argument<Number>("sourceId") ?: 0).toLong(), result)
                "stop" -> { stopService(Intent(this, CaptureService::class.java)); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    // ---- audio capture (host) ----

    private fun startCapture(sourceId: Long, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported", "Sharing this phone's audio needs Android 10 or newer.", null)
            return
        }
        if (pendingResult != null) { result.error("busy", "Another request is in progress.", null); return }
        if (sourceId == 0L) { result.error("capture_failed", "No audio destination was given.", null); return }
        pendingResult = result
        pendingSourceId = sourceId

        // AudioRecord needs RECORD_AUDIO even for capturing other apps' playback (no microphone is used);
        // notifications are needed on Android 13+ for the "sharing" notice to be visible.
        val wanted = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33) wanted += Manifest.permission.POST_NOTIFICATIONS
        val missing = wanted.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) askCaptureConsent() else requestPermissions(missing.toTypedArray(), REQ_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_HOTSPOT_PERMISSION) {
            val r = pendingHotspot ?: return
            pendingHotspot = null
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) beginHotspot(r)
            else r.error("denied", "Creating a hotspot needs the nearby-devices / location permission, which was declined.", null)
            return
        }
        if (requestCode != REQ_PERMISSIONS || pendingResult == null) return
        val micIdx = permissions.indexOf(Manifest.permission.RECORD_AUDIO)
        val micDenied = micIdx >= 0 && grantResults[micIdx] != PackageManager.PERMISSION_GRANTED
        if (micDenied || checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            finishPending("denied_mic", "Audio permission was declined.")
        } else {
            askCaptureConsent() // a declined notification permission only hides the notice; capture still works
        }
    }

    private fun askCaptureConsent() {
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        @Suppress("DEPRECATION")
        startActivityForResult(manager.createScreenCaptureIntent(), REQ_CAPTURE_CONSENT)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_CAPTURE_CONSENT || pendingResult == null) return
        if (resultCode != RESULT_OK || data == null) {
            finishPending("denied", "Screen-capture permission was declined.")
            return
        }
        // The service replies through this callback once capture is really running (or has failed).
        CaptureService.onStarted = { error ->
            runOnUiThread { if (error == null) finishPending(null, null) else finishPending("capture_failed", error) }
        }
        val intent = Intent(this, CaptureService::class.java)
            .setAction(CaptureService.ACTION_START)
            .putExtra("resultCode", resultCode)
            .putExtra("data", data)
            .putExtra("sourceId", pendingSourceId)
        startForegroundService(intent)
    }

    private fun finishPending(errorCode: String?, message: String?) {
        val result = pendingResult ?: return
        pendingResult = null
        if (errorCode == null) result.success(null) else result.error(errorCode, message, null)
    }

    // ---- hotspot (host) ----

    private fun startHotspot(result: MethodChannel.Result) {
        if (pendingHotspot != null) { result.error("busy", "A hotspot request is already in progress.", null); return }
        if (hotspot != null) { result.error("busy", "The hotspot is already running.", null); return }
        // Android ties local-only hotspots to the nearby-devices permission (13+) or location (older).
        val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION
        if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
            pendingHotspot = result
            requestPermissions(arrayOf(permission), REQ_HOTSPOT_PERMISSION)
        } else {
            beginHotspot(result)
        }
    }

    private fun beginHotspot(result: MethodChannel.Result) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    hotspot = reservation
                    val ssid: String
                    val password: String
                    if (Build.VERSION.SDK_INT >= 30) {
                        val c = reservation.softApConfiguration
                        @Suppress("DEPRECATION")
                        ssid = c.ssid ?: ""
                        password = c.passphrase ?: ""
                    } else {
                        @Suppress("DEPRECATION")
                        val c = reservation.wifiConfiguration
                        ssid = c?.SSID?.trim('"') ?: ""
                        password = c?.preSharedKey?.trim('"') ?: ""
                    }
                    result.success(mapOf("ssid" to ssid, "password" to password))
                }

                override fun onStopped() { hotspot = null }

                override fun onFailed(reason: Int) {
                    val why = when (reason) {
                        ERROR_NO_CHANNEL -> "No Wi-Fi channel is free for a hotspot."
                        ERROR_INCOMPATIBLE_MODE -> "Turn off the phone's own hotspot first, or use it and type its name and password instead."
                        ERROR_TETHERING_DISALLOWED -> "Hotspots are not allowed on this device."
                        else -> "The hotspot could not start. Make sure Wi-Fi and location are turned on."
                    }
                    result.error("hotspot_failed", why, null)
                }
            }, Handler(Looper.getMainLooper()))
        } catch (e: SecurityException) {
            result.error("denied", "Android refused to start a hotspot (permission or location is off).", null)
        } catch (e: IllegalStateException) {
            result.error("hotspot_failed", "The hotspot could not start. Make sure Wi-Fi is turned on.", null)
        }
    }

    // ---- join a hotspot (guest) ----

    private fun joinWifi(ssid: String, password: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported", "Joining a Wi-Fi network from the app needs Android 10 or newer. Connect to \"$ssid\" in Settings, then join again.", null)
            return
        }
        leaveWifi()
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).apply { if (password.isNotEmpty()) setWpa2Passphrase(password) }.build()
        // The hotspot has no internet, so the request must not insist on it.
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(spec)
            .build()
        var replied = false
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                // Send this app's traffic (including the Rust audio sockets) over the hotspot.
                cm.bindProcessToNetwork(network)
                if (!replied) { replied = true; runOnUiThread { result.success(null) } }
            }

            override fun onUnavailable() {
                if (!replied) { replied = true; runOnUiThread { result.error("join_failed", "Could not join \"$ssid\". It was declined, out of range, or the password is wrong.", null) } }
            }

            override fun onLost(network: Network) { cm.bindProcessToNetwork(null) }
        }
        joinCallback = callback
        try {
            cm.requestNetwork(request, callback, 30_000)
        } catch (e: Exception) {
            joinCallback = null
            result.error("join_failed", "Could not ask Android to join \"$ssid\".", null)
        }
    }

    private fun leaveWifi() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        joinCallback?.let { try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {} }
        joinCallback = null
        cm.bindProcessToNetwork(null)
    }

    // ---- Wi-Fi lock ----

    private fun acquireWifiLock(): String {
        if (wifiLock?.isHeld == true) return "already held"
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        // FULL_LOW_LATENCY (API 29+) is the mode meant for this; it only takes effect while the app is in the
        // foreground with the screen on. Older phones get FULL_HIGH_PERF.
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                   else @Suppress("DEPRECATION") WifiManager.WIFI_MODE_FULL_HIGH_PERF
        val lock = wifi.createWifiLock(mode, "multiphone_player:session")
        lock.setReferenceCounted(false)
        lock.acquire()
        wifiLock = lock
        return if (mode == WifiManager.WIFI_MODE_FULL_LOW_LATENCY) "low-latency" else "high-perf"
    }

    private fun releaseWifiLock() {
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
    }

    override fun onDestroy() {
        hotspot?.close()
        hotspot = null
        leaveWifi()
        releaseWifiLock()
        stopService(Intent(this, CaptureService::class.java))
        super.onDestroy()
    }
}

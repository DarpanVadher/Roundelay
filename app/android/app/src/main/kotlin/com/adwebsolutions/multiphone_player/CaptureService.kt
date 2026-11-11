package com.adwebsolutions.multiphone_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import androidx.annotation.RequiresApi

/**
 * Captures what other apps are playing (Android 10+ playback capture, authorised by the user's screen-capture
 * consent) and pushes it into the Rust host engine. Must run as a foreground service of type mediaProjection.
 *
 * Only apps that allow capture can be heard: apps and content that opt out of playback capture (some streaming
 * and DRM apps) are silent here by design of Android, not by a fault of this service.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class CaptureService : Service() {
    companion object {
        const val ACTION_START = "com.adwebsolutions.multiphone_player.START_CAPTURE"
        private const val CHANNEL_ID = "mpsp_capture"
        private const val NOTIFICATION_ID = 7
        private const val RATE = 48_000
        private const val FRAME_SAMPLES = 480 * 2 // 10 ms of interleaved stereo

        /** Called once per start request: null on success, otherwise a readable error. Set by MainActivity. */
        @Volatile
        var onStarted: ((String?) -> Unit)? = null
    }

    private var projection: MediaProjection? = null
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile
    private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_START) return START_NOT_STICKY
        startAsForeground()
        try {
            startCapture(intent)
            report(null)
        } catch (e: Exception) {
            shutdown()
            report(e.message ?: e.javaClass.simpleName)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startAsForeground() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Sharing audio", NotificationManager.IMPORTANCE_LOW))
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Sharing this phone's audio")
            .setContentText("Other devices are playing what plays here.")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
    }

    private fun startCapture(intent: Intent) {
        val resultCode = intent.getIntExtra("resultCode", 0)
        @Suppress("DEPRECATION")
        val consent: Intent = intent.getParcelableExtra("data") ?: error("Screen-capture permission data is missing.")
        val sourceId = intent.getLongExtra("sourceId", 0L)
        check(sourceId != 0L) { "No audio destination was given." }

        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val mp = manager.getMediaProjection(resultCode, consent) ?: error("Screen-capture permission was not granted.")
        // Android 14+ requires a callback before the projection is used; it also tells us when the user revokes it.
        mp.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                shutdown()
                stopSelf()
            }
        }, Handler(Looper.getMainLooper()))
        projection = mp

        val config = AudioPlaybackCaptureConfiguration.Builder(mp)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
            .build()
        val minBytes = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord.Builder()
            .setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(minBytes, RATE * 4 / 5)) // ~200 ms of slack for scheduling hiccups
            .setAudioPlaybackCaptureConfig(config)
            .build()
        check(rec.state == AudioRecord.STATE_INITIALIZED) { "Audio capture could not be initialised." }
        rec.startRecording()
        record = rec
        running = true
        thread = Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val buffer = ShortArray(FRAME_SAMPLES)
            var peak = 0
            var frames = 0L
            var lastLog = System.nanoTime()
            // Debug only (flag file in the app's cache): keep the first 30 s of captured PCM to inspect offline.
            val dump = runCatching {
                if (java.io.File(cacheDir, "mpsp_trace_on").exists()) java.io.FileOutputStream(java.io.File(cacheDir, "capture.raw")) else null
            }.getOrNull()
            var dumped = 0L
            val bytes = java.nio.ByteBuffer.allocate(FRAME_SAMPLES * 2).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            while (running) {
                val n = rec.read(buffer, 0, buffer.size) // blocks until a 10 ms frame is available
                if (n < 0) break
                if (n > 0) {
                    MpspNative.push(sourceId, buffer, n / 2)
                    frames += n / 2
                    for (i in 0 until n) peak = maxOf(peak, kotlin.math.abs(buffer[i].toInt()))
                    if (dump != null && dumped < 30L * RATE * 2) {
                        bytes.clear()
                        for (i in 0 until n) bytes.putShort(buffer[i])
                        dump.write(bytes.array(), 0, n * 2)
                        dumped += n
                        if (dumped >= 30L * RATE * 2) dump.close()
                    }
                }
                if (System.nanoTime() - lastLog >= 1_000_000_000L) {
                    // A peak of 0 here means Android is delivering silence: the playing app blocks audio capture.
                    android.util.Log.i("mpsp-capture", "captured $frames frames in the last second, peak=$peak/32767")
                    peak = 0
                    frames = 0
                    lastLog = System.nanoTime()
                }
            }
        }, "mpsp-capture").apply { start() }
    }

    private fun report(error: String?) {
        val cb = onStarted
        onStarted = null
        cb?.invoke(error)
    }

    private fun shutdown() {
        running = false
        thread?.let { t -> if (t !== Thread.currentThread()) t.join(500) }
        thread = null
        record?.let { runCatching { it.stop() }; it.release() }
        record = null
        projection?.let { runCatching { it.stop() } }
        projection = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }
}

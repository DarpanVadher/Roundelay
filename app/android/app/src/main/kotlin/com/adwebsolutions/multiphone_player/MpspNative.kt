package com.adwebsolutions.multiphone_player

/** JNI entry points into the Rust engine (core/mpsp-ffi). */
object MpspNative {
    init {
        System.loadLibrary("mpsp_ffi")
    }

    /**
     * Hands captured audio to the host engine. [pcm] is interleaved 16-bit stereo at 48 kHz holding [frames] frames.
     * [id] is the external-source id from `mpsp_host_external_id`; an id whose host is gone is simply rejected.
     */
    @JvmStatic
    external fun push(id: Long, pcm: ShortArray, frames: Int): Boolean
}

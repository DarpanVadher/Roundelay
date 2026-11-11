//! C ABI for Flutter (`dart:ffi`). Everything crosses the boundary as plain C strings:
//! events are JSON, polled by Dart on a timer (no callbacks, so no cross-thread Dart calls).
//!
//! Ownership rules:
//! * `mpsp_*_start/join` return an opaque handle (or NULL + `*err`); release with `mpsp_*_stop/leave`.
//! * Strings returned by this library (`*_poll`, `err`) must be released with `mpsp_free_string`.
//! * Strings passed in are borrowed for the call only.
use mpsp_engine::{AudioSource, ExternalSource, Guest, GuestOptions, Host, HostOptions};
use std::ffi::{c_char, c_int, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock, Weak};

fn to_c(s: String) -> *mut c_char {
    CString::new(s.replace('\0', " ")).unwrap().into_raw()
}

unsafe fn from_c(p: *const c_char) -> Option<String> {
    if p.is_null() { None } else { CStr::from_ptr(p).to_str().ok().map(str::to_owned) }
}

unsafe fn set_err(err: *mut *mut c_char, msg: String) {
    if !err.is_null() { *err = to_c(msg); }
}

/// Never let a Rust panic unwind into Dart.
fn guarded<T>(default: T, f: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(default)
}

/// Called once from `MainActivity.onCreate`. Hands the Android app Context to `ndk-context`, which cpal's
/// Oboe backend needs to query the audio system. Without it the first stream creation panics.
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_adwebsolutions_multiphone_1player_MainActivity_nativeInit(
    env: jni::JNIEnv,
    _this: jni::objects::JObject,
    context: jni::objects::JObject,
) {
    guarded((), || {
        let (Ok(vm), Ok(global)) = (env.get_java_vm(), env.new_global_ref(&context)) else { return };
        // The global reference is intentionally leaked: the context must stay valid for the whole process.
        let ctx = global.as_obj().as_raw() as *mut std::ffi::c_void;
        std::mem::forget(global);
        unsafe { ndk_context::initialize_android_context(vm.get_java_vm_pointer() as *mut std::ffi::c_void, ctx) };
    })
}

/// Diagnostics: makes the next guest sessions write a per-packet CSV trace to `path` (same as setting the
/// MPSP_TRACE environment variable, which an app cannot do for its own process on Android).
///
/// # Safety
/// `path` must be a valid NUL-terminated string. Call before joining, not concurrently with other threads
/// reading the environment.
#[no_mangle]
pub unsafe extern "C" fn mpsp_set_trace_path(path: *const c_char) {
    guarded((), || { if let Some(p) = from_c(path) { std::env::set_var("MPSP_TRACE", p); } })
}

#[no_mangle]
pub extern "C" fn mpsp_free_string(s: *mut c_char) {
    if !s.is_null() { drop(unsafe { CString::from_raw(s) }); }
}

unsafe fn start_host(lan_ip: *const c_char, port: u16, data_dir: *const c_char, source: AudioSource, err: *mut *mut c_char) -> *mut Host {
    guarded(std::ptr::null_mut(), || {
        let (Some(ip), Some(dir)) = (from_c(lan_ip), from_c(data_dir)) else {
            set_err(err, "invalid arguments".into());
            return std::ptr::null_mut();
        };
        match Host::start(&ip, port, &PathBuf::from(dir), HostOptions { source }) {
            Ok(h) => Box::into_raw(Box::new(h)),
            Err(e) => { set_err(err, e.to_string()); std::ptr::null_mut() }
        }
    })
}

/// Starts hosting, capturing this computer's system audio. `data_dir` holds the host identity key.
/// Returns NULL and sets `*err` on failure.
///
/// # Safety
/// `lan_ip` and `data_dir` must be valid NUL-terminated strings; `err` may be NULL or a valid out pointer.
#[no_mangle]
pub unsafe extern "C" fn mpsp_host_start(lan_ip: *const c_char, port: u16, data_dir: *const c_char, err: *mut *mut c_char) -> *mut Host {
    start_host(lan_ip, port, data_dir, AudioSource::SystemLoopback, err)
}

/// Like `mpsp_host_start`, with the audio source chosen by the caller: 0 = system loopback, 1 = external (the
/// platform pushes PCM through `mpsp_host_push_pcm`, as the Android capture service does), 2 = none.
///
/// # Safety
/// Same as `mpsp_host_start`.
#[no_mangle]
pub unsafe extern "C" fn mpsp_host_start_ex(lan_ip: *const c_char, port: u16, data_dir: *const c_char, source: c_int, err: *mut *mut c_char) -> *mut Host {
    let source = match source { 1 => AudioSource::External, 2 => AudioSource::None, _ => AudioSource::SystemLoopback };
    start_host(lan_ip, port, data_dir, source, err)
}

fn registry() -> &'static Mutex<HashMap<u64, Weak<ExternalSource>>> {
    static R: OnceLock<Mutex<HashMap<u64, Weak<ExternalSource>>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Pushes PCM to the external source registered under `id`. Returns false if the id is unknown or its host is
/// gone: ids are looked up, never dereferenced, so a stale id from a late audio thread is harmless.
pub fn push_external(id: u64, pcm: &[i16]) -> bool {
    let weak = registry().lock().ok().and_then(|r| r.get(&id).cloned());
    match weak.and_then(|w| w.upgrade()) {
        Some(src) => { src.push_i16(pcm); true }
        None => false,
    }
}

/// For a host started with source 1: returns a non-zero id the platform's capture code passes to
/// `mpsp_host_push_pcm` (or the JNI `MpspNative.push`). Returns 0 for hosts without an external source.
///
/// # Safety
/// `h` must come from `mpsp_host_start*` and not have been stopped.
#[no_mangle]
pub unsafe extern "C" fn mpsp_host_external_id(h: *mut Host) -> u64 {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    guarded(0, || {
        let Some(src) = h.as_ref().and_then(|h| h.external_source()) else { return 0 };
        let id = NEXT.fetch_add(1, Ordering::Relaxed);
        let mut r = registry().lock().unwrap();
        r.retain(|_, w| w.strong_count() > 0); // forget hosts that have shut down
        r.insert(id, Arc::downgrade(&src));
        id
    })
}

/// Pushes `samples` interleaved 16-bit stereo samples (so `samples / 2` frames) at 48 kHz. Returns 1 if accepted.
///
/// # Safety
/// `data` must point to `samples` readable `i16` values.
#[no_mangle]
pub unsafe extern "C" fn mpsp_host_push_pcm(id: u64, data: *const i16, samples: usize) -> c_int {
    guarded(0, || {
        if data.is_null() { return 0; }
        push_external(id, std::slice::from_raw_parts(data, samples)) as c_int
    })
}

/// JNI: `MpspNative.push(id, pcm, frames)` from the Android capture thread (`frames` = stereo frames in `pcm`).
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_adwebsolutions_multiphone_1player_MpspNative_push(
    env: jni::JNIEnv,
    _class: jni::objects::JClass,
    id: jni::sys::jlong,
    pcm: jni::objects::JShortArray,
    frames: jni::sys::jint,
) -> jni::sys::jboolean {
    guarded(0, || {
        let mut buf = vec![0i16; (frames.max(0) as usize) * 2];
        if env.get_short_array_region(&pcm, 0, &mut buf).is_err() { return 0; }
        push_external(id as u64, &buf) as jni::sys::jboolean
    })
}

/// Returns the next event as JSON, or NULL when none is queued. Free with `mpsp_free_string`.
///
/// # Safety
/// `h` must come from `mpsp_host_start` and not have been stopped.
#[no_mangle]
pub unsafe extern "C" fn mpsp_host_poll(h: *mut Host) -> *mut c_char {
    guarded(std::ptr::null_mut(), || {
        match h.as_ref().and_then(|h| h.poll()) {
            Some(e) => to_c(serde_json::to_string(&e).unwrap_or_default()),
            None => std::ptr::null_mut(),
        }
    })
}

/// # Safety
/// `h` from `mpsp_host_start`; `id` a valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn mpsp_host_respond(h: *mut Host, id: *const c_char, allow: c_int) {
    guarded((), || { if let (Some(h), Some(id)) = (h.as_ref(), from_c(id)) { h.respond(&id, allow != 0); } })
}

/// # Safety
/// `h` from `mpsp_host_start`; `id` a valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn mpsp_host_kick(h: *mut Host, id: *const c_char) {
    guarded((), || { if let (Some(h), Some(id)) = (h.as_ref(), from_c(id)) { h.kick(&id); } })
}

/// Stops the host and frees the handle. Returns immediately; the shutdown finishes on a background thread
/// so the UI thread never waits on worker threads.
///
/// # Safety
/// `h` from `mpsp_host_start`, used at most once afterwards (never).
#[no_mangle]
pub unsafe extern "C" fn mpsp_host_stop(h: *mut Host) {
    if h.is_null() { return; }
    let boxed = Box::from_raw(h);
    std::thread::spawn(move || drop(boxed));
}

/// Joins a host from a pairing link. Returns immediately; progress arrives through `mpsp_guest_poll`.
///
/// # Safety
/// `link` a valid NUL-terminated string; `err` may be NULL or a valid out pointer.
#[no_mangle]
pub unsafe extern "C" fn mpsp_guest_join(link: *const c_char, audio_port: u16, delay_ms: u32, err: *mut *mut c_char) -> *mut Guest {
    guarded(std::ptr::null_mut(), || match from_c(link) {
        Some(l) => Box::into_raw(Box::new(Guest::join(&l, audio_port, delay_ms, GuestOptions::default()))),
        None => { set_err(err, "invalid link".into()); std::ptr::null_mut() }
    })
}

/// # Safety
/// `g` from `mpsp_guest_join` and not yet released.
#[no_mangle]
pub unsafe extern "C" fn mpsp_guest_poll(g: *mut Guest) -> *mut c_char {
    guarded(std::ptr::null_mut(), || {
        match g.as_ref().and_then(|g| g.poll()) {
            Some(s) => to_c(serde_json::to_string(&s).unwrap_or_default()),
            None => std::ptr::null_mut(),
        }
    })
}

/// Leaves and frees the handle.
///
/// # Safety
/// `g` from `mpsp_guest_join`, used at most once afterwards (never).
#[no_mangle]
pub unsafe extern "C" fn mpsp_guest_leave(g: *mut Guest) {
    if g.is_null() { return; }
    drop(Box::from_raw(g)); // Drop only sets the stop flag
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_lifecycle_through_the_c_abi() {
        // audio is on by default in the C ABI; use a throwaway dir and just verify error/ownership paths.
        let mut err: *mut c_char = std::ptr::null_mut();
        let bad = unsafe { mpsp_host_start(std::ptr::null(), 0, std::ptr::null(), &mut err) };
        assert!(bad.is_null());
        assert!(!err.is_null());
        let msg = unsafe { CStr::from_ptr(err) }.to_str().unwrap().to_string();
        assert_eq!(msg, "invalid arguments");
        mpsp_free_string(err);
        assert!(unsafe { mpsp_host_poll(std::ptr::null_mut()) }.is_null());
    }

    #[test]
    fn external_source_ids_are_safe_when_the_host_is_gone() {
        let dir = CString::new(std::env::temp_dir().join("mpsp-ffi-ext").to_str().unwrap()).unwrap();
        let ip = CString::new("127.0.0.1").unwrap();
        let pcm = vec![100i16; 960];
        unsafe {
            // source 1 = external: an id comes back and pushing works
            let h = mpsp_host_start_ex(ip.as_ptr(), 0, dir.as_ptr(), 1, std::ptr::null_mut());
            assert!(!h.is_null());
            let id = mpsp_host_external_id(h);
            assert_ne!(id, 0);
            assert_eq!(mpsp_host_push_pcm(id, pcm.as_ptr(), pcm.len()), 1);
            // after the host shuts down the id must be rejected, not dereferenced
            drop(Box::from_raw(h));
            assert_eq!(mpsp_host_push_pcm(id, pcm.as_ptr(), pcm.len()), 0);
            // unknown ids and null data are rejected
            assert_eq!(mpsp_host_push_pcm(u64::MAX, pcm.as_ptr(), pcm.len()), 0);
            assert_eq!(mpsp_host_push_pcm(id, std::ptr::null(), 4), 0);
            // a host without an external source has no id
            let n = mpsp_host_start_ex(ip.as_ptr(), 0, dir.as_ptr(), 2, std::ptr::null_mut());
            assert!(!n.is_null());
            assert_eq!(mpsp_host_external_id(n), 0);
            drop(Box::from_raw(n));
        }
    }

    #[test]
    fn guest_reports_invalid_link_as_error_status() {
        let link = CString::new("not a link").unwrap();
        let g = unsafe { mpsp_guest_join(link.as_ptr(), 0, 80, std::ptr::null_mut()) };
        assert!(!g.is_null());
        let mut json = String::new();
        for _ in 0..50 {
            let p = unsafe { mpsp_guest_poll(g) };
            if !p.is_null() {
                let s = unsafe { CStr::from_ptr(p) }.to_str().unwrap().to_string();
                mpsp_free_string(p);
                if s.contains("error") { json = s; break; }
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        unsafe { mpsp_guest_leave(g) };
        assert!(json.contains(r#""phase":"error""#), "{json}");
    }
}

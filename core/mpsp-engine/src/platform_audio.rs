//! Questions about the operating system's own audio mixer, so the app can tell a person why they hear nothing.
//!
//! On Windows every app has a per-app volume and mute in the Volume Mixer, remembered between runs. If it is muted
//! or near zero, our audio reaches the sound card at full scale and still comes out silent, with nothing else
//! looking wrong ("Playing in sync"). Reading that state lets the UI say so.

/// This app's volume slider (0.0 to 1.0) and mute switch in the OS mixer.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SessionVolume {
    pub volume: f32,
    pub muted: bool,
}

/// Below this the app is effectively inaudible even though it is not muted.
pub const NEAR_SILENT_VOLUME: f32 = 0.05;

impl SessionVolume {
    /// True when the person cannot hear us because of the mixer.
    pub fn is_inaudible(&self) -> bool {
        self.muted || self.volume < NEAR_SILENT_VOLUME
    }
}

/// Call once on a thread before [`own_session_volume`] (no-op off Windows).
pub fn init_com() {
    #[cfg(windows)]
    win::init_com();
}

/// The mixer state of this process's output session on the default output device, or `None` when there is no such
/// session (nothing is playing yet, no device) or the platform has no per-app mixer we can read (everything but
/// Windows).
pub fn own_session_volume() -> Option<SessionVolume> {
    #[cfg(windows)]
    {
        win::own_session_volume()
    }
    #[cfg(not(windows))]
    {
        None
    }
}

#[cfg(windows)]
mod win {
    use super::SessionVolume;
    use windows::core::Interface;
    use windows::Win32::Media::Audio::{eConsole, eRender, IAudioSessionControl2, IAudioSessionManager2, IMMDeviceEnumerator, ISimpleAudioVolume, MMDeviceEnumerator};
    use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_MULTITHREADED};

    pub fn init_com() {
        // S_FALSE (already initialised) and a different apartment model are both fine for our read-only use.
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        }
    }

    pub fn own_session_volume() -> Option<SessionVolume> {
        unsafe {
            let enumerator: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL).ok()?;
            let device = enumerator.GetDefaultAudioEndpoint(eRender, eConsole).ok()?;
            let manager: IAudioSessionManager2 = device.Activate(CLSCTX_ALL, None).ok()?;
            let sessions = manager.GetSessionEnumerator().ok()?;
            let me = std::process::id();
            for i in 0..sessions.GetCount().ok()? {
                let control = sessions.GetSession(i).ok()?;
                let control2: IAudioSessionControl2 = control.cast().ok()?;
                if control2.GetProcessId().ok()? != me {
                    continue;
                }
                let volume: ISimpleAudioVolume = control.cast().ok()?;
                return Some(SessionVolume { volume: volume.GetMasterVolume().ok()?, muted: volume.GetMute().ok()?.as_bool() });
            }
            None
        }
    }

    /// Test helper: set our own session's mute (the state the Volume Mixer shows for this program).
    #[cfg(test)]
    pub fn set_own_mute(muted: bool) -> bool {
        use windows::Win32::Foundation::BOOL;
        unsafe {
            let Ok(enumerator) = CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL) else { return false };
            let Ok(device) = enumerator.GetDefaultAudioEndpoint(eRender, eConsole) else { return false };
            let Ok(manager) = device.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else { return false };
            let Ok(sessions) = manager.GetSessionEnumerator() else { return false };
            let me = std::process::id();
            for i in 0..sessions.GetCount().unwrap_or(0) {
                let Ok(control) = sessions.GetSession(i) else { continue };
                let Ok(control2) = control.cast::<IAudioSessionControl2>() else { continue };
                if control2.GetProcessId().unwrap_or(0) != me {
                    continue;
                }
                let Ok(volume) = control.cast::<ISimpleAudioVolume>() else { continue };
                return volume.SetMute(BOOL::from(muted), std::ptr::null()).is_ok();
            }
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn muted_or_nearly_silent_sessions_are_inaudible_normal_ones_are_not() {
        assert!(SessionVolume { volume: 1.0, muted: true }.is_inaudible(), "muted");
        assert!(SessionVolume { volume: 0.0, muted: false }.is_inaudible(), "slider at zero");
        assert!(SessionVolume { volume: 0.04, muted: false }.is_inaudible(), "just below the threshold");
        assert!(!SessionVolume { volume: 0.05, muted: false }.is_inaudible(), "at the threshold is still audible");
        assert!(!SessionVolume { volume: 0.5, muted: false }.is_inaudible());
        assert!(!SessionVolume { volume: 1.0, muted: false }.is_inaudible());
    }

    #[test]
    fn no_session_reads_as_none_not_a_crash() {
        init_com();
        // Unit tests run on separate threads in one process: another test may legitimately be playing, so only
        // check that asking never panics.
        let _ = own_session_volume();
    }

    /// End to end on Windows: open a real (silent) output stream so Windows creates our session, mute it through the
    /// Windows API, and check the detector reports it; then unmute and check it reports that too.
    #[cfg(windows)]
    #[test]
    fn detects_our_own_session_being_muted_and_unmuted() {
        use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
        init_com();
        let Some(dev) = cpal::default_host().default_output_device() else { return }; // no sound card: nothing to check
        let Ok((cfg, _rate)) = crate::common::output_config(&dev) else { return };
        let Ok(stream) = dev.build_output_stream(&cfg, move |d: &mut [f32], _| d.fill(0.0), |_| {}, None) else { return };
        stream.play().unwrap();
        // The session appears shortly after the stream starts.
        let mut found = None;
        for _ in 0..40 {
            if let Some(v) = own_session_volume() {
                found = Some(v);
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        let before = found.expect("an active output stream must show up as one of our sessions");
        assert!((0.0..=1.0).contains(&before.volume));

        assert!(win::set_own_mute(true), "could not mute our own session");
        std::thread::sleep(std::time::Duration::from_millis(100));
        let muted = own_session_volume().expect("session still there");
        assert!(muted.muted && muted.is_inaudible(), "muted session must be reported inaudible: {muted:?}");

        assert!(win::set_own_mute(false), "could not unmute our own session");
        std::thread::sleep(std::time::Duration::from_millis(100));
        let unmuted = own_session_volume().expect("session still there");
        assert!(!unmuted.muted, "unmuted session reported muted: {unmuted:?}");
        drop(stream);
    }
}

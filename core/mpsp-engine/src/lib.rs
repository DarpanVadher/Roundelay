//! Audio engine: host (capture -> Opus -> encrypted UDP) and guest (receive -> jitter -> drift-corrected playout),
//! pairing and clock sync included. Exposes plain Rust handles with event queues; `mpsp-ffi` wraps them in a
//! C ABI for Flutter and `mpsp-cli` wraps them for the terminal.
mod common;
pub mod guest;
pub mod host;
pub mod link;
pub mod platform_audio;

pub use common::Stop;
pub use guest::{Guest, GuestOptions, GuestPhase, GuestStatus};
pub use host::{AudioSource, ExternalSource, GuestView, Host, HostEvent, HostOptions};

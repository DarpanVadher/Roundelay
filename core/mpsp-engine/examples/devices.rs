//! Lists every audio output device with the formats cpal can open on it: which sample rates the engine could
//! use. Run it while Bluetooth headphones are connected to see why a device is (not) usable.
use cpal::traits::{DeviceTrait, HostTrait};

fn main() {
    let host = cpal::default_host();
    let default = host.default_output_device().and_then(|d| d.name().ok());
    println!("default output: {}", default.as_deref().unwrap_or("(none)"));
    for d in host.output_devices().expect("devices") {
        let name = d.name().unwrap_or_default();
        println!("\n{}{}", name, if Some(&name) == default.as_ref() { "   <-- default" } else { "" });
        match d.default_output_config() {
            Ok(c) => println!("  default (mix) format: {:?} {} Hz, {} ch", c.sample_format(), c.sample_rate().0, c.channels()),
            Err(e) => println!("  default format: error {e}"),
        }
        match d.supported_output_configs() {
            Ok(it) => for r in it {
                println!("  supports: {:?}  {}..{} Hz  {} ch", r.sample_format(), r.min_sample_rate().0, r.max_sample_rate().0, r.channels());
            },
            Err(e) => println!("  supported configs: error {e}"),
        }
    }
}

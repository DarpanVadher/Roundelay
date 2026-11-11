// Oboe (cpal's Android audio backend) is C++. Its vtables reference the C++ runtime (e.g. __cxa_pure_virtual),
// but Rust links the cdylib with the plain C driver, so nothing pulls the runtime in and Android's loader later
// fails with "cannot locate symbol __cxa_pure_virtual". Link libc++ statically so the .so is self-contained
// (avoids shipping libc++_shared.so next to it).
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        println!("cargo:rustc-link-lib=static=c++_static");
        println!("cargo:rustc-link-lib=static=c++abi");
    }
}

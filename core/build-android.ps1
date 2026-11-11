# Builds libmpsp_ffi.so for Android and drops it into the Flutter app's jniLibs.
#   ./build-android.ps1                       # arm64-v8a, armeabi-v7a, x86_64 (release)
#   ./build-android.ps1 -Abis arm64-v8a       # one ABI, faster
#
# Needs: Android NDK (ANDROID_NDK_HOME, or <ANDROID_HOME|C:\Android>\ndk\<version>), CMake, Ninja, Rust Android
# targets (rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android), cargo-ndk.
#
# Why per-ABI toolchain files: audiopus_sys builds Opus through the `cmake` crate, which does not pass
# ANDROID_ABI, so the NDK toolchain silently falls back to armeabi-v7a. The tiny wrapper files below fix the ABI.
param(
    [string[]]$Abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64'),
    [string]$Out = (Join-Path $PSScriptRoot '..\app\android\app\src\main\jniLibs'),
    [int]$ApiLevel = 21
)
$ErrorActionPreference = 'Stop'

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'C:\Android' }
$ndk = if ($env:ANDROID_NDK_HOME) { $env:ANDROID_NDK_HOME } else {
    (Get-ChildItem (Join-Path $sdk 'ndk') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
}
if (-not $ndk -or -not (Test-Path $ndk)) { throw "Android NDK not found. Set ANDROID_NDK_HOME." }
$env:ANDROID_NDK_HOME = $ndk
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) { throw "ninja not found on PATH (winget install Ninja-build.Ninja)." }
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { $env:Path += ';C:\Program Files\CMake\bin' }

# Opus's bundled CMakeLists predates CMake 4; Windows' 260-char path limit breaks deep target dirs.
$env:CMAKE_POLICY_VERSION_MINIMUM = '3.5'
if (-not $env:CARGO_TARGET_DIR -and $PSScriptRoot.Length -gt 50) { $env:CARGO_TARGET_DIR = 'C:\mpsp-target' }
$env:CMAKE_GENERATOR = 'Ninja'

$triples = @{ 'arm64-v8a' = 'aarch64_linux_android'; 'armeabi-v7a' = 'armv7_linux_androideabi'; 'x86_64' = 'x86_64_linux_android'; 'x86' = 'i686_linux_android' }
$tc = Join-Path ([IO.Path]::GetTempPath()) 'mpsp-android-toolchains'
New-Item -ItemType Directory -Force $tc | Out-Null
$ndkFwd = $ndk -replace '\\', '/'
foreach ($abi in $Abis) {
    $file = Join-Path $tc "$abi.cmake"
    "set(ANDROID_ABI $abi)`nset(ANDROID_PLATFORM android-$ApiLevel)`ninclude(`"$ndkFwd/build/cmake/android.toolchain.cmake`")" | Set-Content $file -Encoding ascii
    # Per-target variable: only this ABI's Opus build sees it; the host (Windows) build is unaffected.
    Set-Item "env:CMAKE_TOOLCHAIN_FILE_$($triples[$abi])" ($file -replace '\\', '/')
}

$abiArgs = $Abis | ForEach-Object { '-t'; $_ }
Push-Location $PSScriptRoot
try {
    # cargo writes progress to stderr; under 'Stop' Windows PowerShell 5.1 would treat that as a failure.
    $ErrorActionPreference = 'Continue'
    & cargo ndk @abiArgs --platform $ApiLevel -o $Out build -p mpsp-ffi --release 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0) { throw "cargo ndk failed (exit $code)" }
} finally { Pop-Location }
Get-ChildItem $Out -Recurse -Filter *.so | Select-Object @{n = 'Library'; e = { $_.FullName.Substring((Resolve-Path $Out).Path.Length) } }, @{n = 'KB'; e = { [int]($_.Length / 1KB) } }

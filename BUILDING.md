# Building the runner release

The tested runner was built from the CodeWeavers 26.0.0 source bundle using a
MinGW PE build for both `i386` and `x86_64`, with the Rosetta x87 loader patch
in [patches/rosettax87-loader.patch](patches/rosettax87-loader.patch).

The configure options used were:

```text
--build=x86_64-apple-darwin
--enable-archs=i386,x86_64
--disable-tests
--without-alsa --without-capi --with-coreaudio --without-cups
--without-dbus --without-fontconfig --with-freetype --without-gettext
--without-gnutls --without-gphoto --without-gssapi --without-gstreamer
--without-inotify --without-krb5 --without-netapi --without-opencl
--without-opengl --without-oss --without-pcap --without-pcsclite
--with-pthread --without-pulse --without-sane --without-sdl
--without-udev --without-usb --without-v4l2 --without-vulkan
--without-wayland --without-x
```

The build requires Apple developer tools plus MinGW cross-compilers for i686
and x86_64 Windows targets. The runtime bundles MoltenVK separately even though
Wine itself is configured without Vulkan.

To package an already-built and tested runner:

```bash
./scripts/build-release.sh \
  --runner "/path/to/WineCX26-RosettaX87-Mingw" \
  --source-archive "/path/to/crossover-sources-26.0.0.tar.gz"
```

The command creates sanitized archives and checksums in `dist/`. It strips
debug data, removes machine-specific build paths, excludes backups, and fails
if known Ascension binary names are present.

## Building the launcher-only DMG

The standalone DMG bundles the compatibility runtime and the official
Ascension Launcher installer, but no game data. On first launch, the app creates
a writable Wine prefix in `~/Library/Application Support/Project Ascension` and
opens the bundled official installer. It also downloads the required x86 and
x64 Visual C++ redistributables directly from Microsoft. The Ascension Launcher
then downloads the game normally.

```bash
./scripts/build-dmg.sh
```

The build downloads and verifies the v1.0.0 compatibility runner and downloads
the current official launcher installer directly from Ascension. Existing
downloads can be supplied for an offline rebuild:

```bash
./scripts/build-dmg.sh \
  --runner-archive /path/to/ascension-winecx26-rosettax87-mingw-v1.0.0.tar.xz \
  --launcher-installer /path/to/ascension-setup.exe
```

The resulting DMG and SHA-256 file are written to `dist/`. The app is ad-hoc
signed for local testing. Public distribution without Gatekeeper warnings
requires an Apple Developer ID signature and notarization.

The DMG build also compiles the native settings application as a universal
Apple Silicon/x86_64 executable and the Wine menu integration library as
x86_64. Both use the macOS AppKit SDK supplied by Apple developer tools. The
settings helper controls the bundled DXVK HUD through launch-time environment
configuration; it does not patch or replace the official launcher.

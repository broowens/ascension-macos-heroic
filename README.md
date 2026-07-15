# Project Ascension on Apple Silicon with Heroic

An automated compatibility package for running Project Ascension through
Heroic on Apple Silicon Macs.

It addresses two startup failures seen with the 32-bit game client and its
64-bit Memory Bridge helper:

- a black screen caused by a Wine `MSVCP140` lock deadlock;
- `Failed to initialize memory bridge` caused by an incompatible x64 runtime.

The installer adds the tested WineCX 26/Rosetta x87 runner, installs matching
x86 and x64 Microsoft VC++ runtime files from Ascension's own cached
redistributable, and updates only Ascension's Heroic settings.

## Requirements

- An Apple Silicon Mac.
- Heroic Games Launcher.
- Project Ascension already installed through Heroic and launched once.
- Python 3 (`brew install python` if `python3` is unavailable).
- Heroic, Ascension Launcher, and the game must be closed during installation.

## Install

Download both files from the latest GitHub release:

- `ascension-macos-heroic-v1.0.0.tar.gz`
- `ascension-winecx26-rosettax87-mingw-v1.0.0.tar.xz`

Extract the first archive, place the runner archive beside `install.sh`, then:

```bash
chmod +x install.sh rollback.sh diagnose.sh
./install.sh --runner-archive ./ascension-winecx26-rosettax87-mingw-v1.0.0.tar.xz
```

The installer auto-detects the Ascension prefix and Heroic game configuration.
For non-standard locations:

```bash
./install.sh \
  --runner-archive /path/to/ascension-winecx26-rosettax87-mingw-v1.0.0.tar.xz \
  --prefix "/path/to/Heroic/Prefixes/Ascension" \
  --config "/path/to/heroic/GamesConfig/game-id.json"
```

Open Heroic after installation and press Play.

## Diagnostics and rollback

```bash
./diagnose.sh
./rollback.sh
```

Installation backups are stored inside the Wine prefix under
`.ascension-macos-fix/`. The diagnostic output deliberately excludes command
lines and login credentials.

## What is not included

This repository and its release assets do not contain Ascension game files,
account details, or Microsoft runtime DLLs. The runtime files are extracted
locally from the VC++ redistributable cached by Ascension's installer.

The custom runner is published as a separate release asset. Its corresponding
CodeWeavers source archive and the Rosetta x87 loader patch should be attached
to the same release; see [BUILDING.md](BUILDING.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Tested configuration

- Apple M4 Pro
- macOS 26.5.2
- Heroic
- WineCX 26-derived Wine 11.0 runner with Rosetta x87 loader
- Microsoft Visual C++ runtime 14.50.35719

Other Apple Silicon models should work, but are not yet confirmed.

Project Ascension, Heroic, Microsoft, Apple, Wine, and CodeWeavers are owned by
their respective authors. This is an independent community compatibility
project.

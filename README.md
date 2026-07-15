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

## One-command install

Clone the repository and run the installer with one command:

```bash
git clone https://github.com/broowens/ascension-macos-heroic.git && cd ascension-macos-heroic && ./bootstrap.sh
```

Once this repository is public, an Apple Silicon Mac can install everything by
opening Terminal and running:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/broowens/ascension-macos-heroic/main/bootstrap.sh)"
```

The bootstrapper checks each stage and installs what is missing:

- Python 3 (and Homebrew first, if needed);
- the latest Apple Silicon release of Heroic;
- the custom WineCX/Rosetta x87 runner;
- the official Ascension Launcher and game;
- the Microsoft runtime fix and Heroic launch settings.
- a native Project Ascension application in `~/Applications`, indexed by
  Spotlight.

Ascension's own setup and download windows are interactive. Follow those
windows, wait for the game download to finish, and close the Ascension Launcher
when prompted. If it is closed early or a download is interrupted, run the same
command again; completed stages are detected and skipped.

To inspect an existing checkout without changing anything:

```bash
./bootstrap.sh --dry-run
```

While the repository is private, clone it with an authenticated GitHub account
and run `./bootstrap.sh`. Private release downloads use the authenticated `gh`
command automatically when it is available.

## Requirements

- An Apple Silicon Mac.
- An internet connection and enough free space for Heroic and the game.
- Administrator approval if Homebrew needs to be installed.
- Heroic, Ascension Launcher, and the game closed before starting or resuming.

## Compatibility-fix-only install

If Heroic and Ascension are already installed, the smaller compatibility-only
installer remains available. Download both files from the latest GitHub release:

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

Open Heroic after installation and press Play, or launch Project Ascension from
Spotlight.

## Uninstall

From a checkout, run:

```bash
./uninstall.sh
```

The uninstaller removes the Ascension Wine prefix, its Heroic library entry,
game-specific Heroic configuration, the dedicated compatibility runner, the
installer cache, and the Project Ascension application shortcut. It keeps
Heroic, Homebrew, Python, and Heroic data for other games. To remove the Heroic
application too, use `./uninstall.sh --remove-heroic`.

Once the repository is public, the uninstaller can also be run directly:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/broowens/ascension-macos-heroic/main/uninstall.sh)"
```

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

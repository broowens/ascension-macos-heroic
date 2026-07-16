# Open-source runtime audit

The compatibility runner distributed with this project was audited against:

- runner archive SHA-256: `da832e55fe008b4b317e70c9de8ea48d8a4e0d8cfb16ffa94bb6aaddb8152366`;
- corresponding source archive SHA-256: `544d6ef462e5089017340ccf66df0a8cdc117aa9895d91d7c5d10edaa5fcbc56`.

The CodeWeavers-derived portion consists of Wine executables, Wine libraries,
Wine modules, headers/metadata, and command-line build tools compiled from the
published CrossOver 26.0.0 FOSS source bundle. That source bundle contains only
recognized open-source package roots and includes Wine's LGPL 2.1 license.

The runner does not contain the proprietary CrossOver application, app bundle,
license activation signature, installer, user interface, account management
tools, or `cxoffice` tree. Separately bundled runtime libraries are recognizable
open-source dependencies such as MoltenVK, FreeType, GnuTLS, GMP, Nettle, SDL2,
ICU, libxml2, libpng, and compression libraries. The Rosetta x87 compatibility
payload is sourced from the GPLv3 WoWSilicon project.

`scripts/audit-runner.sh` enforces the audited executable, library, source-package,
and directory allowlists. Both runner release creation and DMG creation fail if
an unexpected or known proprietary CrossOver product artifact appears.

This content audit confirms that the package does not include proprietary
CrossOver product components. It does not replace the separate obligation to
ship complete license notices and corresponding source for every open-source
component with each public binary release.

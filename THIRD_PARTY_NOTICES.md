# Third-party notices

## Non-affiliation and trademarks

This is an unofficial, independent, third-party community compatibility
project. It is not affiliated with, endorsed by, sponsored by, authorized by,
or supported by Project Ascension or any developer, publisher, maintainer,
licensor, or rights holder associated with the games, launchers, compatibility
tools, operating systems, or other software with which it interoperates.

All product names, project names, trademarks, service marks, logos, artwork,
and other intellectual property are the property of their respective owners.
References to them are descriptive and are used only to identify the software
with which this project is intended to interoperate. No ownership, endorsement,
partnership, agency, or other official relationship is claimed or implied.

This project does not grant users any license or other rights to third-party
software, game content, accounts, services, or intellectual property. Users are
responsible for obtaining required software lawfully and for complying with all
applicable third-party licenses, terms of service, and other conditions.

## Included and referenced components

The installer scripts in this repository are licensed under the MIT License.

The optional runner release asset contains third-party components under their
respective licenses, including Wine/CodeWeavers sources, FreeType, MoltenVK,
DXVK-related components, and their dependencies. Wine is distributed under the
GNU Lesser General Public License. Preserve the license files shipped in the
runner and publish the corresponding `crossover-sources-26.0.0.tar.gz` source
asset with each binary release.

The release builder excludes Project Ascension binaries and copied game DLLs.
It also excludes Microsoft Visual C++ runtime DLLs. Those runtime files are
installed on the user's Mac from Microsoft's official x86 and x64
redistributable downloads when required.

Rosetta and Apple technologies remain subject to Apple's terms. The standalone
DMG does not include the Ascension launcher installer, game client, or Ascension
artwork. The launcher is downloaded by the user from Ascension's official
endpoint on first launch. Project Ascension software and services remain subject
to Project Ascension's terms.

The macOS game compatibility payload is derived from WoWSilicon 2.5.5 and is
distributed under GNU GPL version 3. Its corresponding source is available at
https://github.com/WoWSilicon/WoWSilicon/tree/v2.5.5 and its full license is
included in the app under `Resources/runtime-patch/licenses/`.

The bundled D9VK `d3d9.dll` is distributed under the zlib/libpng license. Its
license notice is included alongside the WoWSilicon license. No Project
Ascension game executable or game DLL is included in the DMG; patched proxy
DLLs are generated locally from the user's launcher-managed installation.

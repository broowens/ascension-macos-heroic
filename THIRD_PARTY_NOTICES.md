# Third-party notices

The installer scripts in this repository are licensed under the MIT License.

The optional runner release asset contains third-party components under their
respective licenses, including Wine/CodeWeavers sources, FreeType, MoltenVK,
DXVK-related components, and their dependencies. Wine is distributed under the
GNU Lesser General Public License. Preserve the license files shipped in the
runner and publish the corresponding `crossover-sources-26.0.0.tar.gz` source
asset with each binary release.

The release builder excludes Project Ascension binaries and copied game DLLs.
It also excludes Microsoft Visual C++ runtime DLLs. Those runtime files are
obtained from the user's local Microsoft redistributable cache during install.

Rosetta and Apple technologies remain subject to Apple's terms. Project
Ascension assets remain subject to Project Ascension's terms.

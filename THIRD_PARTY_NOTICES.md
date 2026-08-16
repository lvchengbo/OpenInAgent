# Third-party notices

OpenInAgent is an independent implementation informed by three MIT-licensed
macOS utilities. Their licenses are preserved under `LICENSES/`.

## OpenInTerminal

- Project: <https://github.com/Ji4n1ng/OpenInTerminal>
- Reviewed reference: `537ac2a5ee69ae46d4948c9b259e067a0c179a5f`
- Used as a behavioral reference for the Finder Sync toolbar/menu structure,
  mounted-volume registration, selection-first Finder handling,
  file-to-parent semantics, terminal discovery, and argument-safe launching.
- Copyright (c) 2019 Jianing Wang. Some referenced source headers additionally
  credit Cameron Ingham.

## OpenInCode

- Project: <https://github.com/sozercan/OpenInCode>
- Reviewed reference: `fcc4c91e294fdd7532d500f7c113b88bca8ed0c2`
- Used as an early architectural reference for a one-shot `LSUIElement` host,
  URL normalization, SwiftPM testing, and local hardened-runtime signing.
- Copyright (c) 2016 Sertac Ozercan.

## ClaudeLauncher

- Project: <https://github.com/joelsommerer/ClaudeLauncher>
- Reviewed reference: `6774e4d2b3ed8fd908740e4c061aa9ef33eb42be`
- Used as a UX reference for the standalone fallback chooser’s lifecycle and
  dismissal behavior. OpenInAgent does not copy its automatic toolbar editor.
- Copyright (c) 2026 Joel Sommerer.

No upstream icons or product-logo assets are included. OpenInAgent’s sparkle
icon is generated from original vector geometry in `tools/render-icon.swift`.

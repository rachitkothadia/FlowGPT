# Publisher signing

FlowGPT cannot issue its own trusted Apple or Windows publisher certificate. A self-signed certificate would not solve warnings on a friend's computer. The developer must obtain real publisher credentials and configure them before the release can be described as signed and trusted.

## Windows

Obtain a Windows code-signing certificate from a trusted issuer, or use Microsoft's Artifact Signing service with the required account setup. This repository currently has no signing secrets configured.

For a PFX-backed certificate, add these repository Actions secrets:

- `WINDOWS_SIGNING_PFX_BASE64`: the certificate plus its private key, encoded as base64.
- `WINDOWS_SIGNING_PFX_PASSWORD`: the PFX password.

The Windows pipeline imports it into the temporary runner's Current User certificate store, signs and verifies the app, installer and uninstaller, timestamps the signatures, then removes the imported key. Signing fails closed if the certificate is expired, self-signed, or rejected by Windows trust verification. Private credentials are never committed or bundled. Hardware-backed signing services need their issuer's integration instead of exporting the private key.

Without those credentials, it explicitly builds an unsigned preview. An SHA-256 checksum verifies the downloaded bytes, not publisher identity. Even trusted signing does not guarantee that a new app will immediately have SmartScreen reputation.

## Mac

Enroll the developer in Apple's Developer Program and install the **Developer ID Application** certificate with its private key. Store notarization credentials with `xcrun notarytool store-credentials`, then run:

```sh
export FLOW_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
export FLOW_NOTARY_PROFILE="flowgpt-notary"
Scripts/build-distribution.sh
```

That distribution workflow signs both architectures, notarizes the app and DMG, staples the accepted tickets, and checks Gatekeeper before replacing the public artifact. It does not silently strip quarantine or reset microphone/accessibility/input-monitoring grants. No valid Developer ID identity is installed on the development Mac currently; the local test DMG therefore remains an ad hoc signed preview.

Mac **About → Download & open installer** currently verifies and opens the DMG. The user quits FlowGPT and replaces the app in Applications. It preserves the existing data folder, but this is not an automatic signed replacement/relaunch system.

# Public macOS distribution

The local `Scripts/build-flowgpt.sh` produces an ad hoc signed Apple Silicon installer. Downloaded copies can be blocked by Gatekeeper. Signing integrity and successful execution on the build Mac do not establish public distribution readiness.

## Prerequisites

- Active Apple Developer Program membership and a Developer ID Application certificate with its private key installed in the local keychain.
- Swift 6.2+, a compatible macOS SDK, `codesign`, `notarytool`, and `stapler`.
- A stored notarization credential profile. Store credentials interactively rather than putting a password in shell history:

```sh
xcrun notarytool store-credentials flowgpt-notary
```

Follow Apple's prompts using your own Apple ID, app-specific password, and Team ID, or configure an App Store Connect API key through Apple's supported tooling. Never commit credentials or certificate exports.

Check the available signing identity:

```sh
security find-identity -v -p codesigning
```

## Build and notarize

```sh
export FLOW_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
export FLOW_NOTARY_PROFILE="flowgpt-notary"
Scripts/build-distribution.sh
```

The script refuses ad hoc signing, checks the certificate and notarization profile before building, tests the package, compiles both architectures, combines them, signs the app with hardened runtime and microphone entitlement, and submits a zipped app to Apple. It staples and verifies the app before creating and signing the DMG, then notarizes and staples the DMG as well.

Logs stay in `release/distribution/`. The universal DMG goes directly in the project root only after successful notarization and verification. The installed app, saved session, and macOS privacy switches are not replaced by this workflow.

## Release acceptance

Mount the resulting DMG, copy its app into Applications on a separate Mac, and test the downloaded/quarantined copy. Check first launch, permissions, own-account login, cold/warm startup, microphone output, shortcut, and insertion into native and browser editors. Test Apple Silicon and Intel separately; a universal binary is not proof of Intel runtime behavior.

An account session can still expire and microphone/Accessibility/Input Monitoring grants must be given on each user's Mac. Notarization resolves distribution trust, not speech accuracy, account limits, or website compatibility.

References: [Apple Developer ID](https://developer.apple.com/developer-id/) · [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Apple safe app opening](https://support.apple.com/102445).

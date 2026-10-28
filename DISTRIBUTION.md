# Sharing Cleo

The complete transferable app is `Cleo.app`. A ZIP containing that bundle and a short `Read Me.txt` is sufficient; source files, sample photos, generated source sheets, diagnostics, compiler caches, and older builds are excluded.

The friend download targets **macOS 14 or later on Apple silicon and Intel Macs**. The universal executable contains native `arm64` and `x86_64` slices. Dependencies are macOS frameworks and the system Swift libraries; recipients do not need Xcode or another runtime. Both slices have been launched live on this Apple silicon Mac, with `x86_64` running under its already-installed Rosetta. No actual Intel Mac or macOS 14 machine has been used for live validation.

## Build the package

From this project directory:

```sh
./scripts/package.sh
```

This calls `scripts/build.sh --universal`, verifies both architectures and all required sprite resources, and packages the app without installing or launching it. If a fresh universal build is already available, use `./scripts/package.sh --skip-build`; it performs the same architecture and signature checks. The script never opens an app, accesses an account or keychain, publishes a release, or changes global developer settings.

Outputs under `build/distribution/`:

- `Cleo-1.0.0-macOS-universal-preview.zip`: the app and friend-facing instructions.
- A matching `-Install.txt`: the same instructions separately.
- A matching `.sha256`: ZIP integrity checksum.
- A matching `.json`: version, minimum macOS, architectures, signature status, size, and checksum.

The version comes from the built bundle, so filenames follow future version changes. The package is unpacked into a temporary local folder and its signature and architectures are verified again before the final files are saved. No unit or integration tests run.

To check a received archive's integrity, put its `.sha256` beside it and run `shasum -a 256 -c Cleo-1.0.0-macOS-universal-preview.sha256`. A checksum verifies the downloaded bytes, not the publisher's identity.

## Current signing status

The current build uses a valid **ad hoc signature**. It has no Developer ID authority or Team Identifier, and it is not a notarized release. Packaging preserves that signature and labels the output as a preview. The script does not contact Apple's notarization service or claim that Gatekeeper accepts the package.

For a trusted preview from someone they know, the recipient can extract the ZIP, move `Cleo.app` to Applications, and attempt to open it. If macOS blocks it, Apple's documented process is **System Settings → Privacy & Security → Open Anyway**, followed by **Open**. See [Apple's instructions](https://support.apple.com/en-us/102445). This does not require disabling Gatekeeper or removing quarantine attributes.

For the standard download experience without an unidentified-developer override, the remaining blocker is **Developer ID signing and notarization**. That requires an appropriate Apple Developer identity/private key, hardened-runtime signing with a timestamp, submission to Apple's notarization service, and a stapled ticket before repackaging. No signing identity, private key, keychain profile, or Apple account has been accessed for this packaging task. Account and key access need explicit task approval before proceeding.

## Delivery

The user approved public GitHub distribution, and **Cleo 1.0.0 was published on October 20, 2026** as a preview release:

- [Release and installation notes](https://github.com/Abhinav-Joshi/cleo-desktop/releases/tag/v1.0.0)
- [Download the universal macOS ZIP](https://github.com/Abhinav-Joshi/cleo-desktop/releases/download/v1.0.0/Cleo-1.0.0-macOS-universal-preview.zip)
- [Public download repository](https://github.com/Abhinav-Joshi/cleo-desktop)

The release includes the ZIP, install text, checksum, and metadata. The public repository contains download instructions; original photos and project source remain local. Publication was confirmed on GitHub's release page and asset listing. The uploaded ZIP is 564,593 bytes with SHA-256 `1044b418d2a749ed43b3a9c97d503dccc83f8324291f1f4c8e08177578442c35`.

`RELEASE-NOTES.md` contains the release description. The package script itself does not access accounts, upload, or publish.

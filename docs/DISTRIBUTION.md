# Distribution

The current alpha is built from source. `scripts/build-app.sh` produces an ad-hoc signed development app for the build machine's architecture. `scripts/package-app.py` now creates verified, versioned ZIP archives and checksums; ad-hoc apps require an explicit `--development` flag. Neither script creates a universal binary, Developer ID signature, or notarization ticket. There is no Homebrew cask yet.

This guide describes the proposed binary release process. Completion and acceptance belong in [PLAN.md](PLAN.md#distribution-readiness); ordinary developer commands belong in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Before Apple enrollment

Documentation, archive tooling, and version checks can be developed with the existing toolchain. The [local preview workflow](../CONTRIBUTING.md#packaging-a-local-preview) is implemented. Keep development artifacts clearly labeled. An ad-hoc signature is not evidence that a downloaded app will pass Gatekeeper.

Start with one versioned ZIP containing `iMCP-HTTP.app`, its embedded licenses, and a published SHA-256 checksum. A disk image can be added if a drag-to-Applications installer would help direct-download users. A privileged package installer is unnecessary for this app.

Choose and state the supported architectures. The current builder uses the host architecture. An Apple silicon release must be labeled accordingly; Intel or universal support needs its own build and runtime evidence. The minimum OS is macOS 15.

## Apple enrollment and signing

[Apple Developer Program enrollment](https://developer.apple.com/programs/enroll/) is required for the planned Developer ID distribution. Apple lists membership at USD 99 per year, with regional pricing and some fee waivers. Individuals need an Apple Account with two-factor authentication and identity verification; organizations have additional legal-entity requirements.

Use a [Developer ID Application certificate](https://developer.apple.com/developer-id/) for the app distributed outside the Mac App Store. No App Store listing is required. Keep private keys and notarization credentials in the signing machine's Keychain or a protected release environment, outside the repository.

The release pipeline still needs to implement and verify these steps:

1. Build an optimized app from the reviewed source revision and pinned dependencies. Retain `io.github.huglyfe.imcp-http` as the bundle identifier and increment the build number.
2. Sign embedded executable code from the inside out, then sign the app with Developer ID, Hardened Runtime, and a secure timestamp. Include the Apple Events entitlement required by Mail and Notes (`com.apple.security.automation.apple-events`). Review actual code and entitlement needs; do not use broad exceptions or `codesign --deep` as the signing strategy.
3. Verify signatures and embedded resources. Submit an archive using `xcrun notarytool`, wait for acceptance, and inspect any failures. See [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
4. Staple the accepted ticket to the app and validate it. Create the final ZIP from that stapled app; calculate the published checksum only after the final archive exists. A ZIP itself cannot be stapled.
5. Test the downloaded artifact through Gatekeeper on a clean Mac or test account, including offline launch after download. Test first permission requests, OAuth approval, and Mail/Notes Automation under Hardened Runtime.
6. Install a second signed build over the first after quitting it. Verify settings, grants, revocations, and Apple permissions. Also test the transition from an ad-hoc development install; do not promise that its permissions will carry over.

Signing and notarization do not grant Apple-data permissions or establish service correctness. Run the relevant disposable [native acceptance](PLAN.md#native-acceptance) on the packaged app.

## Homebrew

Use a **cask** to install the prebuilt Mac app. Start with a maintainer-owned [tap](https://docs.brew.sh/Taps), such as a future `huglyfe/homebrew-tap` repository. This keeps release timing under the maintainer's control.

Once that tap and a verified binary release exist, the intended command is:

```sh
# Planned command; the tap and cask are not published yet.
brew install --cask huglyfe/tap/imcp-http
```

The cask needs a version, immutable release download URL, SHA-256 checksum, name, description, homepage, minimum macOS version, architecture constraints, and `app "iMCP-HTTP.app"`. Follow the [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook). Use separate checksums for separate architecture archives. Do not use `sha256 :no_check` for versioned releases.

Validate the cask's syntax, style, audit results, installation, upgrade, and uninstall against the actual release artifact before advertising the command. Normal uninstall should preserve settings and grants. Any optional `zap` cleanup must explicitly describe that it removes local authorization state. Installation must not start a daemon, approve clients, grant permissions, or disable quarantine.

Publish the app release before updating the cask to its URL and checksum. Users can then update through Homebrew after quitting the app; an in-app updater is a separate feature.

Inclusion in the official `homebrew/cask` repository is a later submission, subject to its [acceptance policy](https://docs.brew.sh/Acceptable-Casks). That policy requires supported-platform compatibility, verifiable upstream downloads, Gatekeeper checks, and shared package acceptance criteria. A personal tap does not imply official Homebrew review or endorsement.

Creating a public release or tap requires the owner's explicit publication instruction. Preparing files locally does not publish them.

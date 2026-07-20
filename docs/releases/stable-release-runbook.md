# Stable release runbook

Stable GitHubBar releases are universal Developer ID applications with hardened runtime, Apple notarization and stapling, and Sparkle 2 updates protected by both Apple code signing and a maintainer-owned Ed25519 key. Validation builds remain a separate ad-hoc channel and cannot initialize Sparkle.

## One-time ownership and credentials

The maintainer—not an agent or repository—owns these credentials:

1. A Developer ID Application certificate for the Apple Developer team. Install it in the signing Keychain and record its exact `security find-identity -v -p codesigning` description as `GITHUBBAR_SIGNING_IDENTITY`.
2. Apple notarization credentials. For a workstation, create a named Keychain profile with `xcrun notarytool store-credentials`. For CI, use an App Store Connect Notary API key with the least required access and store the private key, key ID, and issuer ID as protected environment secrets.
3. A Sparkle Ed25519 key. Run Sparkle's `generate_keys --account com.franciscomoretti.githubbar` once on a trusted Mac. Back up the private key with `generate_keys --account com.franciscomoretti.githubbar -x <offline-file>`, protect that file like a password, and keep it outside the repository. The printed public key is configuration, not a secret.
4. A protected GitHub `stable-release` environment requiring maintainer approval. Store the base64 certificate, certificate password, ephemeral Keychain password, Notary API key material, and Sparkle private key as environment secrets. Never put them in workflow inputs, repository variables, release notes, or issue comments.

The stable appcast URL is:

```text
https://github.com/FranciscoMoretti/GitHubBar/releases/latest/download/appcast.xml
```

Only non-prerelease stable releases may be marked Latest. Their update archives use the immutable per-tag prefix `https://github.com/FranciscoMoretti/GitHubBar/releases/download/<tag>/`.

## Local stable build

Install full Xcode and XcodeGen. Install the Developer ID identity, store a `notarytool` profile, and import the Sparkle key into the login Keychain. Then run without shell tracing:

```sh
export GITHUBBAR_VERSION=1.0.0
export GITHUBBAR_BUILD_NUMBER=100
export GITHUBBAR_DEVELOPMENT_TEAM=YOUR_TEAM_ID
export GITHUBBAR_SIGNING_IDENTITY='Developer ID Application: Your Name (YOUR_TEAM_ID)'
export GITHUBBAR_NOTARY_PROFILE=GitHubBar
export GITHUBBAR_SPARKLE_PUBLIC_KEY='PUBLIC_BASE64_KEY'
export GITHUBBAR_SPARKLE_FEED_URL='https://github.com/FranciscoMoretti/GitHubBar/releases/latest/download/appcast.xml'
export GITHUBBAR_DOWNLOAD_URL_PREFIX='https://github.com/FranciscoMoretti/GitHubBar/releases/download/v1.0.0/'
scripts/package-stable.sh
```

The script fails closed if Xcode or credentials are absent, either architecture is missing, signing or hardened runtime is invalid, `get-task-allow` is present, notarization is not accepted, stapling/Gatekeeper fails, the Sparkle public/private keys differ, an update URL is not HTTPS, or the appcast lacks an Ed25519 signature.

## Publish and verify

The protected stable workflow imports secrets into an ephemeral Keychain, runs the same packaging script, and publishes the notarized ZIP, checksum, signed `appcast.xml`, and any deltas. Before approval:

- confirm `CFBundleVersion` increases monotonically;
- confirm the tag and immutable download prefix match;
- download the workflow artifact and run `codesign`, `spctl`, `stapler validate`, and `lipo -archs` independently;
- inspect the appcast enclosure URL, build number, minimum macOS, archive length, and `sparkle:edSignature`;
- scan workflow logs for accidental secret output before making the release public.

On a clean supported Mac, install the stable build without Gatekeeper bypass. Keep the previous stable installed on a second test account, publish a higher test build, and verify end to end that it discovers, downloads, verifies, installs, and relaunches. Do not call the release complete until this prior-to-new update succeeds.

## Failure recovery and rollback

- **Build or signing failure:** publish nothing. Fix the configuration and use a new, higher build number.
- **Notarization rejection:** do not staple or upload. Read the saved notary log, fix every signing/runtime finding, rebuild from a clean archive, and resubmit. Never staple a ticket from another build.
- **Bad release before appcast publication:** delete or mark the GitHub release as draft, leave the previous stable release as Latest, and do not upload its appcast.
- **Bad release after appcast publication:** immediately restore the previous signed appcast and mark the previous good release Latest. Then ship a corrected artifact with a higher `CFBundleVersion`; never reuse a released build number or mutate an archive behind an existing signature.
- **Notary credential compromise:** revoke the App Store Connect API key, remove the CI secret, audit Apple notarization history, and provision a replacement before another release.
- **Developer ID compromise:** contact Apple to revoke the certificate and notarization tickets as appropriate. Rotate to a new Developer ID identity and coordinate the Sparkle trust transition; do not rotate both Apple and Sparkle identities in the same update.
- **Sparkle key compromise:** remove the CI secret and Keychain item, restore the last trusted appcast, generate a new key offline, and ship a key-rotation update signed by the existing Developer ID identity. Sparkle permits trust rotation, but changing both the Apple identity and Ed25519 key in one update can strand installed clients.
- **Lost Sparkle key:** recover the offline backup. If recovery is impossible, use Sparkle's documented Developer ID-backed key rotation path and test from every supported prior stable version.

Record credential owners, creation dates, backup location, and revocation contacts in the maintainer's private password/secret system—not in this repository.

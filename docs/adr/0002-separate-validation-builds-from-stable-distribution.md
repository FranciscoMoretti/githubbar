---
status: accepted
---

# Separate validation builds from stable distribution

GitHubBar will use ad-hoc-signed GitHub prereleases while the MVP is being validated, with Sparkle disabled and updates installed manually. The first stable release must cross a hard trust gate: a universal macOS 14+ build signed with GitHubBar's Developer ID identity, hardened, notarized, stapled, and published through GitHub Releases with a dedicated Sparkle signing key and CodexBar-style stable update feed; this avoids paying the release-infrastructure cost before validation without normalizing an unsigned public product.

## Consequences

- Packaging has explicit validation and stable-release modes from the start; stable mode fails closed when signing or notarization credentials are unavailable.
- GitHub Releases is the only MVP distribution channel; the Mac App Store and Homebrew are deferred.
- CodexBar's MIT-licensed release and Sparkle mechanisms may be adapted, but its identities, bundle identifiers, repositories, and signing keys must never be reused.
- The stable bundle identifier is `com.franciscomoretti.githubbar`.

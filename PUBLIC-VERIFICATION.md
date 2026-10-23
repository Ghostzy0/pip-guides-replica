# Verification and limits

Experimental native macOS alpha. Baseline and Pip use the same original local capture/edit/export implementation with different presentation and separate app/data identities. No proprietary reference code/assets or private character engine is shipped.

Verified host: Apple Silicon arm64, macOS27.0.1, Xcode27.1/Swift6.4. Minimum source targetmacOS14; other hosts/Intel and accessibility tools are unverified.

- Latest current-source check: 12/12 Python integrity tests, 27/27 Swift tests in default and `BASELINE` modes, and all four local edition builds passed. Manifest `a4bbb120d7f434f41a6dc483080049d075c58b25824a2335a39438a6c3d6a25c`; see the source-check summary below. The packages were verified against current source, flags, plist identity, strict ad-hoc signatures and post-sign executable hashes. The latest rerun includes the replica capture-navigation guard and carries manifest `a4bbb120d7f434f41a6dc483080049d075c58b25824a2335a39438a6c3d6a25c`. This is dirty-worktree evidence only; clean public clone/export and native UI remain pending.
- The frozen baseline and Pip applications passed deep/strict ad-hoc signature verification. Their exact complete source identity is unknown and they predate current source. They are not Developer ID signed or notarised.
- Real native practice-window coordinate clicks created screenshots. Pause prevented an added step; resume added a step; stop/edit/reorder/save persisted. Pip reopened the same synthetic guide, permanently redacted an image and exported HTML using the native save dialog. Export contained3embedded PNGs and no external image URLs; stored primary/recovery images matched the flattened edit.
- Independent reviews found future-schema rollback, PDF title truncation, redaction crash-gap, clipped title controls and an encoded-file size mismatch. Data-safety fixes passed the20-test regression suite. Final clipped-field/fresh-practice appearance checks and clean-export/clone results remain pending before publication.

**Unverified:** clean-clone builds, external third-party-window capture with actual Screen Recording/Accessibility grants, custom secure controls/password detection in third-party apps, multiple displays, VoiceOver, extended performance, other Macs/OS versions. A frozen-package external test with both owner-enabled grants started successfully, but one clicked target action produced0saved steps after Stop; external capture acceptance failed for that run and its cause is unknown. The built-in practice window is a real native fixture but does not certify external capture. Neutral Core now selects the original `GUIDES_REPLICA` source adapter with documented public-tutorial hierarchy and local Step/Tip/Alert/Header cards; current local package checks have passed, but native UI acceptance remains pending. The public tutorial is not the current signed-in editor, so visual parity and paid desktop access remain unknown. Automatic prose descriptions, browser extensions and team services are outside this alpha.

Redaction flattens pixels and updates the current/recovery document after a successful save. Exported files, OS snapshots and external backups are separate copies. Local storage is permission-restricted, not encrypted by the app. Review screenshots before sharing. Markdown viewers may block embedded data images; HTML is the portable self-contained viewing format.


## Previous typed-content source check — 23 October 2026

After fixing versioned Step/Tip/Alert/Header persistence and typed insertion validation, ``scripts/check.sh`` passed 7/7 Python tests, 26/26 Swift tests in default and `BASELINE` modes, and all four receipt-bearing builds. Manifest SHA-256 `c5e382bbe3f1fea4538d896c0da0d2bacca286a11ffaafefec7d670ee6d2c9e7`. These are local dirty-worktree build checks only. Native UI and clean-clone/export remain pending. No current-source external-capture success is claimed; the frozen20 package's external click test saved zero steps despite passing permission gates and Start.


## Latest distribution and typed-content check — 23 October 2026

The full check passed 12/12 Python tests, 27/27 Swift tests in default and `BASELINE` modes, and built/verified all four local variants. It covers optional `distribution.json` default/allowed-variant selection and manifest binding, plus fail-closed unknown typed kinds in primary and backup files. Manifest `a4bbb120d7f434f41a6dc483080049d075c58b25824a2335a39438a6c3d6a25c`. Public clean-clone builds and current native walkthrough remain pending. The prior frozen20 external capture failed: both grants and Start worked but one real target click yielded zero saved steps.

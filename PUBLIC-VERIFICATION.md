# Verification and limits

Experimental macOS app. This follow-up updates the public source with an optional existing Apple Development signing selector, bounded capture-stage diagnostics, permission feedback based on the APIs' returned values, and a capture-status wrapping adjustment. It does not claim complete Scribe/Tango parity or a stable binary release.

## Candidate source checks

This public candidate is on branch `codex/guides-followup-20261025`. The exact candidate app-input manifest SHA-256 is `57c09dbc56529f60383ecb85547ab3155b1e059d926c3e906d70301bc9185734`. The shared engine input digest is `c70983c086599ccff3d0e5939073dc37592b2deb5e1f5f7d32e1131874a9ff49` in both the Neutral Core Replica and custom repositories. `SOURCE-INPUTS.json` records the pre-export source-input hashes; `SOURCE-MANIFEST.json` hashes the resulting public files; `SOURCE-PROVENANCE.json` binds those records to this product and the common engine. Candidate hosted CI is the verification gate for these changed sources. Until that exact candidate head's checks pass, do not treat the candidate source as CI-verified.

The updated permission feedback, capture-stage diagnostics and status wrapping have compile-level source evidence only; they have not been packaged or launched as this candidate. This follow-up also adds a **Check access** control that reports Screen Recording and Accessibility preflight values for the running build. Source review confirms it calls only `CGPreflightScreenCaptureAccess()` and `AXIsProcessTrusted()`; it does not call a request API, open System Settings or enumerate windows. The new control and messages remain pending exact-head CI and native UI verification. The candidate manifests below describe the prepared source; fresh exact-head hosted checks have not yet run. A source review or compile does not establish rendered feedback, permission behavior or capture acceptance.

## Bounded native evidence for the earlier frozen build

The only current native runtime evidence applies to frozen executable SHA-256 `e622199ee73d1e060f524aa718acd46adbccfa5de984eb863f9a53686db3dabc`, built from app-input manifest `0a75c8c63dcbf62208b95065fc9744136a5f3c3ad3d80b59745943f4c0bddf6f`. It does not apply to the source candidate above.

On that exact build, macOS Screen Recording preflight returned false while System Settings showed Pip Guides enabled for Screen & System Audio Recording and Accessibility. The cause and mapping of those settings rows to the running code identity remain unresolved; external enumeration and recording were not started in that preflight slice. No permission was changed.

A separate bounded walkthrough of the same frozen build and input used only its synthetic Sample practice window. A coordinate click created one picture and saved step; closing Sample stopped capture; guide and step text edits saved; cancelling the Open panel left the guide unchanged; and normal quit/relaunch with the same isolated synthetic data preserved the edits and picture. This accepts those Sample/editor/persistence/cancel/quit cases only. It does not validate external-window capture, permission inheritance, broad keyboard/accessibility/theme/export coverage or reference fidelity. Raw screenshots are not included in this repository.

The stable-signing selector has a separate two-build proof on the earlier source input above: two builds used the same existing Apple Development identity and had the same designated-requirement digest, with different executable hashes. This demonstrates the selector's signing continuity in that proof, not permission inheritance; the exact native preflight still returned false despite the enabled settings. The repository contains no certificate, private key, fingerprint value or identity name.

## Build and distribution limits

The Replica distribution contains only `baseline`. The custom distribution contains Neutral Plus (`baseline-enhanced`), Pip Core (`pip`) and Pip Plus (`pip-enhanced`). Both exports use the same shared Guides engine inputs; the edition configuration and product-specific presentation remain separately identified.

The workflow uses pinned checkout, read-only repository permissions, a bounded macOS runner and a sequential edition matrix. Pull requests and manual dispatch check the listed variants; branch-push checks are limited to `main`, avoiding duplicate push and PR matrices for feature branches. Hosted checks build the listed variants and verify their package receipts and signatures. Hosted CI does not constitute native UI or permission acceptance.

Packages built locally without a selected identity are ad-hoc signed and not notarised. The minimum source target is macOS 14; Intel, other Macs/OS versions, multiple displays, VoiceOver and extended performance remain unverified. No external packages, models, account, network client or telemetry are required.

Solid redaction replaces pixels in the local document after a successful save. Existing exports, snapshots and external backups remain separate copies. Local files are permission-restricted, not encrypted by the app. Review every picture before sharing.

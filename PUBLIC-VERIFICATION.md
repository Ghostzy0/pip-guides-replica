# Verification and limits

23 October 2026. **Experimental macOS alpha.** Manual authoring and file handling have automated and bounded native evidence. External-window capture remains unaccepted. No complete Scribe/Tango equivalence or stable release is claimed.

## Reproducible source and packages

On Apple Silicon, macOS27.0.1, Xcode27.1/Swift6.4, two fresh local Git exports were cloned into separate clean directories. In each clone, `scripts/check.sh` passed12 Python integrity tests and27 Swift tests in each of default and BASELINE modes. The Replica export built its one enabled edition; the custom export built Neutral Plus, Pip Core and Pip Plus. All four bundles passed strict ad-hoc signature, identity, compile-flag, source-manifest and executable-hash verification. These were local clean clones, not hosted CI or recording acceptance.

| Export | Tested source commit | Build-input SHA256 |
| --- | --- | --- |
| Replica | `0eec3e826a9efd792386d980216bbc30c86c4678` | `dcfe7af13c7664411382f1ce29d8a98d97c6c05994881d0265bdc3accf0248f0` |
| Custom | `c480b2026246720559bd079d8e21b170386cc2d1` | `f7e76d1ddb152a045f979788160d0a01dc68d3484e8d967fe3c0700e8f1dc75d` |

Both exports have common-engine SHA256 `9da282ed855fe3fc1428da79608b41f26029d768fc3c566797214116e08b26a8`. `SOURCE-PROVENANCE.json` and the source/file manifests explain their scope; `distribution.json` selects this repository's enabled editions. A later documentation-only commit does not extend this tested-code claim to changed source inputs. Final downloaded artifacts must be checked against their own release receipt.

Tests cover portable v1/v2 guides, future-format/kind refusal without backup rollback, typed insertion, bounded data, image processing, recovery/privacy journaling and escaped self-contained HTML/Markdown/PDF. The source has no external packages or bundled models. Packages are **locally ad-hoc signed, not Developer ID signed or notarised**. Minimum source target is macOS14; Intel, other Macs and older OS versions have not been accepted.

## Native workflow evidence

Earlier local native artifacts created actual screenshots from the built-in synthetic practice window. Pause prevented a step, Resume added one, and Stop/edit/reorder/save persisted the guide. A Pip artifact reopened it, permanently redacted an image and exported HTML through the native save dialog; the export contained3 embedded PNGs and no external image URLs. Those artifacts predate this source and their complete source identity is unavailable; they do not certify the rebuilt packages.

The current replica's synthetic typed insertion/save/reopen/copy was observed through native UI/accessibility. A later current Pip native check verified that the custom menu creates all four guide kinds and that entries persist after save/reopen. A coordinate click in the built-in Sample practice window produced the saved [synthetic practice screenshot](assets/practice-capture.png); it is a picture of the sample window, not editor UI or external-capture acceptance. The current binary's external Screen Recording preflight was blocked, so external capture has no current acceptance, no owner grant, and no verified third-party-window click. These later native checks do not change the tested source commits or package claims above.

## Open acceptance gaps

- A previous external-window test passed both native permission gates and started, but one real target click produced zero saved steps. The cause remains unisolated. Current external-window capture, secure-field protection in third-party apps and multiple displays are unverified. The practice window does not establish external capture acceptance.
- Current custom typed-menu interaction, fresh screenshots, light/dark/theme layout, keyboard/focus, VoiceOver and extended performance need runtime verification.
- The neutral replica uses an original vertical document editor informed by an official public tutorial. The current signed-in editor, paid desktop surfaces and exact visual parity were not observed. Browser extensions, automatic prose, GIF/rich text and team services are not implemented.

Solid redaction flattens pixels and replaces the current/recovery picture after a successful save. Existing exports, OS snapshots and external backups remain separate copies. Local files are permission-restricted, not encrypted by the app. Review every picture before sharing. Some Markdown viewers block embedded data images; HTML is the self-contained viewing option.

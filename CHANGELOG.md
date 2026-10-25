## Unreleased source follow-up · 25 October 2026

- Limited workflow push checks to `main`; feature branches retain exact pull-request checks and manual dispatch while the sequential edition matrix and permissions stay unchanged.

- Added an opt-in selector for an already-installed Apple Development signing identity; the default remains ad-hoc, invalid selections fail closed, and no signing identity or key is shipped.
- Improved capture-stage and permission-result feedback, plus wrapped capture status text. These changes are source candidates; native verification for this candidate remains pending.
- Added a read-only current-build access check that reports Screen Recording and Accessibility status without requesting permission or enumerating windows; native verification is pending.
- Updated public verification to distinguish the earlier frozen e622 Sample/editor evidence from external capture and from this changed source candidate.

# Changes

## 0.1.0-alpha.1 · 23 October 2026

Initial experimental Neutral Core Replica edition.

- Local guide library and portable editable files with atomic autosave and last-good recovery.
- Selected-window click capture, explicit pause/resume/stop and synthetic native practice workspace.
- Manual title/description editing, insert/reorder/delete, structural undo and image import.
- Flattened crop, solid redaction, blur and outline; click marker review/removal.
- Self-contained HTML/Markdown, paginated PDF and editable guide-file export.
- User-visible permission/recovery/save errors, keyboard commands, About/privacy/setup guidance.

Native evidence and current limitations are summarized in [public verification](PUBLIC-VERIFICATION.md). Source publication and a tested binary release remain distinct. No complete Scribe/Tango parity, notarisation, external secure-field certification or third-party ownership claim.

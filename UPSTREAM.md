# Foundations and references

Research checkpoint: 23 October 2026.

## Original native foundation

Pip Guides is original Swift/SwiftUI/AppKit code. Swift package has zero third-party package dependencies. Apple system frameworks: SwiftUI, AppKit, ScreenCaptureKit, ApplicationServices, CoreGraphics, ImageIO, CoreImage, CoreText; PDFKit is used only by tests. System frameworks are supplied by macOS and are not relicensed or copied into this repository. No network runtime, model, downloaded font or competitor asset is required.

## Wegweiser evaluation

Official repository: https://github.com/Sauerbac/Wegweiser
Pinned inspected HEAD: `effb4652f41693384a4407b83e599e529400309a`.

Its README identifies Windows 10/11, Tauri 2/SvelteKit/TypeScript/Rust, xcap and rdev. Documented behaviours include click screenshots, click markers, pause, library/autosave, step editing/reorder/delete, Markdown and self-contained HTML. The README states MIT; no standalone root LICENSE file was present in this inspected checkout. No source was copied, so this unresolved licence packaging does not enter Pip's distribution. No Windows SDK/host was available here; no Wegweiser build or observed native run is claimed. Reproducible original native baseline was chosen instead of pretending that Windows code had been ported or run on macOS.

Wegweiser's typed-key capture and whole-monitor behaviour are deliberately excluded from Pip's current window-only privacy scope. They remain documented parity differences.

## Proprietary behaviour references

- Scribe, https://scribehow.com and https://support.scribehow.com. Official documentation describes click-to-step recording, pause, redaction and exports. Pro documentation lists desktop recording, screenshot editing and advanced HTML/Markdown export. No paid trial started and no signed-in native run is claimed.
- Tango, https://help.tango.ai/en/articles/17359491-where-does-tango-work. Official help distinguishes browser capture from paid Pro/Enterprise desktop capture. Native hands-on reference parity remains unverified without eligible access.
- SmartPages: not reused. Commercial/noncommercial restrictions require a separate decision before any code adoption.

## Apple API references

- https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)
- https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
- https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)

The selected-window filter follows its window across displays; this documented API property is not a measured multiple-display result. Global mouse event observation does not read typed key values. Accessibility secure-control detection is conservative and not a universal secret detector.

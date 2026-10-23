# Native design decisions

The original edition is an independent original functional implementation with standard native SwiftUI/AppKit controls. It shares the data/capture/export engine with Pip. It is not Wegweiser or proprietary source. `BASELINE` builds preserve standard native styling. Pip styling follows the supplied design reference through original code; no reserved animation engine is imported.

## Task and layout

One local guide at a time: library → guide title/summary → ordered step list → selected step text/picture. Capture and export remain visible in the main header. Capture locks document replacement/editing until Stop; Pause/Resume/Stop are labelled. Manual authoring remains a complete workflow if external capture is denied. A native Sample practice surface is deliberately distinct from real external capture.

The workbench uses a sidebar, a narrow ordered-step column and a scrollable detail editor. Minimum 1000×680 native points; no phone layout is claimed. In short windows, details scroll instead of clipping primary actions. Status stays at the foot. Native open/save panels and platform menus preserve keyboard/focus behaviour. This is an intentional adaptation of web-only dropdown/title-bar recipes.

## Pip visual authority

Paper light canvas #FFFFFF, ink #121211, surface #FAFAFA, fill #F3F3F3, strong fill #EBEBEB, secondary text #555555, boundary #929292. Paper dark #0F0F0E / #F1F1EE / #171716 / #212120 / #2C2C2B / #A3A3A0. Other theme anchors follow the supplied nine-theme table. Selection grey, primary actions ink, no yellow-green general decoration. Character: original still pebble silhouette and two eyes; no claim of exact canonical geometry/motion. System SF font is a native fallback instead of redistributing an unverified Geist asset. SF Symbols replace the web Phosphor renderer through native framework APIs. No copied assets.

4-point spacing rhythm, 24-point page gutters, 16-point card padding, rounded 14/18-point surfaces and pill primary buttons. System focus rings, text editors and file controls remain functional. Body 15 native points, metadata 12–13, title 23–27. Appearance follows device or explicit light/dark; theme preferences are local. Baseline leaves native appearance unchanged.

## Motion and accessibility contract

Typing, list selection, navigation and detail swaps are immediate. No infinite loops, progress simulation, animated timers or decorative polling. One still decorative Pip; real recording/paused/stopped words expose state. Optional press feedback scales only the pressed control for 100 ms and respects native Reduce Motion. Native sheets retain OS lifecycle; app data never depends on animation completion. Keyboard commands are documented, image drag has percentage fields and a centre-area button, move up/down replaces drag-only reorder. Delete requires confirmation and offers structural Undo. Privacy edits deliberately discard earlier images/undo and explain why.

Runtime checks must separately cover Paper light/dark, a coloured theme, narrow/short native windows, large text, keyboard/focus, Reduce Motion and VoiceOver. Source tokens or a screenshot are not accessibility/performance certification.

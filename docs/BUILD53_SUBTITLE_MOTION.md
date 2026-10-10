# Build 53 — continuous lyric motion and timed ink

The owner rejected Build 52's blurred three-row treatment. This revision edits
its existing native rail and reader; it does not replace the player shell or
introduce a second playback clock, subtitle manager or recognition provider.

## Design

The compact Arabic ribbon uses 21 pt semibold text, a 480 ms zero-bounce settle,
soft viewport edges and clear context hierarchy. Context scales to 0.86; the
current row remains at its natural size and keeps a real scrolling viewport.
Persistent blur is removed. The full reader uses a 520 ms follow settle, a quiet
radial focus light and a restrained 0.97 context transform without reflow.

For documents with matching word text and word timestamps, SwiftUI's native
TextRenderer draws the normally shaped Arabic text, then reveals white ink
through the current word in that run's writing direction. Completed words stay
bright; future words stay quieter. The renderer animates existing clock samples
for 160 ms; there is no additional timer, periodic observer or queued transition.
Manual captions and V2 captions use the same existing line renderer. Phrase-only
captions remain phrase-based. If word text differs from the original, the full
original wins: punctuation or dialect spelling must never be silently lost.

Reduced Motion, background scenes and low-power mode disable transforms and ink
sweeping, preserving readable instant word focus. Android's existing reader uses
the same softer hierarchy and a 420 ms focus settle; its manual-caption reader
continues to use phrase-level focus, without invented word timings.

The Build 52 full-screen reader, controls/footer insets and track-change dismissal
are preserved. RootView, FullPlayerView, BottomBar and AdaptiveLayout are unchanged.
The approved physical-bottom navigation anchor remains 18/874, clamped 12–28.

## References

- [design-motion-principles](https://github.com/kylezantos/design-motion-principles):
  Jakub's production polish, Emil's restraint, asymmetric exits, interruptible
  springs and reduced motion. React/CSS recipes are adapted to the native stack.
- [taste-skill](https://github.com/Leonxlnx/taste-skill): targeted redesign within
  the existing stack, typographic hierarchy and preserving functional states.
- [awesome-claude-design](https://github.com/VoltAgent/awesome-claude-design):
  reference catalogue; no new framework or executable installer is used.
- [Good vs Great Animations](https://emilkowal.ski/ui/good-vs-great-animations):
  easing, matching ink/geometry and inspecting actual recorded frames.
- [SwiftUI TextRenderer](https://developer.apple.com/documentation/swiftui/textrenderer):
  custom drawing after native shaping, rather than splitting Arabic characters.

These are design sources, not evidence that any animation is objectively the
most beautiful. Current Apple Music documentation was reviewed for synchronized
lyric interaction; no claim of copying an unreleased Apple animation is made.

## Verification requirements

A new native recording uses five disposable timed manual-caption examples, never
user content or an ASR result. Release IPA/source are packaged before Debug
fixture injection. The recording must prove all five mounted phrases, actual RTL
TextRenderer runs with advancing time-derived ink, valid bounds, a live process
and zero broad player invalidations from the bounded review clock. Reduced motion
uses a disposable override of the decision input, not an OS-setting claim.

All four native device profiles check real gestures, long Arabic scroll, full
reader open/close, unavailable text, playback changes, main tabs and rotation.
Android changes require compilation, existing unit/lint checks and device UI
regressions. Delivery records actual runtime versions and unresolved failures;
Simulator evidence is not physical-device or recognizer-quality evidence.

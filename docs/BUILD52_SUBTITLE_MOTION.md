# Build 52 — subtitle focus motion

The owner requested subtitle animation on 9 October 2026, using the previously
supplied repositories. This is an edit of the existing SwiftUI rail/reader and
Compose reader, without a new playback clock, recognition provider or UI library.

## Motion decisions

- SwiftUI: a 0.32 s, zero-bounce spring moves the three-line rail and changes
  focus through opacity, at most 1.2 pt of context blur and a 0.96 context scale.
  The current Arabic line is sharp. Font size/weight and scroll-view identity
  stay constant when a phrase becomes active, preserving its wrapping.
- The current phrase keeps its full-height scroll viewport. Context is masked
  through a drawing transform; long current phrases remain manually scrollable.
  Context rows never intercept hit testing in the current phrase's scroll area.
  Entering context fades over 8 pt; leaving context only fades. At most three
  phrases are mounted, with no looping effect or separate timer.
- The full reader softly changes text opacity and its existing focus surface.
  The stable player shell presents that same reader and retains its manager and
  language binding; the shifted artwork rail no longer owns a modal presenter.
  The full text uses a native full-screen cover, so its layout proposal matches
  the visible window on iPad as well as iPhone. The fixed-track reader closes
  when playback changes to another track, preserving the caption/clock pairing. Its scroll view uses the presented page proposal for Arabic wrapping.
  Header controls and the verification footer reserve space with safe-area
  insets, so lyric content cannot displace them or the navigation toolbar.
  Playback following uses a 0.36 s zero-bounce settle. Manual dragging suspends
  following. Seeking can retarget motion rather than queue transitions.
- Existing word highlighting uses the document's timestamps. No word timings,
  lyrics, translations or new ASR results are invented by this visual change.
- Reduce Motion, an inactive scene and low-power mode remove the new iOS motion,
  blur and scale. Android uses its existing lifecycle/power/animator preference
  observer; focus color settles over 240 ms, or instantly when motion is disabled.
  Initial reader positioning is instant, and manual interaction stops following.
- Android's existing reader is moved out of AccountScreens.kt into
  ui/subtitles/SubtitleScreen.kt; the old implementation is removed. Arabic
  remains the default and displays with RTL direction, wrapping and no ellipsis.
  A compact landscape header reserves a scrollable caption viewport; actual
  reduced-motion UI tests check both orientations and the unchanged bottom bar.
- Build 51 navigation geometry, account/media contracts, caches and IDs are
  preserved. Navigation remains covered by independent golden and real UI tests.

## Supplied references

- [design-motion-principles](https://github.com/kylezantos/design-motion-principles/tree/4a9ca879f24a361f4dca4174fe2da0f67b5ddee3):
  Create workflow, Jakub polish and Emil restraint; blur as a focus signal,
  zero-bounce springs, subtler exits, interruptible state-driven motion,
  transform/opacity animation and mandatory reduced-motion handling.
- [taste-skill](https://github.com/Leonxlnx/taste-skill/tree/18dfc928b135629e0eddfdd445a06400d04ed439):
  redesign-existing-projects; targeted edits in the current stack, stable
  typography and hierarchy, no second implementation or framework migration.
- [awesome-claude-design](https://github.com/VoltAgent/awesome-claude-design/tree/8f746b5bbb69cc7544fa850c126a71f754091951):
  a design-reference catalogue. Its rule/token/rationale approach informs this
  record; Muwa retains its native typography and artwork-driven appearance.

The external repositories supply design guidance. Their React/CSS recipes are
not copied into native code and no executable installer is run.

## Evidence requirements

The native capture records the actual compiled Simulator application with five
disposable ordinary Arabic captions and a bounded, real-time review clock.
It does not run recognition or fetch user credentials/content. Release source
and IPA are packaged before test fixture injection. Each checkpoint checks the
mounted active index, source, preference and frame; the video is finalized and
its hash recorded. The iPhone 17 Pro capture also runs the reduced-motion
branch. Since the SDK environment value is read-only, the disposable review
copy overrides that boolean input for the rail and reader; it does not switch
the simulator's system setting. Release continues to read the real preference.

All four native interaction profiles retain navigation, rotation, reader
open/close, long Arabic scrolling, artwork paging, queue and playback checks.
A second long-Arabic scenario exercises the same reduced-motion decision input.
Android adds a cached Arabic reader test with animator scale zero, rapid seeking,
whole-phrase visibility, manual following suspension and the navigation anchor.
It restores the device setting and cached file after the test.

Record actual runtimes in the delivery report. Simulator/video fixtures do not
establish physical iOS 27.2 testing, ASR quality or corrected server transcripts.
